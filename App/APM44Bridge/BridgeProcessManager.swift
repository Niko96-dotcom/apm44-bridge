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

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var isTransitioning: Bool {
        switch self {
        case .starting, .stopping: return true
        default: return false
        }
    }
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
            return retryBudget.bannerMessage(for: state)
        }
        set { noticeMessage = newValue }
    }

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var parentWatchPipe: Pipe?
    private var stdoutBuffer = DaemonStdoutLineBuffer()
    private var lastKnownFrameLoss: UInt64 = 0
    private var glitchTask: Task<Void, Never>?
    private var staleTask: Task<Void, Never>?
    private var lastMetricsAt: Date?
    private var stderrTail = DaemonStderrTail()
    private var terminationWaiters: [UInt64: CheckedContinuation<Bool, Never>] = [:]
    private var terminationWaiterTimers: [UInt64: Task<Void, Never>] = [:]
    private var nextTerminationWaiterID: UInt64 = 0
    private var restartTask: Task<Void, Never>?
    private var pendingRestartReason: StopReason?
    private var wasRunningBeforeDisconnect = false
    private var lastKnownDeviceName: String?
    private var lastKnownDeviceUid: String?
    private var runningOutputFingerprint: AudioDeviceRow?
    @Published private var retryBudget = BridgeRetryBudget()
    private var retryTask: Task<Void, Never>?
    private var stabilityTask: Task<Void, Never>?
    private var processHealth: BridgeProcessHealth = .stopped
    private var resumeAfterSystemWake = false
    /// Tracks a stuck-helper .error without comparing localized strings in
    /// handleTermination. Set only via markStuckHelper(), cleared in
    /// transitionToIdle() and when start() launches.
    private var awaitingStuckHelperExit = false
    // Every sleep bumps this so a wake can tell a newer sleep superseded it.
    private var systemSleepGeneration = 0
    // Every user stop bumps this so a restart awaiting its old helper can tell
    // the user stopped the bridge meanwhile.
    private var userStopGeneration = 0
    /// The newest device-list refresh; superseded refreshes await it.
    private var newestDeviceRefresh: (generation: Int, task: Task<Bool?, Never>)?
    private var hotplugEventGeneration = 0
    /// Lifetime observers; the manager outlives the app, so the tokens are
    /// retained without explicit removal.
    private var outputDeviceObserver: NSObjectProtocol?
    private var willInstallUpdateObserver: NSObjectProtocol?
    private var updateInstallAbandonedObserver: NSObjectProtocol?

    private let processLauncher: ProcessLaunching
    private let binaryURLOverride: URL?
    private let timing: BridgeTiming
    private let bridgeClock: any BridgeClock
    private let deviceSource: any BridgeDeviceSource
    private let applicationTerminator: @MainActor () -> Void

    let settings: BridgeSettings

    internal private(set) var hotplugRefreshGeneration = 0
    internal private(set) var retryGeneration = 0

    private var stabilityWindow: TimeInterval {
        timing.stabilityWindow
    }

    init(
        settings: BridgeSettings,
        processLauncher: ProcessLaunching? = nil,
        binaryURLOverride: URL? = nil,
        timing: BridgeTiming = .live,
        clock: any BridgeClock = LiveBridgeClock(),
        deviceSource: any BridgeDeviceSource = LiveBridgeDeviceSource(),
        applicationTerminator: @escaping @MainActor () -> Void = { NSApplication.shared.terminate(nil) }
    ) {
        self.settings = settings
        self.processLauncher = processLauncher ?? LiveProcessLauncher()
        self.binaryURLOverride = binaryURLOverride
        self.timing = timing
        self.bridgeClock = clock
        self.deviceSource = deviceSource
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
        // Posted when an install that already announced itself fails or is
        // cancelled: this app keeps running, so there is no relaunch to resume.
        updateInstallAbandonedObserver = NotificationCenter.default.addObserver(
            forName: .apm44UpdateInstallAbandoned,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.settings.resumeAfterUpdateRequestedAt = nil
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

    var isTransitioning: Bool { state.isTransitioning }

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

    var isRunning: Bool { state.isRunning }

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

    // `.starting` is synchronously transient under injected launchers, so termination-from-starting is otherwise unreachable.
    internal func setStateForTesting(_ newState: BridgeRunState) {
        state = newState
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

    /// A refresh that a newer one supersedes joins the newest refresh and
    /// returns its result, so a superseded caller (wake, hotplug, the menu)
    /// never reads "superseded" as a failed listing.
    @discardableResult
    func refreshDevices() async -> Bool {
        hotplugRefreshGeneration += 1
        let refreshGeneration = hotplugRefreshGeneration
        refreshRoutingMode()
        resolveCachedBinaryURL()
        guard let url = binaryURL else {
            newestDeviceRefresh = nil
            logger.error("Device list refresh blocked: missing binary")
            bannerMessage = AppStrings.bridgeNotFound
            return false
        }
        let source = deviceSource
        let refresh = Task { @MainActor () -> Bool? in
            do {
                let list = try await Task.detached {
                    try source.listDevices(binaryURL: url)
                }.value
                guard refreshGeneration == self.hotplugRefreshGeneration else { return nil }
                self.applyRefreshedDeviceList(list)
                return true
            } catch {
                guard refreshGeneration == self.hotplugRefreshGeneration else { return nil }
                logger.error("Device list refresh failed")
                self.bannerMessage = AppStrings.couldNotListDevices
                return false
            }
        }
        newestDeviceRefresh = (refreshGeneration, refresh)
        var joinedGeneration = refreshGeneration
        var result = await refresh.value
        // nil means superseded: every newer refresh is recorded before its
        // listing starts, so this loop only ever steps forward.
        while result == nil {
            guard let newest = newestDeviceRefresh, newest.generation > joinedGeneration else {
                return false
            }
            joinedGeneration = newest.generation
            result = await newest.task.value
        }
        return result ?? false
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
        let check = deviceSource.halBuildCheck()
        updateReadinessCaches(
            halPresent: check.halPresent,
            appID: check.appBuildID,
            driverID: check.driverBuildID
        )
        updateConnectionPhase()
    }

    func start(resetRetryAttempt: Bool = true) {
        switch state {
        case .idle, .error, .reconnecting: break
        default: return
        }
        // Refuse to launch over a stuck helper that survived escalation.
        guard process == nil else {
            logger.error("Bridge start refused: previous helper still running")
            return
        }
        if resetRetryAttempt {
            cancelRetryTask()
            cancelStabilityTask()
            retryBudget.reset()
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
        let check = deviceSource.halBuildCheck()
        let halPresent = check.halPresent
        let appID = check.appBuildID
        let driverID = check.driverBuildID
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
            logger.info("Bridge starting retry=\(self.retryBudget.attempt)")
        }
        state = .starting
        processHealth = .spawning
        connectionPhase = routingMode == .halVirtualDevice ? .waitingForDAW : .connected
        stderrTail.removeAll()
        stdoutBuffer.reset()
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
        // Output already queued when this child is replaced must not reach
        // the replacement's metrics, phase, glitch flash or stderr tail, so
        // each Task checks that its child is still the live one.
        errPipe.fileHandleForReading.readabilityHandler = { [weak self, weak proc] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                guard let self, let proc, self.process === proc else { return }
                self.appendStderr(text)
            }
        }

        outPipe.fileHandleForReading.readabilityHandler = { [weak self, weak proc] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                guard let self, let proc, self.process === proc else { return }
                self.consumeStdout(data)
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
            awaitingStuckHelperExit = false
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
            let detail = BridgeDiagnostics.sanitized(error.localizedDescription)
            if !resetRetryAttempt {
                retryBudget.recordRetryLaunchFailure(detail: detail)
                scheduleAutoRetry()
            } else {
                state = .error(AppStrings.bridgeCouldNotStart(detail: detail))
            }
        }
    }

    func stop() {
        if initiateUserStop() {
            Task { await finishUserStop() }
        }
    }

    func stopAsync() async {
        if initiateUserStop() {
            await finishUserStop()
        }
    }

    /// Shared user-stop completion for stop() and stopAsync(): awaits the
    /// escalation and surfaces a stuck helper as .error. Guarded so a late
    /// exit that already idled is not overwritten with a false error.
    private func finishUserStop() async {
        let stopped = await finishStopWithEscalation()
        if !stopped && process != nil {
            markStuckHelper()
        }
    }

    /// Records a helper that survived SIGKILL; its late exit frees the slot.
    private func markStuckHelper() {
        state = .error(AppStrings.bridgeDidNotStop)
        connectionPhase = .stopped
        awaitingStuckHelperExit = true
    }

    private func initiateUserStop() -> Bool {
        userStopGeneration += 1
        wasRunningBeforeDisconnect = false
        resumeAfterSystemWake = false
        // A stop outranks a pending post-update resume, or a later hotplug or
        // relaunch within its window would start the bridge again.
        settings.resumeAfterUpdateRequestedAt = nil
        cancelRetryTask()
        cancelStabilityTask()
        retryBudget.clearAttemptKeepingDiagnostics()
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
        let sleepGeneration = systemSleepGeneration
        let stopGeneration = userStopGeneration
        if process != nil {
            let stopped = await terminateProcessWithEscalation(reason: reason)
            if !stopped && process != nil {
                markStuckHelper()
                return
            }
        }
        // A user stop while the old helper exited cancels the relaunch.
        guard stopGeneration == userStopGeneration else { return }
        // So does a sleep: handleSystemWillSleep kept the intent for the wake,
        // which relaunches with the newest settings once devices are back.
        guard sleepGeneration == systemSleepGeneration else {
            logger.info("Bridge restart deferred to wake")
            return
        }

        start()
    }

    func handleSystemWillSleep() async {
        // Count every sleep first so a wake in flight sees it was superseded.
        systemSleepGeneration += 1
        let shouldResume: Bool
        switch state {
        case .running, .starting, .reconnecting:
            shouldResume = true
        case .stopping where restartTask != nil:
            // A restart is replacing the helper, so the bridge is logically
            // running. Its old helper is already stopping, and performRestart
            // sees this sleep and leaves the relaunch to the wake.
            resumeAfterSystemWake = true
            logger.info("Bridge pausing for sleep during restart")
            return
        default:
            shouldResume = false
        }
        // Keep an intent that a wake has not consumed yet: a sleep that
        // lands during that wake finds the bridge already stopped.
        resumeAfterSystemWake = resumeAfterSystemWake || shouldResume
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
        // The intent stays in resumeAfterSystemWake across every await below,
        // so a user stop meanwhile cancels it; it is consumed only at the end.
        let wakeGeneration = systemSleepGeneration
        var sleepStopUnfinished = false
        if resumeAfterSystemWake, case .stopping = state {
            // The sleep stop is still in flight and start() would ignore
            // .stopping, so wait for the termination first.
            // Outlast one full escalation (SIGTERM wait + SIGKILL wait).
            try? await waitForTermination(timeout: .seconds(timing.stopTimeout * 2 + 1))
            if case .stopping = state { sleepStopUnfinished = true }
        }
        let refreshed = await refreshDevices()
        // A sleep that landed during the refresh owns the intent now; the
        // next wake handles it, so keep the flag without starting or parking.
        if wakeGeneration != systemSleepGeneration {
            logger.info("Bridge slept again during wake")
            return
        }
        let shouldResume = resumeAfterSystemWake
        resumeAfterSystemWake = false
        guard shouldResume else { return }
        if sleepStopUnfinished {
            logger.info("Bridge stop unfinished after wake")
            parkAfterWake(banner: AppStrings.waitingForDevicesAfterWake)
            return
        }
        if case .stopping = state {
            // A hotplug or settings restart began during the refresh and
            // relaunches by itself; parking would overwrite its .stopping.
            logger.info("Bridge restart in flight after wake")
            return
        }
        guard refreshed else {
            logger.info("Bridge waiting for devices after wake")
            parkAfterWake(banner: AppStrings.waitingForDevicesAfterWake)
            return
        }
        guard let uid = settings.outputDeviceUid,
              let selected = devices.first(where: { $0.uid == uid }),
              selected.isAlive,
              selected.isMonitoringCompatible else {
            logger.info("Bridge output unavailable after wake")
            parkAfterWake(banner: AppStrings.outputUnavailableAfterWake(deviceDisplayName))
            return
        }
        logger.info("Bridge resuming after wake")
        start()
    }

    /// Parks a bridge that should resume after wake so the next hotplug with
    /// the output present finishes the resume.
    private func parkAfterWake(banner: String) {
        wasRunningBeforeDisconnect = true
        state = .reconnecting
        connectionPhase = .stopped
        bannerMessage = banner
    }

    func handleHotplug() async {
        hotplugEventGeneration += 1
        let event = hotplugEventGeneration
        refreshRoutingMode()
        guard await refreshDevices() else { return }
        // A newer hotplug joined the same refresh and handles this list;
        // handling it twice would restart the bridge twice.
        guard event == hotplugEventGeneration else { return }

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

        // Each waiter gets its own id so the timeout timer removes only
        // itself; a plain array would need index juggling on removal.
        let terminated: Bool = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            if self.state == .idle, self.process == nil {
                continuation.resume(returning: true)
                return
            }
            // PROC-03: support concurrent termination waiters. Each caller
            // registers under its own id; the termination handler drains
            // the full map. A single optional slot would let the second
            // caller overwrite the first.
            let id = self.nextTerminationWaiterID
            self.nextTerminationWaiterID += 1
            self.terminationWaiters[id] = continuation
            // The timer owns only this id: on fire it removes that waiter
            // (if still present) and resumes it with false, so the wait
            // times out even when the process never exits.
            self.terminationWaiterTimers[id] = Task { @MainActor in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                guard let waiter = self.terminationWaiters.removeValue(forKey: id) else { return }
                self.terminationWaiterTimers.removeValue(forKey: id)
                waiter.resume(returning: false)
            }
        }
        if !terminated {
            throw TerminationWaitError.timedOut
        }
    }

    private enum TerminationWaitError: Error {
        case timedOut
    }

    private func buildArguments(outputUid: String) -> [String] {
        let ms = settings.effectiveTargetFillMs(halMode: routingMode == .halVirtualDevice)
        let quality = settings.effectiveSrcQuality.cliArgument
        return BridgeLaunchArguments.make(
            outputUid: outputUid,
            targetFillMs: ms,
            srcQuality: quality,
            halMode: routingMode == .halVirtualDevice
        )
    }

    private func consumeStdout(_ chunk: Data) {
        for line in stdoutBuffer.append(chunk) {
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
        lastMetricsAt = bridgeClock.now()
        metricsStale = false
        if processHealth == .spawning {
            processHealth = .handshaking
            scheduleStabilityReset()
        }
        updateConnectionPhase()
    }

    private func updateConnectionPhase() {
        connectionPhase = BridgeConnectionPhase.derive(
            state: state,
            halMode: routingMode == .halVirtualDevice,
            metrics: latestMetrics
        )
    }

    private func triggerGlitchFlash() {
        glitchFlash = true
        glitchTask?.cancel()
        let flashDuration = timing.glitchFlashDuration
        glitchTask = Task {
            try? await Task.sleep(for: .seconds(flashDuration))
            // A newer glitch cancels this task and owns the flash; clearing
            // it here would cut the newer flash short.
            guard !Task.isCancelled else { return }
            glitchFlash = false
        }
    }

    private func scheduleStaleWatch() {
        staleTask?.cancel()
        let checkInterval = timing.staleCheckInterval
        let staleAfter = timing.staleAfter
        staleTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(checkInterval))
                guard isRunning else { continue }
                if let last = lastMetricsAt, bridgeClock.now().timeIntervalSince(last) > staleAfter {
                    metricsStale = true
                }
            }
        }
    }

    private func appendStderr(_ text: String) {
        stderrTail.append(text)
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
            try await waitForTermination(timeout: .seconds(timing.stopTimeout))
            return true
        } catch {
            if let proc = process, processLauncher.isProcessRunning(proc) {
                logger.error("Bridge stop timed out; sending SIGKILL")
                processLauncher.forceKill(proc)
            }
            do {
                try await waitForTermination(timeout: .seconds(timing.stopTimeout))
                return true
            } catch {
                // PROC-01: ensure any in-flight termination waiter
                // unblocks with failure instead of hanging. Clear
                // pipe handlers and resume every queued continuation with
                // false so siblings also observe the failure.
                logger.error("Bridge stop failed after SIGKILL")
                clearPipeHandlers()
                resumeTerminationWaiters(terminated: false)
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
        awaitingStuckHelperExit = false
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

    private func resumeTerminationWaiters(terminated: Bool = true) {
        // PROC-03: resume all queued termination waiters, not just one.
        // Drain the map, then clear it so a new waiter that arrives after
        // this point is not immediately resumed.
        let pending = terminationWaiters
        terminationWaiters = [:]
        // Cancel each timer so a drained waiter is never resumed twice
        // (once here with true, once later by its timeout with false).
        for (_, timer) in terminationWaiterTimers {
            timer.cancel()
        }
        terminationWaiterTimers = [:]
        for (_, continuation) in pending {
            continuation.resume(returning: terminated)
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
            self.retryBudget.reset()
        }
    }

    private func scheduleAutoRetry() {
        cancelRetryTask()
        cancelStabilityTask()
        retryGeneration += 1
        let decision = retryBudget.consumeAttempt(delays: timing.retryDelays)
        switch decision {
        case .exhausted(let message):
            logger.error("Bridge retries exhausted")
            state = .error(message)
            return
        case .retry(let delay):
            state = .reconnecting

            // The delay is computed from the attempt captured before the task
            // is created. Stop/reset can set the live counter back to zero
            // before a cancelled task begins executing.
            retryTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                guard case .reconnecting = self.state else { return }
                self.retryTask = nil
                self.start(resetRetryAttempt: false)
            }
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

    private func failWithoutRetry(_ message: String) {
        cancelRetryTask()
        retryBudget.clearAttemptKeepingDiagnostics()
        lastStopReason = nil
        state = .error(message)
        bannerMessage = message
        connectionPhase = .stopped
        resumeTerminationWaiters()
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
        if awaitingStuckHelperExit, case .error = state {
            // Stuck helper outlived SIGKILL; its late exit frees the slot.
            transitionToIdle()
            return
        }
        if case .reconnecting = state, wasRunningBeforeDisconnect, lastStopReason == .internal {
            // Wake parked over an unfinished sleep stop; the stuck helper
            // just exited, so finish the resume the park was waiting for.
            // A failed hotplug stop can also leave a tracked process in
            // .reconnecting, but its reason is .hotplug so it falls through
            // to classify below instead of resuming here.
            if let uid = settings.outputDeviceUid,
               let selected = devices.first(where: { $0.uid == uid }),
               selected.isAlive,
               selected.isMonitoringCompatible {
                bannerMessage = nil
                resumeTerminationWaiters()
                start()
            } else {
                // Output still missing; keep the park for the next hotplug.
                connectionPhase = .stopped
                resumeTerminationWaiters()
            }
            return
        }
        let exitStatus = processLauncher.terminationStatus(of: proc)
        let stderr = stderrTail.joined

        if exitStatus != 0 {
            retryBudget.recordUnexpectedExit(status: exitStatus, stderr: BridgeDiagnostics.sanitized(stderr))
            logger.error("Bridge unexpected exit status=\(exitStatus)")
        }

        switch BridgeTerminationPolicy.classify(
            state: state,
            exitStatus: exitStatus,
            lastStopReason: lastStopReason
        ) {
        case .loadedDriverMismatch:
            failWithoutRetry(AppStrings.loadedDriverBuildMismatch)
            return
        case .helperAlreadyRunning:
            failWithoutRetry(AppStrings.helperAlreadyRunning)
            return
        case .autoRetry:
            scheduleAutoRetry()
            connectionPhase = .stopped
            resumeTerminationWaiters()
            return
        case .failWhileRunning:
            lastStopReason = nil
            let message = stderrTail.failureMessage(default: AppStrings.couldNotStart)
            state = .error(message)
            bannerMessage = message
            connectionPhase = .stopped
            resumeTerminationWaiters()
            return
        case .cleanExitWhileRunning:
            transitionToIdle()
            return
        case .failWhileStarting:
            lastStopReason = nil
            state = .error(stderrTail.failureMessage(default: AppStrings.couldNotStart))
        case .ignore:
            break
        }
        connectionPhase = .stopped
        resumeTerminationWaiters()
    }

}
