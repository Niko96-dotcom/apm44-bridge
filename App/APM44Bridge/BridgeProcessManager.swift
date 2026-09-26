import AppKit
import Foundation
import Darwin
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.niko.apm44.menu",
    category: "Bridge"
)

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

enum BridgeProcessHealth: Equatable {
    case stopped
    case spawning
    case handshaking
    case stable
}

@MainActor
final class BridgeProcessManager: ObservableObject {
    static let loadedDriverBuildMismatchExitStatus: Int32 = 44
    @Published private(set) var state: BridgeRunState = .idle
    @Published private(set) var latestMetrics: BridgeMetricsSnapshot?
    @Published private(set) var glitchFlash = false
    @Published private(set) var metricsStale = false
    @Published private(set) var devices: [AudioDeviceRow] = []
    @Published private(set) var routingMode: RoutingMode = .blackHoleFallback
    @Published private(set) var connectionPhase: BridgeConnectionPhase = .stopped
    @Published private(set) var lastStopReason: StopReason?
    @Published private var noticeMessage: String?
    @Published private(set) var isApplyingSettings = false
    @Published private(set) var cachedAppBuildID: String?
    @Published private(set) var cachedDriverBuildID: String?
    @Published private(set) var cachedBinaryURL: URL?

    var bannerMessage: String? {
        get {
            if let noticeMessage { return noticeMessage }
            guard retryAttempt > 0 else { return nil }
            switch state {
            case .idle, .stopping: return nil
            default: break
            }
            if retryAttempt >= maxUnhealthyLaunches { return exhaustedRetryMessage() }
            return AppStrings.reconnectingAttempt(current: retryAttempt, max: maxUnhealthyLaunches)
        }
        set { noticeMessage = newValue }
    }

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var parentWatchPipe: Pipe?
    private var stdoutBuffer = Data()
    private let stdoutCap = 64 * 1024
    private var lastKnownFrameLoss: UInt64 = 0
    private var glitchTask: Task<Void, Never>?
    private var staleTask: Task<Void, Never>?
    private var lastMetricsAt: Date?
    private var stderrLines: [String] = []
    private var terminationContinuations: [CheckedContinuation<Void, Never>] = []
    private var restartTask: Task<Void, Never>?
    private var pendingRestartReason: StopReason?
    private var wasRunningBeforeDisconnect = false
    private var lastKnownDeviceName: String?
    private var lastKnownDeviceUid: String?
    private var runningOutputFingerprint: AudioDeviceRow?
    @Published private var retryAttempt = 0
    private let maxUnhealthyLaunches = 4
    private var retryTask: Task<Void, Never>?
    private var stabilityTask: Task<Void, Never>?
    private var processHealth: BridgeProcessHealth = .stopped
    private var lastUnexpectedExitStatus: Int32?
    private var lastUnexpectedStderr: String?
    private var resumeAfterSystemWake = false
    /// Lifetime observers; the manager outlives the app, so the tokens are
    /// retained without explicit removal.
    private var outputDeviceObserver: NSObjectProtocol?
    private var willInstallUpdateObserver: NSObjectProtocol?

    private let processLauncher: ProcessLaunching
    private let binaryURLOverride: URL?
    private let applicationTerminator: @MainActor () -> Void

    let settings: BridgeSettings

    internal private(set) var hotplugRefreshGeneration = 0
    internal private(set) var retryGeneration = 0
    internal var testRetryDelays: [TimeInterval]?
    internal var testStabilityWindow: TimeInterval?

    private var retryDelays: [TimeInterval] {
        testRetryDelays ?? [1.0, 2.0, 4.0, 4.0]
    }

    private var stabilityWindow: TimeInterval {
        testStabilityWindow ?? 15.0
    }

