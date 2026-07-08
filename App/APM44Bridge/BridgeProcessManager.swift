import AppKit
import Foundation

enum BridgeRunState: Equatable {
    case idle
    case starting
    case running
    case stopping
    case reconnecting
    case error(String)
}

enum StopReason: Equatable {
    case user
    case settingsChange
    case hotplug
    case `internal`
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
    @Published private(set) var lastStopReason: StopReason?
    @Published var bannerMessage: String?

    private let lifecycle: BridgeLifecycleController
    private var stdoutBuffer = Data()
    private let stdoutCap = 64 * 1024
    private var lastXrunCount: UInt64 = 0
    private var glitchTask: Task<Void, Never>?
    private var staleTask: Task<Void, Never>?
    private var lastMetricsAt: Date?
    private var stderrLines: [String] = []
    private var restartTask: Task<Void, Never>?
    private var pendingRestartReason: StopReason?
    private var wasRunningBeforeDisconnect = false
    private var lastKnownDeviceName: String?
    private var lastKnownDeviceUid: String?

    private let binaryURLOverride: URL?
    private let applicationTerminator: @MainActor () -> Void

    let settings: BridgeSettings

    internal private(set) var hotplugRefreshGeneration = 0
    internal var retryGeneration: Int { lifecycle.retryGeneration }
    internal var testRetryDelays: [TimeInterval]? {
        get { lifecycle.testRetryDelays }
        set { lifecycle.testRetryDelays = newValue }
    }

    internal var testTerminationWaitTimeout: Duration? {
        get { lifecycle.testTerminationWaitTimeout }
        set { lifecycle.testTerminationWaitTimeout = newValue }
    }

    init(
        settings: BridgeSettings,
        processLauncher: ProcessLaunching? = nil,
        binaryURLOverride: URL? = nil,
        applicationTerminator: @escaping @MainActor () -> Void = { NSApplication.shared.terminate(nil) }
    ) {
        self.settings = settings
        self.lifecycle = BridgeLifecycleController(
            processLauncher: processLauncher ?? LiveProcessLauncher()
        )
        self.binaryURLOverride = binaryURLOverride
        self.applicationTerminator = applicationTerminator
    }

    var binaryURL: URL? { binaryURLOverride ?? BridgeBinaryLocator.resolve() }

    var isTransitioning: Bool {
        switch state {
        case .starting, .stopping: return true
        default: return false
        }
    }

