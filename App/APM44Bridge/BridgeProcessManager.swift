import Foundation

enum BridgeRunState: Equatable {
    case idle
    case starting
    case running
    case stopping
    case error(String)
}

@MainActor
final class BridgeProcessManager: ObservableObject {
    @Published private(set) var state: BridgeRunState = .idle
    @Published private(set) var latestMetrics: BridgeMetricsSnapshot?
    @Published private(set) var glitchFlash = false
    @Published private(set) var metricsStale = false
    @Published private(set) var devices: [AudioDeviceRow] = []
    @Published private(set) var routingMode: RoutingMode = .blackHoleFallback
    @Published private(set) var connectionPhase: BridgeConnectionPhase = .stopped
    @Published var bannerMessage: String?

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stdoutBuffer = Data()
    private let stdoutCap = 64 * 1024
    private var lastXrunCount: UInt64 = 0
    private var glitchTask: Task<Void, Never>?
    private var staleTask: Task<Void, Never>?
    private var lastMetricsAt: Date?
    private var stderrLines: [String] = []

    let settings: BridgeSettings

    init(settings: BridgeSettings) {
        self.settings = settings
    }

    var binaryURL: URL? { BridgeBinaryLocator.resolve() }

    var deviceDisplayName: String {
        guard let uid = settings.outputDeviceUid,
              let row = devices.first(where: { $0.uid == uid }) else {
            return "Not selected"
        }
        return row.name
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    func refreshDevices() async {
        refreshRoutingMode()
        guard let url = binaryURL else {
            bannerMessage = "Bridge not found — build or install apm44-bridge"
            return
        }
        do {
            let list = try await Task.detached {
                try DeviceCatalog.refresh(binaryURL: url)
            }.value
            devices = list
            if settings.outputDeviceUid == nil,
               let preferred = DeviceCatalog.preferredDefault(from: list) {
                settings.outputDeviceUid = preferred.uid
            }
            bannerMessage = nil
        } catch {
            bannerMessage = "Could not list audio devices"
        }
    }

    func refreshRoutingMode() {
        routingMode = HalDriverDetector.isHalInstalled() ? .halVirtualDevice : .blackHoleFallback
        updateConnectionPhase()
    }

    func start() {
        guard case .idle = state else { return }
        guard let url = binaryURL else {
            state = .error("Bridge not found — build or install apm44-bridge")
            return
        }
        guard let uid = settings.outputDeviceUid, !uid.isEmpty else {
            state = .error("Select an output device")
            return
        }

        state = .starting
        connectionPhase = routingMode == .halVirtualDevice ? .waitingForDAW : .connected
        stderrLines.removeAll()
        latestMetrics = nil
        lastXrunCount = 0
        metricsStale = false

        let proc = Process()
        proc.executableURL = url
        proc.arguments = buildArguments(outputUid: uid)

        let outPipe = Pipe()
        stdoutPipe = outPipe
        proc.standardOutput = outPipe
        let errPipe = Pipe()
        proc.standardError = errPipe
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.appendStderr(text)
            }
        }

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                self?.consumeStdout(data)
            }
        }

        proc.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                self?.handleTermination(finished)
            }
        }

        do {
            try proc.run()
            process = proc
            state = .running
            updateConnectionPhase()
            scheduleStaleWatch()
        } catch {
            state = .error("Bridge could not start.")
        }
    }

    func stop() {
        guard let proc = process else {
            state = .idle
            return
        }
        state = .stopping
        proc.terminate()
    }

    func toggle() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    func handleHotplug() async {
        refreshRoutingMode()
        guard isRunning else { return }
        await refreshDevices()
        guard let uid = settings.outputDeviceUid else {
            bannerMessage = "Output disconnected — select a device"
            stop()
            return
        }
        if devices.contains(where: { $0.uid == uid }) {
            bannerMessage = "Reconnecting to \(deviceDisplayName)…"
            stop()
            try? await Task.sleep(nanoseconds: 200_000_000)
            start()
        } else {
            state = .error("Output device disconnected")
            bannerMessage = "Output disconnected — select a device"
            stop()
        }
    }

    private func buildArguments(outputUid: String) -> [String] {
        let ms = settings.effectiveTargetFillMs
        let quality = settings.effectiveSrcQuality.cliArgument
        var args: [String] = [
            "--output-device", outputUid,
            "--target-fill-ms", String(format: "%.0f", ms),
            "--src-quality", quality,
            "--metrics-json",
        ]
        if routingMode == .halVirtualDevice {
            args.insert("--virtual-device", at: 0)
        }
        return args
    }

    private func consumeStdout(_ chunk: Data) {
        stdoutBuffer.append(chunk)
        if stdoutBuffer.count > stdoutCap {
            stdoutBuffer.removeFirst(stdoutBuffer.count - stdoutCap)
        }
        guard let text = String(data: stdoutBuffer, encoding: .utf8) else { return }
        var lines = text.components(separatedBy: "\n")
        if !text.hasSuffix("\n"), let last = lines.popLast() {
            stdoutBuffer = Data(last.utf8)
        } else {
            stdoutBuffer = Data()
        }
        for line in lines where !line.isEmpty {
            if let snapshot = MetricsParser.parse(line: line) {
                applyMetrics(snapshot)
            }
        }
    }

    private func applyMetrics(_ snapshot: BridgeMetricsSnapshot) {
        if snapshot.xruns > lastXrunCount {
            triggerGlitchFlash()
        }
        lastXrunCount = snapshot.xruns
        latestMetrics = snapshot
        lastMetricsAt = Date()
        metricsStale = false
        updateConnectionPhase()
    }

    private func updateConnectionPhase() {
        switch state {
        case .idle, .stopping:
            connectionPhase = .stopped
        case .starting:
            connectionPhase = routingMode == .halVirtualDevice ? .waitingForDAW : .connected
        case .error:
            connectionPhase = .stopped
        case .running:
            guard let metrics = latestMetrics else {
                connectionPhase = routingMode == .halVirtualDevice ? .waitingForDAW : .running
                return
            }
            let target = max(metrics.targetFillMs, 1.0)
            if metrics.fillMs < 2.0 {
                connectionPhase = .waitingForDAW
            } else if metrics.fillMs < target * 0.5 {
                connectionPhase = .connected
            } else {
                connectionPhase = .running
            }
        }
    }

    private func triggerGlitchFlash() {
        glitchFlash = true
        glitchTask?.cancel()
        glitchTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            glitchFlash = false
        }
    }

    private func scheduleStaleWatch() {
        staleTask?.cancel()
        staleTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard isRunning else { continue }
                if let last = lastMetricsAt, Date().timeIntervalSince(last) > 2 {
                    metricsStale = true
                }
            }
        }
    }

    private func appendStderr(_ text: String) {
        for line in text.split(separator: "\n") {
            stderrLines.append(String(line))
            if stderrLines.count > 20 {
                stderrLines.removeFirst()
            }
        }
    }

    private func bridgeFailureMessage(defaultMessage: String) -> String {
        let stderr = stderrLines.joined(separator: "\n")
        if stderr.localizedCaseInsensitiveContains("shm") {
            return "APM44 driver IPC failed. Reinstall the matching driver and reload Core Audio."
        }
        if let last = stderrLines.last, !last.isEmpty {
            return last
        }
        return defaultMessage
    }

    private func handleTermination(_ proc: Process) {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        process = nil
        staleTask?.cancel()
        if case .stopping = state {
            state = .idle
            connectionPhase = .stopped
            return
        }
        if proc.terminationStatus != 0, case .running = state {
            let message = bridgeFailureMessage(defaultMessage: "Lost connection to bridge.")
            state = .error(message)
            bannerMessage = message
        } else if case .running = state {
            state = .idle
        } else if case .starting = state {
            state = .error(bridgeFailureMessage(defaultMessage: "Bridge could not start."))
        }
        connectionPhase = .stopped
    }

}