    init(
        settings: BridgeSettings,
        processLauncher: ProcessLaunching? = nil,
        binaryURLOverride: URL? = nil,
        applicationTerminator: @escaping @MainActor () -> Void = { NSApplication.shared.terminate(nil) }
    ) {
        self.settings = settings
        self.processLauncher = processLauncher ?? LiveProcessLauncher()
        self.binaryURLOverride = binaryURLOverride
        self.applicationTerminator = applicationTerminator
        self.cachedBinaryURL = binaryURLOverride ?? BridgeBinaryLocator.resolve()
        // Restore the persisted device name so deviceDisplayName can show it
        // while the selected output is absent (e.g. right after relaunch).
        if let remembered = settings.outputDeviceName, !remembered.isEmpty {
            lastKnownDeviceName = remembered
            lastKnownDeviceUid = settings.outputDeviceUid
        }
        // BridgeSettings posts synchronously from its @Published didSet on
        // the main thread, so queue:nil delivers synchronously and the cache
        // stays in lockstep without an async hop.
        outputDeviceObserver = NotificationCenter.default.addObserver(
            forName: .apm44OutputDeviceChanged,
            object: nil,
            queue: nil
        ) { [weak self] note in
            MainActor.assumeIsolated {
                let raw = note.userInfo?["uid"] as? String
                self?.handleOutputDeviceChange(uid: raw?.isEmpty == false ? raw : nil)
            }
        }
        // Declared by SparkleUpdateController; posted when an in-app update
        // starts installing so a running bridge can resume after relaunch.
        willInstallUpdateObserver = NotificationCenter.default.addObserver(
            forName: .apm44WillInstallUpdate,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWillInstallUpdate()
            }
        }
    }

    var binaryURL: URL? { binaryURLOverride ?? cachedBinaryURL }

    /// Cached readiness for SwiftUI body paths: computed purely from
    /// cached/published state, never probing Core Audio, disk, or the
    /// file system. Caches refresh in refreshRoutingMode(),
    /// refreshDevices(), and start().
    var startBlockedReason: String? {
        BridgeStartReadiness.blockedReason(
            binaryMissing: binaryURL == nil,
            selectedUid: settings.outputDeviceUid,
            devices: devices,
            lastKnownName: deviceDisplayName,
            halDevicePresent: routingMode == .halVirtualDevice,
            appBuildID: cachedAppBuildID,
            driverBuildID: cachedDriverBuildID
        )
    }

    var isTransitioning: Bool {
        switch state {
        case .starting, .stopping: return true
        default: return false
        }
    }

    var deviceDisplayName: String {
        guard let uid = settings.outputDeviceUid else {
            return AppStrings.outputNotSelected
        }
        if let row = devices.first(where: { $0.uid == uid }) {
            return row.name
        }
        // Fall back to the name cached by applyRefreshedDeviceList while the
        // device was last present (e.g. during a disconnect).
        if lastKnownDeviceUid == uid, let name = lastKnownDeviceName {
            return name
        }
        return AppStrings.selectedOutput
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// Pure launch-automation decision: start only from idle with no blocker.
    /// Read by the launch Task after the initial refresh; the defaults key
    /// itself is checked at the call site and never persisted here.
    nonisolated static func shouldAutomationStart(
        state: BridgeRunState,
        blockedReason: String?
    ) -> Bool {
        guard state == .idle else { return false }
        return blockedReason == nil
    }

    internal func setDevicesForTesting(_ list: [AudioDeviceRow]) {
        devices = list
    }

    internal func setRoutingModeForTesting(_ mode: RoutingMode) {
        routingMode = mode
    }

    internal func setStateForTesting(_ newState: BridgeRunState) {
        state = newState
    }

    internal func setRetryAttemptForTesting(_ value: Int) {
        retryAttempt = value
    }

    internal var retryAttemptForTesting: Int { retryAttempt }
    internal var processHealthForTesting: BridgeProcessHealth { processHealth }

    internal var testTerminationStatus: Int32?
    internal var testDeviceListOverride: [AudioDeviceRow]?
    /// Injectable HAL build check for deterministic tests:
    /// `(halPresent, appID, driverID)`. When nil, `start()` reads the live
    /// HAL enumeration and the two small Info.plists. No helper commands run.
    internal var halBuildCheckOverride: (halPresent: Bool, appID: String?, driverID: String?)? {
        didSet {
            if let override = halBuildCheckOverride {
                updateReadinessCaches(
                    halPresent: override.halPresent,
                    appID: override.appID,
                    driverID: override.driverID
                )
            }
        }
    }

    private func updateReadinessCaches(halPresent: Bool, appID: String?, driverID: String?) {
        let mode: RoutingMode = halPresent ? .halVirtualDevice : .blackHoleFallback
        if routingMode != mode { routingMode = mode }
        if cachedAppBuildID != appID { cachedAppBuildID = appID }
        if cachedDriverBuildID != driverID { cachedDriverBuildID = driverID }
    }

    private func resolveCachedBinaryURL() {
        guard binaryURLOverride == nil else { return }
        let resolved = BridgeBinaryLocator.resolve()
        if cachedBinaryURL != resolved { cachedBinaryURL = resolved }
    }

    private func settleApplyingSettings() {
        if restartTask == nil, pendingRestartReason == nil, isApplyingSettings {
            isApplyingSettings = false
        }
    }

    @discardableResult
    func refreshDevices() async -> Bool {
        hotplugRefreshGeneration += 1
        let refreshGeneration = hotplugRefreshGeneration
        refreshRoutingMode()
        resolveCachedBinaryURL()
        if let override = testDeviceListOverride {
            applyRefreshedDeviceList(override)
            return true
        }
        guard let url = binaryURL else {
            logger.error("Device list refresh blocked: missing binary")
            bannerMessage = AppStrings.bridgeNotFound
            return false
        }
        do {
            let list = try await Task.detached {
                try DeviceCatalog.refresh(binaryURL: url)
            }.value
            guard refreshGeneration == hotplugRefreshGeneration else {
                return false
            }
            applyRefreshedDeviceList(list)
            return true
        } catch {
            if refreshGeneration == hotplugRefreshGeneration {
                logger.error("Device list refresh failed")
                bannerMessage = AppStrings.couldNotListDevices
            }
            return false
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
            bannerMessage = AppStrings.previousOutputSelect
        } else if settings.outputDeviceUid == nil,
                  let preferred = DeviceCatalog.preferredDefault(from: list) {
            settings.outputDeviceUid = preferred.uid
            if let row = list.first(where: { $0.uid == preferred.uid }) {
                lastKnownDeviceName = row.name
                lastKnownDeviceUid = row.uid
                settings.outputDeviceName = row.name
            }
            if bannerMessage == AppStrings.previousOutputSelect {
                // keep stale-selection banner until user picks a device
            } else {
                bannerMessage = nil
            }
        } else if let uid = settings.outputDeviceUid,
                  let row = list.first(where: { $0.uid == uid }) {
            lastKnownDeviceName = row.name
            lastKnownDeviceUid = uid
            settings.outputDeviceName = row.name
            if bannerMessage != AppStrings.waitingForOutput(row.name) {
                bannerMessage = nil
            }
        }
    }

    /// Keeps the remembered (and persisted) output-device name in lockstep
    /// with uid changes. A uid that resolves in the current list refreshes
    /// the name; a uid that changes to a device not in the list drops it so
    /// deviceDisplayName falls back to AppStrings.selectedOutput. A
    /// re-announced identical uid while absent keeps the memory.
    private func handleOutputDeviceChange(uid: String?) {
        guard let uid, !uid.isEmpty else {
            lastKnownDeviceName = nil
            lastKnownDeviceUid = nil
            settings.outputDeviceName = nil
            return
        }
        if let row = devices.first(where: { $0.uid == uid }) {
            lastKnownDeviceName = row.name
            lastKnownDeviceUid = uid
            settings.outputDeviceName = row.name
        } else if uid != lastKnownDeviceUid {
            lastKnownDeviceName = nil
            lastKnownDeviceUid = nil
            settings.outputDeviceName = nil
        }
    }

    private func handleWillInstallUpdate() {
        if isRunning {
            settings.resumeAfterUpdateRequestedAt = Date()
        }
    }

    /// Relaunches the bridge after an in-app update when the pre-install
    /// observer recorded a fresh request. The flag is kept while the only
    /// blocker is a selected output that Core Audio has not enumerated yet
    /// (postinstall kickstarts coreaudiod, so the first refresh may miss it
    /// or return false); it is cleared for stale requests, running/
    /// transitioning states, and any other launch blocker.
    func resumeAfterUpdateIfRequested(now: Date = Date()) {
        guard let requestedAt = settings.resumeAfterUpdateRequestedAt else { return }
        let age = now.timeIntervalSince(requestedAt)
        guard age >= 0, age < 10 * 60 else {
            settings.resumeAfterUpdateRequestedAt = nil
            return
        }
        switch state {
        case .idle, .error, .reconnecting: break
        default:
            settings.resumeAfterUpdateRequestedAt = nil
            return
        }
        if let uid = settings.outputDeviceUid,
           !devices.contains(where: { $0.uid == uid }) {
            return
        }
        guard startBlockedReason == nil else {
            settings.resumeAfterUpdateRequestedAt = nil
            return
        }
        settings.resumeAfterUpdateRequestedAt = nil
        logger.info("Bridge resuming after update")
        start()
    }

    func refreshRoutingMode() {
        if let override = halBuildCheckOverride {
            updateReadinessCaches(
                halPresent: override.halPresent,
                appID: override.appID,
                driverID: override.driverID
            )
        } else {
            let halPresent = HalDriverDetector.isHalInstalled()
            updateReadinessCaches(
                halPresent: halPresent,
                appID: HalDriverDetector.appBuildID(),
                driverID: HalDriverDetector.driverBuildID()
            )
        }
        updateConnectionPhase()
    }

    func start(resetRetryAttempt: Bool = true) {
        switch state {
        case .idle, .error, .reconnecting: break
        default: return
        }
        if resetRetryAttempt {
            cancelRetryTask()
            cancelStabilityTask()
            retryAttempt = 0
            lastUnexpectedExitStatus = nil
            lastUnexpectedStderr = nil
        }
        resolveCachedBinaryURL()
        guard let url = binaryURL else {
            logger.error("Bridge start blocked: missing binary")
            state = .error(AppStrings.bridgeNotFound)
            return
        }
        guard let uid = settings.outputDeviceUid, !uid.isEmpty else {
            logger.error("Bridge start blocked: no output selected")
            state = .error(AppStrings.selectOutputDevice)
            return
        }
        // APM44 build-mismatch gate: in HAL mode the installed driver build
        // ID must equal the app's full build ID. Fail closed on
        // missing/malformed IDs. Never silently fall back to BlackHole here;
        // when the HAL device is absent this gate does not block.
        let halPresent: Bool
        let appID: String?
        let driverID: String?
        if let override = halBuildCheckOverride {
            halPresent = override.halPresent
            appID = override.appID
            driverID = override.driverID
        } else {
            halPresent = HalDriverDetector.isHalInstalled()
            appID = HalDriverDetector.appBuildID()
            driverID = HalDriverDetector.driverBuildID()
        }
        // Keep the launch route in lockstep with the live build-gate
        // decision: `routingMode` may be stale (last hotplug refresh), so
        // derive it from the same `halPresent` used for gating. This keeps
        // `connectionPhase`, `buildArguments`, and target fill consistent.
        // No silent fallback: HAL present + ID mismatch still errors below.
        // Store the gate inputs in the readiness caches for SwiftUI.
        updateReadinessCaches(halPresent: halPresent, appID: appID, driverID: driverID)
        if halPresent,
           !HalDriverDetector.buildIDsMatch(appBuildID: appID, driverBuildID: driverID) {
            let displayApp = HalDriverDetector.normalizedBuildID(appID)
                ?? AppStrings.buildIDMissingPlaceholder
            let displayDriver = HalDriverDetector.normalizedBuildID(driverID)
                ?? AppStrings.buildIDMissingPlaceholder
            state = .error(AppStrings.driverBuildMismatchDetail(app: displayApp, driver: displayDriver))
            return
        }
        guard let selectedOutput = devices.first(where: { $0.uid == uid }) else {
            logger.error("Bridge start blocked: selected output gone")
            state = .error(AppStrings.selectedOutputGone)
            return
        }
        guard selectedOutput.isMonitoringCompatible else {
            logger.error("Bridge start blocked: incompatible output")
            let issue = selectedOutput.compatibilityIssue ?? AppStrings.unsupportedPrefix
            state = .error(AppStrings.selectedOutputIncompatible(issue: AppStrings.compatibility(issue)))
            bannerMessage = AppStrings.namedIssue(selectedOutput.name, issue: AppStrings.compatibility(issue))
            return
        }

        if resetRetryAttempt {
            logger.info("Bridge starting")
        } else {
            logger.info("Bridge starting retry=\(self.retryAttempt)")
        }
        state = .starting
        processHealth = .spawning
        connectionPhase = routingMode == .halVirtualDevice ? .waitingForDAW : .connected
        stderrLines.removeAll()
        stdoutBuffer.removeAll(keepingCapacity: true)
        resetMetricsState()
        lastKnownFrameLoss = 0

        let proc = processLauncher.makeProcess()
        proc.executableURL = url
        proc.arguments = buildArguments(outputUid: uid)

        let parentPipe = Pipe()
        parentWatchPipe = parentPipe
        proc.standardInput = parentPipe

        let outPipe = Pipe()
        stdoutPipe = outPipe
        proc.standardOutput = outPipe
        let errPipe = Pipe()
        stderrPipe = errPipe
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

        // Install identity before launch so an immediately exiting child cannot
        // race its termination callback against assignment of the live process.
        process = proc
        do {
            try processLauncher.launch(proc)
            // The child owns its inherited read descriptor. Keeping a duplicate
            // read end in the app is unnecessary; the write end is the liveness
            // token and closes automatically if the app crashes.
            parentPipe.fileHandleForReading.closeFile()
            runningOutputFingerprint = selectedOutput
            state = .running
            logger.info("Bridge running")
            wasRunningBeforeDisconnect = false
            updateConnectionPhase()
            scheduleStaleWatch()
            drainPendingRestart()
        } catch {
            proc.terminationHandler = nil
            if process === proc {
                process = nil
            }
            processHealth = .stopped
            clearPipeHandlers()
            let nsError = error as NSError
            logger.error("Bridge launch failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code)")
            let detail = sanitizedDiagnostic(error.localizedDescription)
            if !resetRetryAttempt {
                lastUnexpectedStderr = detail
                scheduleAutoRetry()
            } else {
                state = .error(AppStrings.bridgeCouldNotStart(detail: detail))
            }
        }
    }

    func stop() {
        if initiateUserStop() {
            Task { await finishStopWithEscalation() }
        }
    }

    func stopAsync() async {
        if initiateUserStop() {
            await finishStopWithEscalation()
        }
    }

    private func initiateUserStop() -> Bool {
        wasRunningBeforeDisconnect = false
        cancelRetryTask()
        cancelStabilityTask()
        retryAttempt = 0
        if process != nil {
            initiateStop(reason: .user)
            return true
        } else if case .reconnecting = state {
            logger.info("Bridge stopping reason=\(self.stopReasonLabel(.user), privacy: .public)")
            state = .idle
            bannerMessage = nil
            lastStopReason = nil
            clearPipeHandlers()
        }
        settleApplyingSettings()
        return false
    }

    func quitApplication() async {
        await stopAsync()
        applicationTerminator()
    }

    private func initiateStop(reason: StopReason) {
        lastStopReason = reason
        logger.info("Bridge stopping reason=\(self.stopReasonLabel(reason), privacy: .public)")
        guard let proc = process else {
            transitionToIdle()
            return
        }
        state = .stopping
        if processLauncher.isProcessRunning(proc) {
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
            settleApplyingSettings()
            return
        }

        switch state {
        case .starting, .stopping:
            pendingRestartReason = reason
            settleApplyingSettings()
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
        settleApplyingSettings()
    }

    func restartForSettingsChange() async {
        switch state {
        case .running, .reconnecting, .error:
            if !isApplyingSettings { isApplyingSettings = true }
        default:
            break
        }
        await restart(reason: .settingsChange)
        settleApplyingSettings()
    }

    private func performRestart(reason: StopReason) async {
        switch state {
        case .idle:
            return
        case .error:
            start()
            return
        case .running, .reconnecting:
            break
        default:
            return
        }

        lastStopReason = reason
        if process != nil {
            let stopped = await terminateProcessWithEscalation(reason: reason)
            if !stopped {
                state = .error(AppStrings.bridgeDidNotStop)
                return
            }
        }

        start()
    }

    func handleSystemWillSleep() async {
        let shouldResume: Bool
        switch state {
        case .running, .starting, .reconnecting:
            shouldResume = true
        default:
            shouldResume = false
        }
        resumeAfterSystemWake = shouldResume
        guard shouldResume else { return }

        logger.info("Bridge pausing for sleep")
        wasRunningBeforeDisconnect = false
        cancelRetryTask()
        cancelStabilityTask()
        if process != nil {
            _ = await terminateProcessWithEscalation(reason: .internal)
        } else {
            transitionToIdle()
        }
    }

    func handleSystemDidWake() async {
        let shouldResume = resumeAfterSystemWake
        resumeAfterSystemWake = false
        guard await refreshDevices() else {
            if shouldResume {
                logger.info("Bridge waiting for devices after wake")
                state = .reconnecting
                bannerMessage = AppStrings.waitingForDevicesAfterWake
            }
            return
        }
        guard shouldResume else { return }
        guard let uid = settings.outputDeviceUid,
              let selected = devices.first(where: { $0.uid == uid }),
              selected.isAlive,
              selected.isMonitoringCompatible else {
            logger.info("Bridge output unavailable after wake")
            wasRunningBeforeDisconnect = true
            state = .reconnecting
            connectionPhase = .stopped
            bannerMessage = AppStrings.outputUnavailableAfterWake(deviceDisplayName)
            return
        }
        logger.info("Bridge resuming after wake")
        start()
    }

    func handleHotplug() async {
        refreshRoutingMode()
        guard await refreshDevices() else { return }

        guard let uid = settings.outputDeviceUid else {
            if isRunning {
                logger.info("Bridge output disconnected")
                wasRunningBeforeDisconnect = false
                bannerMessage = AppStrings.outputDisconnectedSelect
                _ = await terminateProcessWithEscalation(reason: .hotplug)
                state = .error(AppStrings.outputDeviceDisconnected)
            }
            return
        }

        let selectedOutput = devices.first(where: { $0.uid == uid && $0.isAlive })
        let devicePresent = selectedOutput != nil

        if isRunning {
            if let selectedOutput {
                guard runningOutputFingerprint != selectedOutput else {
                    // The global device-list notification concerned another
                    // endpoint; the selected output is unchanged.
                    return
                }
                bannerMessage = AppStrings.reconnectingTo(deviceDisplayName)
                await restart(reason: .hotplug)
            } else {
                logger.info("Bridge waiting for output after hotplug")
                wasRunningBeforeDisconnect = true
                _ = await terminateProcessWithEscalation(reason: .hotplug)
                state = .reconnecting
                bannerMessage = AppStrings.waitingForOutput(deviceDisplayName)
            }
            return
        }

        if case .reconnecting = state {
            if devicePresent, wasRunningBeforeDisconnect {
                bannerMessage = AppStrings.reconnectingTo(deviceDisplayName)
                await restart(reason: .hotplug)
                if isRunning {
                    wasRunningBeforeDisconnect = false
                }
            }
            return
        }

        // Idle: refresh only; the only auto-start is a pending post-update
        // resume once its selected output is enumerated.
        if case .idle = state {
            resumeAfterUpdateIfRequested(now: Date())
        }
    }

    private func waitForTermination(timeout: Duration = .seconds(5)) async throws {
        if state == .idle, process == nil { return }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    if self.state == .idle, self.process == nil {
                        continuation.resume()
                        return
                    }
                    // PROC-03: support concurrent termination waiters. Each
                    // caller appends its own continuation; the termination
                    // handler drains the full list. A single optional slot
                    // would let the second caller overwrite the first.
                    self.terminationContinuations.append(continuation)
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw TerminationWaitError.timedOut
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    private enum TerminationWaitError: Error {
        case timedOut
    }

    private func buildArguments(outputUid: String) -> [String] {
        let ms = settings.effectiveTargetFillMs(halMode: routingMode == .halVirtualDevice)
        let quality = settings.effectiveSrcQuality.cliArgument
        var args: [String] = [
            "--output-device", outputUid,
            "--target-fill-ms", String(format: "%.0f", ms),
            "--src-quality", quality,
            "--metrics-json",
            "--parent-watch-stdin",
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
        if snapshot.knownFrameLoss > lastKnownFrameLoss {
            triggerGlitchFlash()
        }
        lastKnownFrameLoss = snapshot.knownFrameLoss
        latestMetrics = snapshot
        lastMetricsAt = Date()
        metricsStale = false
        if processHealth == .spawning {
            processHealth = .handshaking
            scheduleStabilityReset()
        }
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
        if stderr.localizedCaseInsensitiveContains("shm") {
            return AppStrings.ipcFailed()
        }
        if let last = stderrLines.last, !last.isEmpty {
            return last
        }
        return defaultMessage
    }

    private func clearPipeHandlers() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
        parentWatchPipe?.fileHandleForWriting.closeFile()
        parentWatchPipe?.fileHandleForReading.closeFile()
        parentWatchPipe = nil
    }

    private func sanitizedDiagnostic(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let printableScalars = normalized.unicodeScalars.filter {
            $0.value >= 0x20 && $0.value != 0x7f
        }
        let singleLine = String(String.UnicodeScalarView(printableScalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if singleLine.isEmpty { return AppStrings.noDiagnostic }
        return String(singleLine.prefix(240))
    }

    private func resetMetricsState() {
        latestMetrics = nil
        lastMetricsAt = nil
        metricsStale = false
    }

    @discardableResult
    private func finishStopWithEscalation() async -> Bool {
        guard process != nil else {
            clearPipeHandlers()
            return true
        }
        do {
            try await waitForTermination(timeout: .seconds(5))
            return true
        } catch {
            if let proc = process, processLauncher.isProcessRunning(proc), proc.isRunning {
                logger.error("Bridge stop timed out; sending SIGKILL")
                kill(proc.processIdentifier, SIGKILL)
            }
            do {
                try await waitForTermination(timeout: .seconds(5))
                return true
            } catch {
                // PROC-01: ensure any in-flight termination waiter
                // unblocks with a final result instead of hanging. Clear
                // pipe handlers and resume every queued continuation so
                // the caller gets a deterministic `false`.
                logger.error("Bridge stop failed after SIGKILL")
                clearPipeHandlers()
                resumeTerminationWaiters()
                return false
            }
        }
    }

    @discardableResult
    private func terminateProcessWithEscalation(reason: StopReason) async -> Bool {
        initiateStop(reason: reason)
        return await finishStopWithEscalation()
    }

    private func transitionToIdle() {
        cancelStabilityTask()
        processHealth = .stopped
        runningOutputFingerprint = nil
        clearPipeHandlers()
        resetMetricsState()
        state = .idle
        connectionPhase = .stopped
        lastStopReason = nil
        resumeTerminationWaiters()
        drainPendingRestart()
        settleApplyingSettings()
    }

    private func drainPendingRestart() {
        guard let pending = pendingRestartReason else { return }
        // Coalescing: when a restart is already in flight its wrapper loop
        // drains the pending reason. Spawning a second task here would
        // launch an extra daemon. Only spawn when no restart is running.
        guard restartTask == nil else { return }
        pendingRestartReason = nil
        Task { @MainActor in await restart(reason: pending) }
    }

    private func resumeTerminationWaiters() {
        // PROC-03: resume all queued termination continuations, not just
        // one. Drain the list, then clear it so a new waiter that arrives
        // after this point is not immediately resumed.
        let pending = terminationContinuations
        terminationContinuations = []
        for continuation in pending {
            continuation.resume()
        }
    }

    private func cancelRetryTask() {
        retryTask?.cancel()
        retryTask = nil
    }

    private func cancelStabilityTask() {
        stabilityTask?.cancel()
        stabilityTask = nil
    }

    private func scheduleStabilityReset() {
        cancelStabilityTask()
        guard let launchedProcess = process else { return }
        stabilityTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(self.stabilityWindow))
            guard !Task.isCancelled,
                  self.process === launchedProcess,
                  self.processHealth == .handshaking,
                  self.isRunning else { return }
            self.processHealth = .stable
            self.retryAttempt = 0
            self.lastUnexpectedExitStatus = nil
            self.lastUnexpectedStderr = nil
        }
    }

    private func exhaustedRetryMessage() -> String {
        var detail = ""
        if let status = lastUnexpectedExitStatus {
            detail = AppStrings.lastExit(Int(status))
        }
        if let stderr = lastUnexpectedStderr, !stderr.isEmpty {
            detail += ": \(stderr)"
        }
        return AppStrings.stoppedAfterUnstableLaunches(maxUnhealthyLaunches, detail: detail)
    }

    private func scheduleAutoRetry() {
        cancelRetryTask()
        cancelStabilityTask()
        retryGeneration += 1
        retryAttempt += 1
        if retryAttempt >= maxUnhealthyLaunches {
            logger.error("Bridge retries exhausted")
            let message = exhaustedRetryMessage()
            state = .error(message)
            return
        }

        state = .reconnecting

        // Capture the attempt before creating the task. Stop/reset can set the
        // live counter back to zero before a cancelled task begins executing.
        let scheduledAttempt = retryAttempt
        let delayIndex = min(scheduledAttempt - 1, retryDelays.count - 1)
        let delay = retryDelays[delayIndex]

        retryTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            guard case .reconnecting = self.state else { return }
            self.retryTask = nil
            self.start(resetRetryAttempt: false)
        }
    }

    private func stopReasonLabel(_ reason: StopReason) -> String {
        switch reason {
        case .user:
            return "user"
        case .settingsChange:
            return "settingsChange"
        case .hotplug:
            return "hotplug"
        case .internal:
            return "internal"
        }
    }

    private func handleTermination(_ proc: Process) {
        defer { settleApplyingSettings() }
        // A late callback from an old child must never clear state belonging
        // to a replacement process.
        guard process === proc else { return }
        cancelStabilityTask()
        processHealth = .stopped
        clearPipeHandlers()
        process = nil
        staleTask?.cancel()
        if case .stopping = state {
            transitionToIdle()
            return
        }
        let exitStatus = testTerminationStatus ?? proc.terminationStatus
        testTerminationStatus = nil
        let stderr = stderrLines.joined(separator: "\n")
        let recoverableStale = isRecoverableStaleRingExit(status: exitStatus, stderr: stderr)

        if exitStatus != 0 {
            lastUnexpectedExitStatus = exitStatus
            lastUnexpectedStderr = sanitizedDiagnostic(stderr)
            logger.error("Bridge unexpected exit status=\(exitStatus)")
        }

        if exitStatus == Self.loadedDriverBuildMismatchExitStatus,
           state == .running || state == .starting {
            cancelRetryTask()
            retryAttempt = 0
            lastStopReason = nil
            let message = AppStrings.loadedDriverBuildMismatch
            state = .error(message)
            bannerMessage = message
            connectionPhase = .stopped
            resumeTerminationWaiters()
            return
        }

        if exitStatus != 0, case .running = state {
            if lastStopReason != .user {
                scheduleAutoRetry()
            } else {
                lastStopReason = nil
                let message = bridgeFailureMessage(defaultMessage: AppStrings.couldNotStart)
                state = .error(message)
                bannerMessage = message
            }
            connectionPhase = .stopped
            resumeTerminationWaiters()
            return
        } else if case .running = state {
            transitionToIdle()
            return
        } else if case .starting = state {
            if recoverableStale, lastStopReason != .user {
                scheduleAutoRetry()
            } else {
                lastStopReason = nil
                state = .error(bridgeFailureMessage(defaultMessage: AppStrings.couldNotStart))
            }
        }
        connectionPhase = .stopped
        resumeTerminationWaiters()
    }

}