    var deviceDisplayName: String {
        guard let uid = settings.outputDeviceUid else {
            return "Not selected"
        }
        if let row = devices.first(where: { $0.uid == uid }) {
            return row.name
        }
        // Fall back to the name cached by applyRefreshedDeviceList while the
        // device was last present (e.g. during a disconnect).
        if lastKnownDeviceUid == uid, let name = lastKnownDeviceName {
            return name
        }
        return "device"
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    internal func setDevicesForTesting(_ list: [AudioDeviceRow]) {
        devices = list
    }

    internal func setStateForTesting(_ newState: BridgeRunState) {
        state = newState
    }

    internal func setRetryAttemptForTesting(_ value: Int) {
        lifecycle.setRetryAttemptForTesting(value)
    }

    internal var testLaunchArgumentsOverride: [String]?
    internal var testTerminationStatus: Int32?
    internal var testDeviceListOverride: [AudioDeviceRow]?

    func refreshDevices() async {
        refreshRoutingMode()
        if let override = testDeviceListOverride {
            applyRefreshedDeviceList(override)
            return
        }
        guard let url = binaryURL else {
            bannerMessage = "Bridge not found — build or install apm44-bridge"
            return
        }
        do {
            let list = try await Task.detached {
                try DeviceCatalog.refresh(binaryURL: url)
            }.value
            applyRefreshedDeviceList(list)
        } catch {
            bannerMessage = "Could not list audio devices"
        }
    }

    internal func applyRefreshedDeviceListForTesting(_ list: [AudioDeviceRow]) {
        applyRefreshedDeviceList(list)
    }

    private func applyRefreshedDeviceList(_ list: [AudioDeviceRow]) {
        devices = list
        if let uid = settings.outputDeviceUid,
           !list.contains(where: { $0.uid == uid }),
           DeviceCatalog.isDeniedMonitoringDevice(uid: uid, name: lastKnownDeviceName ?? uid) {
            settings.outputDeviceUid = nil
            bannerMessage = "Previous output unavailable — select a device"
        } else if settings.outputDeviceUid == nil,
                  let preferred = DeviceCatalog.preferredDefault(from: list) {
            settings.outputDeviceUid = preferred.uid
            if let row = list.first(where: { $0.uid == preferred.uid }) {
                lastKnownDeviceName = row.name
                lastKnownDeviceUid = row.uid
            }
            if bannerMessage == "Previous output unavailable — select a device" {
                // keep stale-selection banner until user picks a device
            } else {
                bannerMessage = nil
            }
        } else if let uid = settings.outputDeviceUid,
                  let row = list.first(where: { $0.uid == uid }) {
            lastKnownDeviceName = row.name
            lastKnownDeviceUid = uid
            if bannerMessage != "Output disconnected — waiting for \(row.name)…" {
                bannerMessage = nil
            }
        }
    }

    func refreshRoutingMode() {
        routingMode = HalDriverDetector.isHalInstalled() ? .halVirtualDevice : .blackHoleFallback
        updateConnectionPhase()
    }

    func start(resetRetryAttempt: Bool = true) {
        switch state {
        case .idle, .error, .reconnecting: break
        default: return
        }
        if lifecycle.hasUnresolvedLiveProcess {
            if !lifecycle.forceStopUnresolvedProcess() {
                state = .error("Bridge did not stop")
                bannerMessage = "Bridge did not stop"
                return
            }
        }
        if resetRetryAttempt {
            lifecycle.cancelRetryTask()
            lifecycle.resetRetryAttempt()
        }
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
        resetMetricsState()
        lastXrunCount = 0

        let proc = lifecycle.makeProcess()
        proc.executableURL = url
        proc.arguments = testLaunchArgumentsOverride ?? buildArguments(outputUid: uid)

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
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
            try lifecycle.launch(proc)
            lifecycle.attachLaunchedProcess(proc, stdout: outPipe, stderr: errPipe)
            state = .running
            wasRunningBeforeDisconnect = false
            updateConnectionPhase()
            scheduleStaleWatch()
            drainPendingRestart()
        } catch {
            state = .error("Bridge could not start.")
        }
    }

    func stop() {
        wasRunningBeforeDisconnect = false
        lifecycle.cancelRetryTask()
        lifecycle.resetRetryAttempt()
        if lifecycle.isProcessActive {
            initiateStop(reason: .user)
            Task {
                let stopped = await finishStopWithEscalation()
                if !stopped {
                    failClosedAfterFailedStop()
                }
                _ = reapUnresolvedOrFailClosed()
            }
        } else if case .reconnecting = state {
            if !reapUnresolvedOrFailClosed() {
                return
            }
            state = .idle
            bannerMessage = nil
            lastStopReason = nil
            lifecycle.clearPipeHandlers()
        } else {
            _ = reapUnresolvedOrFailClosed()
        }
    }

    func stopAsync() async {
        wasRunningBeforeDisconnect = false
        lifecycle.cancelRetryTask()
        lifecycle.resetRetryAttempt()
        if lifecycle.isProcessActive {
            initiateStop(reason: .user)
            let stopped = await finishStopWithEscalation()
            if !stopped {
                failClosedAfterFailedStop()
            }
            _ = reapUnresolvedOrFailClosed()
        } else if case .reconnecting = state {
            if !reapUnresolvedOrFailClosed() {
                return
            }
            state = .idle
            bannerMessage = nil
            lastStopReason = nil
            lifecycle.clearPipeHandlers()
        } else {
            _ = reapUnresolvedOrFailClosed()
        }
    }

    func quitApplication() async {
        await stopAsync()
        // Never exit while an unresolved orphan may still own the output device.
        if lifecycle.hasUnresolvedLiveProcess {
            _ = reapUnresolvedOrFailClosed()
        }
        if lifecycle.hasUnresolvedLiveProcess {
            return
        }
        if case .error(let message) = state,
           message.localizedCaseInsensitiveContains("did not stop") {
            state = .idle
            bannerMessage = nil
            connectionPhase = .stopped
            lastStopReason = nil
        }
        applicationTerminator()
    }

    private func initiateStop(reason: StopReason) {
        lastStopReason = reason
        guard let proc = lifecycle.process else {
            transitionToIdle()
            return
        }
        state = .stopping
        if lifecycle.isLauncherRunning(proc) {
            if proc.isRunning {
                proc.terminate()
            }
        } else {
            handleTermination(proc)
        }
    }

    func restart(reason: StopReason) async {
        if let existing = restartTask {
            pendingRestartReason = reason
            await existing.value
            return
        }

        switch state {
        case .starting, .stopping:
            pendingRestartReason = reason
            return
        default:
            break
        }

        let task = Task { @MainActor in
            await self.performRestart(reason: reason)
        }
        restartTask = task
        await task.value
        restartTask = nil

        while let pending = pendingRestartReason {
            pendingRestartReason = nil
            await restart(reason: pending)
        }
    }

    func restartForSettingsChange() async {
        await restart(reason: .settingsChange)
    }

    private func performRestart(reason: StopReason) async {
        switch state {
        case .idle, .error:
            return
        case .running, .reconnecting:
            break
        default:
            return
        }

        lastStopReason = reason
        if lifecycle.isProcessActive {
            let stopped = await terminateProcessWithEscalation(reason: reason)
            if !stopped {
                failClosedAfterFailedStop()
                return
            }
        } else if lifecycle.hasUnresolvedLiveProcess {
            if !lifecycle.forceStopUnresolvedProcess() {
                failClosedAfterFailedStop()
                return
            }
        }

        start()
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
        await refreshDevices()
        hotplugRefreshGeneration += 1

        guard let uid = settings.outputDeviceUid else {
            if isRunning {
                wasRunningBeforeDisconnect = false
                bannerMessage = "Output disconnected — select a device"
                let stopped = await terminateProcessWithEscalation(reason: .hotplug)
                if !stopped {
                    failClosedAfterFailedStop()
                    return
                }
                state = .error("Output device disconnected")
            }
            return
        }

        let devicePresent = devices.contains(where: { $0.uid == uid })

        if isRunning {
            if devicePresent {
                bannerMessage = "Reconnecting to \(deviceDisplayName)…"
                await restart(reason: .hotplug)
            } else {
                wasRunningBeforeDisconnect = true
                let stopped = await terminateProcessWithEscalation(reason: .hotplug)
                if !stopped {
                    failClosedAfterFailedStop()
                    return
                }
                state = .reconnecting
                bannerMessage = "Output disconnected — waiting for \(deviceDisplayName)…"
            }
            return
        }

        if case .reconnecting = state {
            if devicePresent, wasRunningBeforeDisconnect {
                bannerMessage = "Reconnecting to \(deviceDisplayName)…"
                await restart(reason: .hotplug)
                if isRunning {
                    wasRunningBeforeDisconnect = false
                }
            }
            return
        }

        // Idle: refresh only; never auto-start.
    }

    private func buildArguments(outputUid: String) -> [String] {
        let ms = settings.effectiveTargetFillMs(halMode: routingMode == .halVirtualDevice)
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
        case .idle, .stopping, .reconnecting:
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

    internal func appendStderrForTesting(_ text: String) {
        appendStderr(text)
    }

    internal func applyMetricsForTesting(_ snapshot: BridgeMetricsSnapshot) {
        applyMetrics(snapshot)
    }

    internal func markMetricsStaleForTesting() {
        metricsStale = true
    }

    internal var hasLastMetricsTimestampForTesting: Bool {
        lastMetricsAt != nil
    }

    private func isRecoverableStaleRingExit(status: Int32, stderr: String) -> Bool {
        status == 42 && stderr.localizedCaseInsensitiveContains("stale shm ring")
    }

    internal func bridgeFailureMessageForTesting(defaultMessage: String) -> String {
        bridgeFailureMessage(defaultMessage: defaultMessage)
    }

    private func bridgeFailureMessage(defaultMessage: String) -> String {
        let stderr = stderrLines.joined(separator: "\n")
        if stderr.localizedCaseInsensitiveContains("stale shm ring") {
            return "APM44 driver IPC failed. Reinstall the matching driver and reload Core Audio."
        }
        if stderr.localizedCaseInsensitiveContains("shm") {
            return "APM44 driver IPC failed. Reinstall the matching driver and reload Core Audio."
        }
        if let last = stderrLines.last, !last.isEmpty {
            return last
        }
        return defaultMessage
    }

    private func resetMetricsState() {
        latestMetrics = nil
        lastMetricsAt = nil
        metricsStale = false
    }

    @discardableResult
    private func finishStopWithEscalation() async -> Bool {
        await lifecycle.finishStopWithEscalation { [weak self] in
            self?.state == .idle
        }
    }

    @discardableResult
    private func terminateProcessWithEscalation(reason: StopReason) async -> Bool {
        initiateStop(reason: reason)
        return await finishStopWithEscalation()
    }

    /// User-stop / quit / hotplug path must not remain wedged or pretend stop succeeded.
    private func failClosedAfterFailedStop() {
        staleTask?.cancel()
        wasRunningBeforeDisconnect = false
        resetMetricsState()
        state = .error("Bridge did not stop")
        bannerMessage = "Bridge did not stop"
        connectionPhase = .stopped
        pendingRestartReason = nil
    }

    /// Force-stop a previously dropped handle. Returns false when an orphan remains live.
    @discardableResult
    private func reapUnresolvedOrFailClosed() -> Bool {
        guard lifecycle.hasUnresolvedLiveProcess else { return true }
        if lifecycle.forceStopUnresolvedProcess() {
            return true
        }
        failClosedAfterFailedStop()
        return false
    }

    private func transitionToIdle() {
        lifecycle.clearPipeHandlers()
        resetMetricsState()
        state = .idle
        connectionPhase = .stopped
        lastStopReason = nil
        lifecycle.resumeTerminationWaiters()
        drainPendingRestart()
    }

    private func drainPendingRestart() {
        guard let pending = pendingRestartReason else { return }
        pendingRestartReason = nil
        Task { await restart(reason: pending) }
    }

    private func scheduleAutoRetry() {
        lifecycle.scheduleAutoRetry(
            setReconnectingBanner: { [weak self] attempt, maxAttempts in
                guard let self else { return }
                self.state = .reconnecting
                self.bannerMessage = "Reconnecting… (attempt \(attempt) of \(maxAttempts))"
            },
            setExhausted: { [weak self] message in
                guard let self else { return }
                self.state = .error(message)
                self.bannerMessage = message
            },
            isStillReconnecting: { [weak self] in
                guard let self else { return false }
                if case .reconnecting = self.state { return true }
                return false
            },
            attemptStart: { [weak self] in
                guard let self else { return false }
                self.start(resetRetryAttempt: false)
                return self.isRunning
            }
        )
    }

    private func handleTermination(_ proc: Process) {
        lifecycle.clearPipeHandlers()
        _ = lifecycle.takeProcess()
        lifecycle.clearUnresolvedProcess()
        staleTask?.cancel()
        if case .stopping = state {
            transitionToIdle()
            return
        }
        let exitStatus = testTerminationStatus ?? proc.terminationStatus
        testTerminationStatus = nil
        let stderr = stderrLines.joined(separator: "\n")
        let recoverableStale = isRecoverableStaleRingExit(status: exitStatus, stderr: stderr)

        if exitStatus != 0, case .running = state {
            if lastStopReason != .user {
                scheduleAutoRetry()
            } else {
                lastStopReason = nil
                let message = bridgeFailureMessage(defaultMessage: "Lost connection to bridge.")
                state = .error(message)
                bannerMessage = message
            }
            connectionPhase = .stopped
            lifecycle.resumeTerminationWaiters()
            return
        } else if case .running = state {
            transitionToIdle()
            return
        } else if case .starting = state {
            if recoverableStale, lastStopReason != .user {
                scheduleAutoRetry()
            } else {
                lastStopReason = nil
                state = .error(bridgeFailureMessage(defaultMessage: "Bridge could not start."))
            }
        }
        connectionPhase = .stopped
        lifecycle.resumeTerminationWaiters()
    }

}
