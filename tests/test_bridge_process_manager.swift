import XCTest
@testable import APM44Bridge

final class MockProcessLauncher: ProcessLaunching {
    private(set) var makeCount = 0
    private(set) var lastProcess: Process?
    var terminationDelayNanoseconds: UInt64 = 0
    var shouldFailLaunch = false
    var failLaunchesAfterFirstSuccess = false
    /// One-shot stub for the exit status the manager observes on the next
    /// termination, mirroring the previous override-hook semantics.
    var nextTerminationStatus: Int32?
    private var successfulLaunches = 0
    private var running = Set<ObjectIdentifier>()
    private(set) var forceKilled: [Process] = []
    var terminateOnForceKill = false

    func makeProcess() -> Process {
        makeCount += 1
        let proc = Process()
        lastProcess = proc
        return proc
    }

    func launch(_ process: Process) throws {
        if shouldFailLaunch {
            throw NSError(domain: "MockProcessLauncher", code: 1)
        }
        if failLaunchesAfterFirstSuccess, successfulLaunches >= 1 {
            throw NSError(domain: "MockProcessLauncher", code: 1)
        }
        successfulLaunches += 1
        running.insert(ObjectIdentifier(process))
    }

    func isProcessRunning(_ process: Process) -> Bool {
        running.contains(ObjectIdentifier(process))
    }

    func terminationStatus(of process: Process) -> Int32 {
        if let stubbed = nextTerminationStatus {
            nextTerminationStatus = nil
            return stubbed
        }
        return process.terminationStatus
    }

    func forceKill(_ process: Process) {
        forceKilled.append(process)
        // Mock processes never really run, so mirror fireTermination
        // synchronously: drop the running token and invoke the handler.
        if terminateOnForceKill {
            running.remove(ObjectIdentifier(process))
            process.terminationHandler?(process)
        }
    }

    /// Marks a process as exited without delivering its termination
    /// callback, so the manager's next stop handles it synchronously.
    func markExited(_ proc: Process) {
        running.remove(ObjectIdentifier(proc))
    }

    func fireTermination(for proc: Process) async {
        if terminationDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: terminationDelayNanoseconds)
        }
        running.remove(ObjectIdentifier(proc))
        proc.terminationHandler?(proc)
    }
}

/// Fake BridgeDeviceSource with lock-protected mutable state: tests mutate
/// it from @MainActor while the manager reads it from `Task.detached`.
final class FakeBridgeDeviceSource: BridgeDeviceSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _halCheck: HalBuildCheck
    private var _devices: [AudioDeviceRow]
    private var pendingGates: [ListDevicesGate] = []

    init(halCheck: HalBuildCheck, devices: [AudioDeviceRow]) {
        self._halCheck = halCheck
        self._devices = devices
    }

    var halCheck: HalBuildCheck {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _halCheck
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _halCheck = newValue
        }
    }

    var devices: [AudioDeviceRow] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _devices
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _devices = newValue
        }
    }

    func halBuildCheck() -> HalBuildCheck {
        lock.lock()
        defer { lock.unlock() }
        return _halCheck
    }

    /// Holds the next unclaimed `listDevices` call inside the manager's
    /// `Task.detached` until the returned gate is released.
    func gateNextListing() -> ListDevicesGate {
        let gate = ListDevicesGate()
        lock.lock()
        pendingGates.append(gate)
        lock.unlock()
        return gate
    }

    func listDevices(binaryURL: URL) throws -> [AudioDeviceRow] {
        lock.lock()
        let gate = pendingGates.isEmpty ? nil : pendingGates.removeFirst()
        lock.unlock()
        gate?.hold()
        lock.lock()
        defer { lock.unlock() }
        return _devices
    }
}

/// One held `listDevices` call. It blocks a cooperative-pool thread, so a
/// test holds at most two at once and releases them in teardown.
final class ListDevicesGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var held = false
    private var released = false

    var isHolding: Bool {
        condition.lock()
        defer { condition.unlock() }
        return held && !released
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }

    fileprivate func hold() {
        condition.lock()
        held = true
        while !released { condition.wait() }
        condition.unlock()
    }
}

/// Controllable wall-clock for the stale-metrics watch: tests advance time
/// instead of waiting out the live staleness threshold.
final class FakeBridgeClock: BridgeClock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    /// Far from the real clock, so a watch that reads Date() instead of the
    /// injected clock never sees the metrics as stale.
    init(now: Date = Date(timeIntervalSinceReferenceDate: 4_000_000_000)) {
        _now = now
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        _now = _now.addingTimeInterval(interval)
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return _now
    }
}

@MainActor
final class BridgeProcessManagerTests: XCTestCase {
    private let fixtureBuildID = "0.12.7+test-fixture-match"
    private let testDevice = AudioDeviceRow(
        uid: "test-output-uid",
        name: "Test Output",
        nominalRate: 48_000,
        hasInput: false,
        hasOutput: true
    )

    private func awaitHotplugCompletingTermination(
        manager: BridgeProcessManager,
        launcher: MockProcessLauncher
    ) async {
        let task = Task { await manager.handleHotplug() }
        for _ in 0..<200 {
            if case .stopping = manager.state { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        await task.value
    }

    /// Yields the main actor until `condition` holds or about a second passes.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func sleepCompletingTermination(
        manager: BridgeProcessManager,
        launcher: MockProcessLauncher
    ) async {
        let sleep = Task { await manager.handleSystemWillSleep() }
        await waitUntil { manager.state == .stopping }
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        await sleep.value
    }

    private func makeSettings() -> BridgeSettings {
        let suite = "com.niko.apm44.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return BridgeSettings(defaults: defaults)
    }

    private func makeManager(
        launcher: MockProcessLauncher? = nil,
        timing: BridgeTiming = .live,
        clock: any BridgeClock = LiveBridgeClock(),
        halCheck: HalBuildCheck? = nil,
        devices: [AudioDeviceRow]? = nil,
        applicationTerminator: @escaping @MainActor () -> Void = {}
    ) async -> (BridgeProcessManager, BridgeSettings, MockProcessLauncher, FakeBridgeDeviceSource) {
        let mockLauncher = launcher ?? MockProcessLauncher()
        let settings = makeSettings()
        settings.outputDeviceUid = testDevice.uid
        let source = FakeBridgeDeviceSource(
            halCheck: halCheck ?? HalBuildCheck(
                halPresent: true,
                appBuildID: fixtureBuildID,
                driverBuildID: fixtureBuildID
            ),
            devices: devices ?? [testDevice]
        )
        let manager = BridgeProcessManager(
            settings: settings,
            processLauncher: mockLauncher,
            binaryURLOverride: URL(fileURLWithPath: "/tmp/apm44-bridge"),
            timing: timing,
            clock: clock,
            deviceSource: source,
            applicationTerminator: applicationTerminator
        )
        await manager.refreshDevices()
        return (manager, settings, mockLauncher, source)
    }

    private func assertStoppedAfterUnstableLaunches(_ message: String, launches: Int = 4, lastExit: Int) {
        let marker = "__DETAIL__"
        let parts = AppStrings.stoppedAfterUnstableLaunches(launches, detail: marker)
            .components(separatedBy: marker)
        XCTAssertEqual(parts.count, 2, message)
        XCTAssertTrue(message.hasPrefix(parts[0]), message)
        XCTAssertTrue(message.hasSuffix(parts[1]), message)
        XCTAssertTrue(message.contains(AppStrings.lastExit(lastExit)), message)
    }

    /// One helper metrics line in the JSON format the daemon emits; written
    /// to the mock process's stdout pipe so tests drive the real parser.
    private let metricsJSONLine =
        #"{"fill_ms":15.200,"ratio":1.08843537,"ppm":12.00,"underruns":0,"overruns":0,"xruns":0,"estimated_rt_ms":17.700,"target_fill_ms":15.000,"src_quality":"medium"}"# + "\n"

    private func writeStdout(_ text: String, launcher: MockProcessLauncher) {
        let pipe = launcher.lastProcess?.standardOutput as? Pipe
        XCTAssertNotNil(pipe, "start() must install a stdout pipe")
        try? pipe?.fileHandleForWriting.write(contentsOf: Data(text.utf8))
    }

    private func writeStderr(_ text: String, launcher: MockProcessLauncher) {
        let pipe = launcher.lastProcess?.standardError as? Pipe
        XCTAssertNotNil(pipe, "start() must install a stderr pipe")
        try? pipe?.fileHandleForWriting.write(contentsOf: Data((text + "\n").utf8))
    }

    /// Pipe readabilityHandlers hop to the main actor, so let them run
    /// before firing termination (which snapshots the stderr lines).
    /// stderr ingestion has no observable signal to poll; a late pipe can
    /// only fail a test, never pass a broken one.
    private func settlePipeDelivery() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    private func pollUntil(
        _ description: String,
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        check: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(Double(timeoutNanoseconds) / 1_000_000_000)
        while !check() {
            if Date() >= deadline {
                XCTFail("Timed out waiting for \(description)")
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testProductionLaunchUsesParentDeathPipe() async throws {
        let launcher = MockProcessLauncher()
        let settings = makeSettings()
        settings.outputDeviceUid = testDevice.uid
        let source = FakeBridgeDeviceSource(
            halCheck: HalBuildCheck(
                halPresent: true,
                appBuildID: fixtureBuildID,
                driverBuildID: fixtureBuildID
            ),
            devices: [testDevice]
        )
        let manager = BridgeProcessManager(
            settings: settings,
            processLauncher: launcher,
            binaryURLOverride: URL(fileURLWithPath: "/tmp/apm44-bridge"),
            deviceSource: source
        )
        await manager.refreshDevices()

        manager.start()

        let process = try XCTUnwrap(launcher.lastProcess)
        XCTAssertTrue(process.arguments?.contains("--parent-watch-stdin") == true)
        XCTAssertTrue(process.standardInput is Pipe)

        manager.stop()
        await launcher.fireTermination(for: process)
    }

    func testSecondGlitchKeepsFlashUntilItsOwnTimeout() async {
        let (manager, _, launcher, _) = await makeManager(
            timing: BridgeTiming(
                retryDelays: [60],
                stabilityWindow: 15,
                glitchFlashDuration: 0.3
            )
        )
        manager.start()
        func lossLine(_ frames: Int) -> String {
            metricsJSONLine.replacingOccurrences(
                of: #""xruns":0,"#,
                with: #""xruns":0,"input_dropped_frames":\#(frames),"#
            )
        }

        writeStdout(lossLine(1), launcher: launcher)
        await pollUntil("first glitch") { manager.glitchFlash }
        writeStdout(lossLine(2), launcher: launcher)
        await pollUntil("second loss applied") { manager.latestMetrics?.knownFrameLoss == 2 }
        // The first flash's cancelled timer must not switch the new one off.
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(manager.glitchFlash)
        await pollUntil("flash clears after its own duration") { !manager.glitchFlash }

        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
    }

    func testStartResetsMetricsStateAndTimestamp() async {
        let clock = FakeBridgeClock()
        let (manager, _, launcher, _) = await makeManager(
            timing: BridgeTiming(
                retryDelays: [60],
                stabilityWindow: 15,
                staleCheckInterval: 0.05
            ),
            clock: clock
        )
        manager.start()
        XCTAssertEqual(manager.state, .running)

        writeStdout(metricsJSONLine, launcher: launcher)
        await pollUntil("metrics from stdout pipe") { manager.latestMetrics != nil }
        XCTAssertNotNil(manager.latestMetrics)
        // Several watch ticks without the clock moving: still fresh.
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(manager.metricsStale)
        clock.advance(by: 10)
        await pollUntil("stale flag from watch") { manager.metricsStale }
        XCTAssertTrue(manager.metricsStale)

        // Park in reconnecting (metrics are retained there) so start()
        // exercises its reset path.
        launcher.nextTerminationStatus = 1
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        guard case .reconnecting = manager.state else {
            XCTFail("Expected reconnecting before restart, got \(manager.state)")
            return
        }
        XCTAssertNotNil(manager.latestMetrics)

        manager.start()

        XCTAssertEqual(manager.state, .running)
        XCTAssertNil(manager.latestMetrics)
        XCTAssertFalse(manager.metricsStale)
        XCTAssertNil(manager.bannerMessage)
        // The clock is already past the old stamp; a restart that kept it
        // would turn stale on the next watch tick.
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(manager.metricsStale)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        XCTAssertEqual(manager.state, .idle)
    }

    func testRunningToIdleViaUserStop() async {
        let (manager, _, launcher, _) = await makeManager()

        manager.start()
        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 1)

        manager.stop()
        XCTAssertEqual(manager.state, .stopping)
        XCTAssertEqual(manager.lastStopReason, .user)

        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(manager.lastStopReason)
    }

    func testIdleTransitionResetsMetricsStateAndTimestamp() async {
        let clock = FakeBridgeClock()
        let (manager, _, launcher, _) = await makeManager(
            timing: BridgeTiming(
                retryDelays: BridgeTiming.live.retryDelays,
                stabilityWindow: 15,
                staleCheckInterval: 0.05
            ),
            clock: clock
        )

        manager.start()
        writeStdout(metricsJSONLine, launcher: launcher)
        await pollUntil("metrics from stdout pipe") { manager.latestMetrics != nil }
        XCTAssertNotNil(manager.latestMetrics)
        clock.advance(by: 10)
        await pollUntil("stale flag from watch") { manager.metricsStale }
        XCTAssertTrue(manager.metricsStale)

        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(manager.latestMetrics)
        XCTAssertFalse(manager.metricsStale)
    }

    func testCleanRunningTerminationUsesIdleTransition() async {
        let clock = FakeBridgeClock()
        let (manager, _, launcher, _) = await makeManager(
            timing: BridgeTiming(
                retryDelays: BridgeTiming.live.retryDelays,
                stabilityWindow: 15,
                staleCheckInterval: 0.05
            ),
            clock: clock
        )

        manager.start()
        writeStdout(metricsJSONLine, launcher: launcher)
        await pollUntil("metrics from stdout pipe") { manager.latestMetrics != nil }
        XCTAssertEqual(manager.state, .running)
        XCTAssertNotNil(manager.latestMetrics)
        clock.advance(by: 10)
        await pollUntil("stale flag from watch") { manager.metricsStale }
        XCTAssertTrue(manager.metricsStale)

        launcher.nextTerminationStatus = 0
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(manager.latestMetrics)
        XCTAssertFalse(manager.metricsStale)
        XCTAssertNil(manager.lastStopReason)
    }

    func testRunningUnexpectedExit() async {
        let (manager, _, launcher, _) = await makeManager(
            timing: BridgeTiming(retryDelays: [60], stabilityWindow: 15)
        )

        manager.start()
        XCTAssertEqual(manager.state, .running)

        let generationBefore = manager.retryGeneration
        launcher.nextTerminationStatus = 1
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        if case .reconnecting = manager.state {
            XCTAssertGreaterThan(manager.retryGeneration, generationBefore)
            XCTAssertEqual(
                manager.bannerMessage,
                AppStrings.reconnectingAttempt(current: 1, max: 4)
            )
        } else {
            XCTFail("Expected reconnecting state after unexpected exit, got \(manager.state)")
        }
        XCTAssertEqual(launcher.makeCount, 1)
    }

    func testRestartFromErrorActuallyRelaunches() async {
        let (manager, _, launcher, _) = await makeManager()
        launcher.shouldFailLaunch = true
        manager.start()
        guard case .error = manager.state else {
            XCTFail("Expected launch-failure error, got \(manager.state)")
            return
        }
        launcher.shouldFailLaunch = false
        let launchesBeforeRestart = launcher.makeCount

        await manager.restart(reason: .user)

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, launchesBeforeRestart + 1)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        XCTAssertEqual(manager.state, .idle)
    }

    func testSleepStopsAndWakeResumesRunningBridge() async {
        let (manager, _, launcher, _) = await makeManager()
        manager.start()

        let sleepTask = Task { await manager.handleSystemWillSleep() }
        for _ in 0..<200 {
            if case .stopping = manager.state { break }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        await sleepTask.value

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, 1)

        await manager.handleSystemDidWake()

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 2)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
    }

    func testSleepDuringSettingsRestartDefersRelaunchToWake() async {
        let (manager, _, launcher, _) = await makeManager()
        manager.start()
        guard let old = launcher.lastProcess else { return XCTFail("no process") }

        let restart = Task { await manager.restartForSettingsChange() }
        await waitUntil { manager.state == .stopping }
        await manager.handleSystemWillSleep()
        await launcher.fireTermination(for: old)
        await restart.value

        XCTAssertEqual(manager.state, .idle, "no relaunch while the system sleeps")
        XCTAssertEqual(launcher.makeCount, 1)

        await manager.handleSystemDidWake()

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 2, "the wake relaunches exactly once")
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
    }

    func testUserStopDuringSettingsRestartCancelsRelaunch() async {
        let (manager, _, launcher, _) = await makeManager()
        manager.start()
        guard let old = launcher.lastProcess else { return XCTFail("no process") }

        let restart = Task { await manager.restartForSettingsChange() }
        await waitUntil { manager.state == .stopping }
        let stop = Task { await manager.stopAsync() }
        await launcher.fireTermination(for: old)
        await stop.value
        await restart.value

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, 1)
    }

    func testQueuedOutputFromReplacedHelperDoesNotReachReplacement() async {
        let (manager, _, launcher, _) = await makeManager()
        manager.start()
        guard let old = launcher.lastProcess else { return XCTFail("no process") }

        // Let the pipe handler queue its main-actor Task while the main actor
        // is blocked, then replace the child before that Task can run.
        writeStdout(metricsJSONLine, launcher: launcher)
        Thread.sleep(forTimeInterval: 0.3)
        launcher.markExited(old)
        manager.stop()
        manager.start()
        XCTAssertNotIdentical(launcher.lastProcess, old)
        XCTAssertNil(manager.latestMetrics)

        await settlePipeDelivery()

        XCTAssertNil(manager.latestMetrics, "the old child's metrics reached its replacement")
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
    }

    func testWakeDoesNotAutostartBridgeThatWasIdleBeforeSleep() async {
        let (manager, _, launcher, _) = await makeManager()

        await manager.handleSystemWillSleep()
        await manager.handleSystemDidWake()

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, 0)
    }

    func testWakeDuringUnfinishedSleepStopResumesBridge() async {
        let (manager, _, launcher, _) = await makeManager()
        manager.start()
        let sleepingProcess = launcher.lastProcess

        let sleep = Task { await manager.handleSystemWillSleep() }
        await waitUntil { manager.state == .stopping }
        XCTAssertEqual(manager.state, .stopping)
        var wakeFinished = false
        let wake = Task {
            await manager.handleSystemDidWake()
            wakeFinished = true
        }
        // Wake must not finish while the sleep stop is still in flight.
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(wakeFinished)
        if let proc = sleepingProcess {
            await launcher.fireTermination(for: proc)
        }
        await sleep.value
        await wake.value

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 2)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
    }

    func testWakeWhoseRefreshIsSupersededByHotplugStillResumes() async {
        let (manager, _, launcher, source) = await makeManager()
        manager.start()
        await sleepCompletingTermination(manager: manager, launcher: launcher)
        XCTAssertEqual(manager.state, .idle)

        let gate = source.gateNextListing()
        addTeardownBlock { gate.release() }
        let wake = Task { await manager.handleSystemDidWake() }
        await waitUntil { gate.isHolding }
        XCTAssertTrue(gate.isHolding)
        await manager.handleHotplug()
        gate.release()
        await wake.value

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 2)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
    }

    func testUserStopDuringWakeCancelsResume() async {
        let (manager, _, launcher, source) = await makeManager()
        manager.start()
        await sleepCompletingTermination(manager: manager, launcher: launcher)
        XCTAssertEqual(manager.state, .idle)

        let gate = source.gateNextListing()
        addTeardownBlock { gate.release() }
        let wake = Task { await manager.handleSystemDidWake() }
        await waitUntil { gate.isHolding }
        XCTAssertTrue(gate.isHolding)
        manager.stop()
        gate.release()
        await wake.value

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, 1)
    }

    func testSecondSleepDuringWakeRefreshKeepsResumeIntent() async {
        let (manager, _, launcher, source) = await makeManager()
        manager.start()
        await sleepCompletingTermination(manager: manager, launcher: launcher)
        XCTAssertEqual(manager.state, .idle)

        let gate = source.gateNextListing()
        addTeardownBlock { gate.release() }
        let wake = Task { await manager.handleSystemDidWake() }
        await waitUntil { gate.isHolding }
        XCTAssertTrue(gate.isHolding)
        manager.start()
        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 2)
        let restartedProcess = launcher.lastProcess
        let secondSleep = Task { await manager.handleSystemWillSleep() }
        await waitUntil { manager.state == .stopping }
        XCTAssertEqual(manager.state, .stopping)
        gate.release()
        await wake.value
        if let proc = restartedProcess {
            await launcher.fireTermination(for: proc)
        }
        await secondSleep.value
        XCTAssertEqual(manager.state, .idle)

        await manager.handleSystemDidWake()

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 3)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
    }

    func testSleepDuringIdleWakeRefreshDefersResumeToNextWake() async {
        let (manager, _, launcher, source) = await makeManager()
        manager.start()
        await sleepCompletingTermination(manager: manager, launcher: launcher)
        XCTAssertEqual(manager.state, .idle)

        let gate = source.gateNextListing()
        addTeardownBlock { gate.release() }
        let wake = Task { await manager.handleSystemDidWake() }
        await waitUntil { gate.isHolding }
        XCTAssertTrue(gate.isHolding)
        await manager.handleSystemWillSleep()
        gate.release()
        await wake.value
        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, 1)

        await manager.handleSystemDidWake()

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 2)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
    }

    func testUserStopNoAutoRetry() async {
        let (manager, _, launcher, _) = await makeManager(
            timing: BridgeTiming(retryDelays: [0.01], stabilityWindow: 15)
        )

        manager.start()
        let generationBefore = manager.retryGeneration
        manager.stop()

        // A recoverable stale-ring exit must not override the user's stop.
        writeStderr("stale shm ring: invalid header", launcher: launcher)
        await settlePipeDelivery()
        launcher.nextTerminationStatus = 42
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(manager.retryGeneration, generationBefore)
        XCTAssertEqual(launcher.makeCount, 1)
    }

    func testQuitApplicationStopsRunningBridgeBeforeTerminating() async {
        var didTerminate = false
        let (manager, _, launcher, _) = await makeManager {
            didTerminate = true
        }

        manager.start()
        XCTAssertEqual(manager.state, .running)

        let quitTask = Task { await manager.quitApplication() }
        for _ in 0..<200 {
            if case .stopping = manager.state { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        XCTAssertEqual(manager.state, .stopping)
        XCTAssertEqual(manager.lastStopReason, .user)
        XCTAssertFalse(didTerminate)

        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        await quitTask.value

        XCTAssertEqual(manager.state, .idle)
        XCTAssertTrue(didTerminate)
    }

    func testQuitApplicationCancelsReconnectWithoutLaunchingOrReloadingDriver() async {
        var didTerminate = false
        let (manager, _, launcher, _) = await makeManager(
            timing: BridgeTiming(retryDelays: [60], stabilityWindow: 15)
        ) {
            didTerminate = true
        }

        manager.start()
        launcher.nextTerminationStatus = 1
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        guard case .reconnecting = manager.state else {
            XCTFail("Expected reconnecting before quit, got \(manager.state)")
            return
        }
        let makeCountBeforeQuit = launcher.makeCount

        await manager.quitApplication()

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, makeCountBeforeQuit)
        XCTAssertTrue(didTerminate)
    }

    func testHotplugWhileIdleRefreshesDevices() async {
        let (manager, _, _, source) = await makeManager()
        source.devices = []
        await manager.refreshDevices()
        let generationBefore = manager.hotplugRefreshGeneration

        await manager.handleHotplug()

        XCTAssertGreaterThan(manager.hotplugRefreshGeneration, generationBefore)
    }

    func testHotplugWhileIdleDoesNotStartBridge() async {
        let (manager, _, launcher, _) = await makeManager()
        XCTAssertEqual(manager.state, .idle)

        await manager.handleHotplug()

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, 0)
    }

    func testSelectedAudioDeviceChangeRestartsRunningBridge() async {
        let (manager, _, launcher, source) = await makeManager()

        manager.start()
        XCTAssertEqual(manager.state, .running)
        let makeCountBefore = launcher.makeCount
        source.devices = [
            AudioDeviceRow(
                uid: testDevice.uid,
                name: testDevice.name,
                nominalRate: 48_000,
                hasInput: false,
                hasOutput: true,
                bufferFrameSize: 256
            )
        ]

        await awaitHotplugCompletingTermination(manager: manager, launcher: launcher)

        XCTAssertGreaterThan(launcher.makeCount, makeCountBefore)
        XCTAssertEqual(manager.state, .running)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
    }

    func testOverlappingHotplugsRestartRunningBridgeOnce() async {
        let (manager, _, launcher, source) = await makeManager()
        manager.start()
        let firstProcess = launcher.lastProcess
        source.devices = [
            AudioDeviceRow(
                uid: testDevice.uid,
                name: testDevice.name,
                nominalRate: 48_000,
                hasInput: false,
                hasOutput: true,
                bufferFrameSize: 256
            )
        ]
        let olderGate = source.gateNextListing()
        let newerGate = source.gateNextListing()
        addTeardownBlock {
            olderGate.release()
            newerGate.release()
        }

        let older = Task { await manager.handleHotplug() }
        await waitUntil { olderGate.isHolding }
        let newer = Task { await manager.handleHotplug() }
        await waitUntil { newerGate.isHolding }
        XCTAssertTrue(olderGate.isHolding && newerGate.isHolding)
        // The superseded refresh finishes first and joins the newer one, so
        // both hotplugs resume together when the newer listing returns.
        olderGate.release()
        try? await Task.sleep(nanoseconds: 50_000_000)
        newerGate.release()
        await waitUntil { manager.state == .stopping }
        if let proc = firstProcess {
            await launcher.fireTermination(for: proc)
        }
        await waitUntil { launcher.makeCount >= 2 && manager.state == .running }
        // A duplicate restart would stop the replacement right away.
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 2)
        // Finish a duplicate restart's stop so both handlers return.
        while manager.state == .stopping, let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
            await waitUntil { manager.state != .stopping }
        }
        await older.value
        await newer.value
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
    }

    func testUnrelatedAudioDeviceChangeDoesNotRestartRunningBridge() async {
        let (manager, _, launcher, source) = await makeManager()
        let unrelatedDevice = AudioDeviceRow(
            uid: "unrelated-output-uid",
            name: "Studio Display Speakers",
            nominalRate: 48_000,
            hasInput: false,
            hasOutput: true
        )

        manager.start()
        XCTAssertEqual(manager.state, .running)
        let makeCountBefore = launcher.makeCount
        source.devices = [testDevice, unrelatedDevice]

        await manager.handleHotplug()

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, makeCountBefore)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
    }

    func testStartRejectsSelectedUidMissingFromCurrentDeviceList() async {
        let (manager, settings, launcher, _) = await makeManager()
        settings.outputDeviceUid = "missing-output"

        manager.start()

        XCTAssertEqual(manager.state, .error(AppStrings.selectedOutputGone))
        XCTAssertNil(manager.bannerMessage)
        XCTAssertEqual(launcher.makeCount, 0)
    }

    func testStartRejectsIncompatibleSelectedOutputBeforeLaunch() async {
        let incompatible = AudioDeviceRow(
            uid: "mono-output",
            name: "Mono Output",
            nominalRate: 48_000,
            hasInput: false,
            hasOutput: true,
            outputChannels: 1
        )
        let (manager, settings, launcher, _) = await makeManager(devices: [incompatible])
        settings.outputDeviceUid = incompatible.uid

        manager.start()

        XCTAssertEqual(launcher.makeCount, 0)
        if case .error(let message) = manager.state {
            XCTAssertTrue(message.localizedCaseInsensitiveContains("stereo"))
        } else {
            XCTFail("Expected compatibility error, got \(manager.state)")
        }
    }

    func testReconnectAfterDisconnectAutoStarts() async {
        let (manager, settings, launcher, source) = await makeManager()

        manager.start()
        XCTAssertEqual(manager.state, .running)

        source.devices = []
        await awaitHotplugCompletingTermination(manager: manager, launcher: launcher)

        if case .reconnecting = manager.state {
            // expected
        } else {
            XCTFail("Expected reconnecting before auto-restart, got \(manager.state)")
        }
        XCTAssertEqual(launcher.makeCount, 1)
        XCTAssertEqual(manager.bannerMessage, AppStrings.waitingForOutput(manager.deviceDisplayName))

        source.devices = [testDevice]
        settings.outputDeviceUid = testDevice.uid
        await manager.handleHotplug()

        XCTAssertEqual(manager.state, .running)
        XCTAssertGreaterThan(launcher.makeCount, 1)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
    }

    func testDisconnectWhileIdleStaysIdle() async {
        let (manager, settings, launcher, source) = await makeManager()
        settings.outputDeviceUid = testDevice.uid
        source.devices = []

        await manager.handleHotplug()

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, 0)
    }

    func testInvalidSelectedDeviceCleared() async {
        let (manager, settings, _, source) = await makeManager()
        settings.outputDeviceUid = "BH-UID"
        let airpods = AudioDeviceRow(
            uid: "AP-UID",
            name: "AirPods Max",
            nominalRate: 48_000,
            hasInput: false,
            hasOutput: true
        )

        source.devices = [airpods]
        await manager.refreshDevices()

        XCTAssertNil(settings.outputDeviceUid)
        XCTAssertEqual(manager.bannerMessage, AppStrings.previousOutputSelect)
    }

    func testReconnectingRetryCanBeInterruptedByStop() async {
        let (manager, _, launcher, _) = await makeManager(
            timing: BridgeTiming(retryDelays: [60], stabilityWindow: 15)
        )

        manager.start()
        launcher.nextTerminationStatus = 1
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        guard case .reconnecting = manager.state else {
            XCTFail("Expected reconnecting retry wait, got \(manager.state)")
            return
        }

        XCTAssertFalse(
            manager.isTransitioning,
            "Reconnecting is a retry wait, so Stop Bridge must remain clickable"
        )

        manager.stop()

        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(manager.bannerMessage)
    }

    func testRetryExhaustionFromZeroAttempt() async {
        let launcher = MockProcessLauncher()
        launcher.failLaunchesAfterFirstSuccess = true
        let (manager, _, _, _) = await makeManager(
            launcher: launcher,
            timing: BridgeTiming(retryDelays: [0], stabilityWindow: 15)
        )

        manager.start()
        XCTAssertEqual(manager.state, .running)

        launcher.nextTerminationStatus = 1
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        for _ in 0..<200 {
            if case .error = manager.state { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        if case .error(let message) = manager.state {
            assertStoppedAfterUnstableLaunches(message, lastExit: 1)
            XCTAssertEqual(manager.bannerMessage, message, "exhausted retry counter must surface as the banner")
        } else {
            XCTFail("Expected final error after retries from zero, got \(manager.state)")
        }
    }

    func testCrashLoopExhaustsAfterFourShortLivedSuccessfulLaunches() async {
        let (manager, _, launcher, _) = await makeManager(
            timing: BridgeTiming(retryDelays: [0], stabilityWindow: 15)
        )

        manager.start()
        XCTAssertEqual(launcher.makeCount, 1)

        for unhealthyLaunch in 1...4 {
            guard let proc = launcher.lastProcess else {
                XCTFail("Missing process for unhealthy launch \(unhealthyLaunch)")
                return
            }
            launcher.nextTerminationStatus = 17
            await launcher.fireTermination(for: proc)

            if unhealthyLaunch < 4 {
                for _ in 0..<100 where launcher.makeCount == unhealthyLaunch {
                    try? await Task.sleep(nanoseconds: 2_000_000)
                }
                XCTAssertEqual(launcher.makeCount, unhealthyLaunch + 1)
            }
        }

        if case .error(let message) = manager.state {
            assertStoppedAfterUnstableLaunches(message, lastExit: 17)
            XCTAssertEqual(manager.bannerMessage, message, "exhausted retry counter must surface as the banner")
        } else {
            XCTFail("Expected bounded crash-loop error, got \(manager.state)")
        }
        XCTAssertEqual(launcher.makeCount, 4, "A fifth unhealthy launch must never occur")
    }

    func testRetryBudgetResetsOnlyAfterMetricsAndStabilityWindow() async {
        let (manager, _, launcher, _) = await makeManager(
            timing: BridgeTiming(retryDelays: [0], stabilityWindow: 0)
        )

        manager.start()
        launcher.nextTerminationStatus = 17
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        for _ in 0..<100 where launcher.makeCount < 2 {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(launcher.makeCount, 2)
        XCTAssertNil(manager.latestMetrics, "fresh retry launch must not have metrics yet")
        XCTAssertEqual(
            manager.bannerMessage,
            AppStrings.reconnectingAttempt(current: 1, max: 4)
        )

        writeStdout(metricsJSONLine, launcher: launcher)
        await pollUntil("metrics from stdout pipe") { manager.latestMetrics != nil }
        await pollUntil("stability reset clears retry banner") { manager.bannerMessage == nil }

        XCTAssertNil(manager.bannerMessage, "Recovery must remove its reconnecting banner")

        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
    }

    func testStopAndStartDuringRecoveryClearsRetryBanner() async {
        let (manager, _, launcher, _) = await makeManager(
            timing: BridgeTiming(retryDelays: [0], stabilityWindow: 15)
        )
        manager.start()
        launcher.nextTerminationStatus = 17
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        for _ in 0..<100 where launcher.makeCount < 2 {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(manager.state, .running)
        XCTAssertNotNil(manager.bannerMessage)

        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(manager.bannerMessage)
        manager.start()
        XCTAssertEqual(manager.state, .running)
        XCTAssertNil(manager.bannerMessage)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
    }

    func testStableRecoveryPreservesUnrelatedNotice() async {
        let (manager, _, launcher, _) = await makeManager(
            timing: BridgeTiming(
                retryDelays: BridgeTiming.live.retryDelays,
                stabilityWindow: 0
            )
        )
        // Reach retry attempt 1 through a real unexpected exit...
        manager.start()
        XCTAssertEqual(manager.state, .running)
        launcher.nextTerminationStatus = 1
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        guard case .reconnecting = manager.state else {
            XCTFail("Expected reconnecting before retry, got \(manager.state)")
            return
        }
        XCTAssertEqual(manager.bannerMessage, AppStrings.reconnectingAttempt(current: 1, max: 4))
        // ...and relaunch the way the scheduled retry would, preserving the attempt.
        manager.start(resetRetryAttempt: false)
        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(manager.bannerMessage, AppStrings.reconnectingAttempt(current: 1, max: 4))
        manager.bannerMessage = "Could not enable launch at login"
        writeStdout(metricsJSONLine, launcher: launcher)
        await pollUntil("metrics from stdout pipe") { manager.latestMetrics != nil }
        XCTAssertEqual(manager.bannerMessage, "Could not enable launch at login")
        // Clearing the notice must not reveal a reconnecting banner: the
        // stability reset cleared the retry counter underneath the notice.
        manager.bannerMessage = nil
        await pollUntil("stability reset clears retry counter") { manager.bannerMessage == nil }
        XCTAssertNil(manager.bannerMessage)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
    }

    func testStaleRingExitRelaunchesVirtualDeviceHelper() async {
        let (manager, _, launcher, _) = await makeManager(
            timing: BridgeTiming(retryDelays: [0], stabilityWindow: 15)
        )

        manager.start()
        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 1)
        XCTAssertEqual(launcher.lastProcess?.arguments?.first, "--virtual-device")

        launcher.nextTerminationStatus = 42
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        launcher.nextTerminationStatus = nil
        await waitUntil { launcher.makeCount == 2 && manager.state == .running }

        XCTAssertEqual(launcher.makeCount, 2)
        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.lastProcess?.arguments?.first, "--virtual-device")
    }

    func testHelperAlreadyRunningExitShowsErrorWithoutRetry() async {
        let (manager, _, launcher, _) = await makeManager(
            timing: BridgeTiming(retryDelays: [60], stabilityWindow: 15)
        )

        manager.start()
        XCTAssertEqual(manager.state, .running)

        let generationBefore = manager.retryGeneration
        launcher.nextTerminationStatus = DaemonExitCode.singletonBusy.rawValue
        writeStderr("error: another apm44-bridge helper already owns the singleton lock", launcher: launcher)
        await settlePipeDelivery()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        XCTAssertEqual(manager.state, .error(AppStrings.helperAlreadyRunning))
        XCTAssertEqual(manager.bannerMessage, AppStrings.helperAlreadyRunning)
        XCTAssertEqual(manager.retryGeneration, generationBefore)
        XCTAssertEqual(launcher.makeCount, 1)
        // Clearing the notice must not reveal a reconnecting banner: exit 43 schedules no retry.
        manager.bannerMessage = nil
        XCTAssertNil(manager.bannerMessage)
    }

    func testStaleRingFailureMessageIsActionable() async {
        let (manager, _, launcher, _) = await makeManager()
        manager.start()
        XCTAssertEqual(manager.state, .running)

        writeStderr("stale shm ring: invalid shm ring header", launcher: launcher)
        await settlePipeDelivery()
        // `.starting` is synchronously transient, so force it to cover the
        // termination-during-start failure path.
        manager.setStateForTesting(.starting)
        launcher.nextTerminationStatus = 1
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        XCTAssertEqual(manager.state, .error(AppStrings.ipcFailed()))
    }

    func testSettingsRestartWaitsForTermination() async {
        let launcher = MockProcessLauncher()
        launcher.terminationDelayNanoseconds = 200_000_000
        let (manager, _, _, _) = await makeManager(launcher: launcher)

        manager.start()
        XCTAssertEqual(launcher.makeCount, 1)

        let restartTask = Task {
            await manager.restartForSettingsChange()
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(launcher.makeCount, 1, "start() must not run until termination completes")

        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        await restartTask.value

        XCTAssertGreaterThanOrEqual(launcher.makeCount, 2)
        XCTAssertEqual(manager.lastStopReason, nil)
    }

    // PROC-03: two concurrent termination waiters must both unblock when
    // the daemon terminates. The old single-slot continuation would
    // overwrite the first waiter; the new id-keyed map registers each
    // caller and drains the full map on termination.
    func testConcurrentTerminationWaitersAllComplete() async {
        let (manager, _, launcher, _) = await makeManager()

        manager.start()
        XCTAssertEqual(manager.state, .running)

        // Kick off two concurrent stop calls. Each invokes
        // `finishStopWithEscalation` → `waitForTermination` →
        // `terminationWaiters[id] =`. Both must unblock when
        // the daemon fires its termination handler.
        let stop1 = Task { @MainActor in
            manager.stop()
        }
        let stop2 = Task { @MainActor in
            manager.stop()
        }

        // Give both tasks a moment to enter waitForTermination and register
        // in the waiter map.
        try? await Task.sleep(nanoseconds: 20_000_000)

        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        // Both awaiters must complete without hanging.
        await stop1.value
        await stop2.value

        XCTAssertEqual(manager.state, .idle)
    }

    func testStopEscalatesToSigkillWhenHelperIgnoresSigterm() async {
        var t = BridgeTiming.live
        t.stopTimeout = 0.05
        let (manager, _, launcher, _) = await makeManager(timing: t)
        launcher.terminateOnForceKill = true
        manager.start()
        XCTAssertEqual(manager.state, .running)
        let started = launcher.lastProcess
        XCTAssertNotNil(started)

        let clock = ContinuousClock()
        let start = clock.now
        await manager.stopAsync()
        let elapsed = clock.now - start

        XCTAssertTrue(elapsed < .seconds(2), "stopAsync hung: elapsed \(elapsed)")
        XCTAssertEqual(launcher.forceKilled.count, 1)
        XCTAssertTrue(launcher.forceKilled.first === started)
        XCTAssertEqual(manager.state, .idle)
    }

    func testStopReturnsWhenHelperSurvivesSigkill() async {
        var t = BridgeTiming.live
        t.stopTimeout = 0.05
        let (manager, _, launcher, _) = await makeManager(timing: t)
        // Helper ignores SIGTERM and survives SIGKILL (no termination).
        launcher.terminateOnForceKill = false
        manager.start()
        XCTAssertEqual(manager.state, .running)

        let clock = ContinuousClock()
        let start = clock.now
        await manager.stopAsync()
        let elapsed = clock.now - start

        XCTAssertTrue(elapsed < .seconds(2), "stopAsync hung: elapsed \(elapsed)")
        XCTAssertEqual(launcher.forceKilled.count, 1)
        // FIX 1: a failed SIGKILL surfaces .error(bridgeDidNotStop) instead
        // of parking in .stopping with Quit/Stop/Restart disabled.
        XCTAssertEqual(manager.state, .error(AppStrings.bridgeDidNotStop))

        // FIX 2a: the mock Process never launched, so stub the exit status
        // that handleTermination reads outside .stopping.
        launcher.nextTerminationStatus = 9
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        await waitUntil { manager.state == .idle }
        XCTAssertEqual(manager.state, .idle)
    }

    func testWakeParksWhenSleepStopNeverFinishes() async {
        var t = BridgeTiming.live
        t.stopTimeout = 0.05
        let (manager, _, launcher, _) = await makeManager(timing: t)
        // Helper never terminates, so the sleep stop never finishes.
        launcher.terminateOnForceKill = false
        manager.start()
        XCTAssertEqual(manager.state, .running)

        let sleep = Task { await manager.handleSystemWillSleep() }
        await waitUntil { manager.state == .stopping }
        XCTAssertEqual(manager.state, .stopping)

        let clock = ContinuousClock()
        let start = clock.now
        await manager.handleSystemDidWake()
        let elapsed = clock.now - start

        XCTAssertTrue(elapsed < .seconds(2), "wake hung: elapsed \(elapsed)")
        XCTAssertEqual(manager.state, .reconnecting)
        XCTAssertEqual(manager.bannerMessage, AppStrings.waitingForDevicesAfterWake)

        await sleep.value
        // FIX 2b: the stuck helper's late exit resumes the parked wake when
        // the selected output is present. The mock Process never launched,
        // so stub the exit status that handleTermination reads.
        launcher.nextTerminationStatus = 9
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        await waitUntil { manager.state == .running }
        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 2)
        XCTAssertNil(manager.bannerMessage)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        XCTAssertEqual(manager.state, .idle)
    }

    func testFailedUserStopShowsErrorAndReenablesQuit() async {
        var t = BridgeTiming.live
        t.stopTimeout = 0.05
        let (manager, _, launcher, _) = await makeManager(timing: t)
        // Helper survives SIGKILL (no termination on force-kill).
        launcher.terminateOnForceKill = false
        manager.start()
        XCTAssertEqual(manager.state, .running)

        await manager.stopAsync()

        XCTAssertEqual(manager.state, .error(AppStrings.bridgeDidNotStop))
        XCTAssertEqual(manager.connectionPhase, .stopped)
        let presentation = MenuPresentation(
            state: manager.state,
            isApplyingSettings: manager.isApplyingSettings,
            connectionPhase: manager.connectionPhase,
            bannerMessage: manager.bannerMessage,
            metricsStale: manager.metricsStale,
            startBlockedReason: manager.startBlockedReason,
            latestMetrics: manager.latestMetrics,
            heldMetrics: nil
        )
        XCTAssertFalse(presentation.quitDisabled)

        // Settle the stuck helper so the test leaves no live process.
        // The mock Process never launched, so stub the exit status that
        // handleTermination reads outside .stopping.
        launcher.nextTerminationStatus = 9
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        await waitUntil { manager.state == .idle }
        XCTAssertEqual(manager.state, .idle)
    }

    func testStuckHelperLateExitAfterFailedStopGoesIdle() async {
        var t = BridgeTiming.live
        t.stopTimeout = 0.05
        let (manager, _, launcher, _) = await makeManager(timing: t)
        launcher.terminateOnForceKill = false
        manager.start()
        XCTAssertEqual(manager.state, .running)

        await manager.stopAsync()
        XCTAssertEqual(manager.state, .error(AppStrings.bridgeDidNotStop))

        // The mock Process never launched, so stub the exit status that
        // handleTermination reads outside .stopping.
        launcher.nextTerminationStatus = 9
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        await waitUntil { manager.state == .idle }
        XCTAssertEqual(manager.state, .idle)

        manager.start()
        XCTAssertEqual(launcher.makeCount, 2)
        XCTAssertEqual(manager.state, .running)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        XCTAssertEqual(manager.state, .idle)
    }

    func testLateExitAfterWakeParkResumesWhenOutputPresent() async {
        var t = BridgeTiming.live
        t.stopTimeout = 0.05
        let (manager, _, launcher, _) = await makeManager(timing: t)
        // Helper never terminates, so the sleep stop never finishes.
        launcher.terminateOnForceKill = false
        manager.start()
        XCTAssertEqual(manager.state, .running)

        let sleep = Task { await manager.handleSystemWillSleep() }
        await waitUntil { manager.state == .stopping }
        await manager.handleSystemDidWake()
        XCTAssertEqual(manager.state, .reconnecting)
        XCTAssertEqual(manager.bannerMessage, AppStrings.waitingForDevicesAfterWake)
        await sleep.value

        // The mock Process never launched, so stub the exit status that
        // handleTermination reads outside .stopping.
        launcher.nextTerminationStatus = 9
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        await waitUntil { manager.state == .running }
        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 2)
        XCTAssertNil(manager.bannerMessage)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        XCTAssertEqual(manager.state, .idle)
    }

    func testLateExitAfterWakeParkStaysParkedWhenOutputMissing() async {
        var t = BridgeTiming.live
        t.stopTimeout = 0.05
        let (manager, _, launcher, source) = await makeManager(timing: t)
        // Helper never terminates, so the sleep stop never finishes.
        launcher.terminateOnForceKill = false
        manager.start()
        XCTAssertEqual(manager.state, .running)

        let sleep = Task { await manager.handleSystemWillSleep() }
        await waitUntil { manager.state == .stopping }
        await manager.handleSystemDidWake()
        XCTAssertEqual(manager.state, .reconnecting)
        XCTAssertEqual(manager.bannerMessage, AppStrings.waitingForDevicesAfterWake)
        await sleep.value

        // Take the selected output away and sync the manager's cached list
        // so the late-exit resume check sees it missing.
        source.devices = []
        await manager.refreshDevices()
        XCTAssertEqual(manager.bannerMessage, AppStrings.waitingForDevicesAfterWake)

        // The mock Process never launched, so stub the exit status that
        // handleTermination reads outside .stopping.
        launcher.nextTerminationStatus = 9
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        // Let any resume attempt run; the park must survive it.
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(manager.state, .reconnecting)
        XCTAssertEqual(manager.bannerMessage, AppStrings.waitingForDevicesAfterWake)
        XCTAssertEqual(launcher.makeCount, 1)
        manager.stop()
        XCTAssertEqual(manager.state, .idle)
    }

    func testConcurrentStopAsyncWaitersBothReleasedBySingleTermination() async {
        let (manager, _, launcher, _) = await makeManager()
        manager.start()
        XCTAssertEqual(manager.state, .running)

        let stop1 = Task { @MainActor in await manager.stopAsync() }
        let stop2 = Task { @MainActor in await manager.stopAsync() }
        // Let both enter waitForTermination before the single exit.
        try? await Task.sleep(nanoseconds: 20_000_000)

        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        await stop1.value
        await stop2.value

        XCTAssertEqual(manager.state, .idle)
    }

    // Stale-route repair: start() must derive launch args and connection
    // phase from the same live halPresent used for the build gate, not
    // from a stale cached routingMode. Uses a fake device source so no
    // real audio or HAL enumeration runs.
    func testStartWithStaleFallbackCacheUsesLiveHalRoute() async {
        let (manager, _, launcher, source) = await makeManager()
        source.halCheck = HalBuildCheck(
            halPresent: false,
            appBuildID: fixtureBuildID,
            driverBuildID: nil
        )
        manager.refreshRoutingMode()
        XCTAssertEqual(manager.routingMode, .blackHoleFallback)
        source.halCheck = HalBuildCheck(
            halPresent: true,
            appBuildID: fixtureBuildID,
            driverBuildID: fixtureBuildID
        )

        manager.start()

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(manager.routingMode, .halVirtualDevice)
        XCTAssertTrue(launcher.lastProcess?.arguments?.contains("--virtual-device") == true)
        XCTAssertEqual(manager.connectionPhase, .waitingForDAW)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
    }

    func testStartWithStaleHalCacheUsesLiveFallbackRoute() async {
        let (manager, _, launcher, source) = await makeManager()
        XCTAssertEqual(manager.routingMode, .halVirtualDevice)
        source.halCheck = HalBuildCheck(
            halPresent: false,
            appBuildID: fixtureBuildID,
            driverBuildID: nil
        )

        manager.start()

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(manager.routingMode, .blackHoleFallback)
        XCTAssertFalse(launcher.lastProcess?.arguments?.contains("--virtual-device") == true)
        XCTAssertEqual(manager.connectionPhase, .running)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
    }

    func testStaleHalCacheWithMismatchStillBlocksWithoutFallbackLaunch() async {
        let (manager, _, launcher, source) = await makeManager()
        XCTAssertEqual(manager.routingMode, .halVirtualDevice)
        source.halCheck = HalBuildCheck(
            halPresent: true,
            appBuildID: fixtureBuildID,
            driverBuildID: "0.12.7+other-build-mismatch"
        )

        manager.start()

        XCTAssertEqual(launcher.makeCount, 0)
        if case .error = manager.state {
        } else {
            XCTFail("expected .error on build mismatch, got \(manager.state)")
        }
    }

    func testLoadedDriverBuildMismatchWhileRunningShowsErrorWithoutRetry() async {
        XCTAssertEqual(DaemonExitCode.loadedDriverBuildMismatch.rawValue, 44)
        for preState in ["running", "starting"] {
            let (manager, _, launcher, _) = await makeManager(
                timing: BridgeTiming(retryDelays: [60], stabilityWindow: 15)
            )

            manager.start()
            XCTAssertEqual(manager.state, .running)
            if preState == "starting" {
                manager.setStateForTesting(.starting)
            }

            let generationBefore = manager.retryGeneration
            launcher.nextTerminationStatus = DaemonExitCode.loadedDriverBuildMismatch.rawValue
            if let proc = launcher.lastProcess {
                await launcher.fireTermination(for: proc)
            }

            XCTAssertEqual(manager.state, .error(AppStrings.loadedDriverBuildMismatch), "pre-state \(preState)")
            if case .reconnecting = manager.state {
                XCTFail("Exit 44 must not auto-retry (pre-state \(preState)), got reconnecting")
            }
            XCTAssertEqual(manager.bannerMessage, AppStrings.loadedDriverBuildMismatch, "pre-state \(preState)")
            XCTAssertEqual(manager.retryGeneration, generationBefore, "pre-state \(preState)")
            XCTAssertEqual(launcher.makeCount, 1, "pre-state \(preState)")
            // Clearing the notice must not reveal a reconnecting banner: exit 44 schedules no retry.
            manager.bannerMessage = nil
            XCTAssertNil(manager.bannerMessage, "pre-state \(preState)")
        }
    }

    func testLoadedDriverBuildMismatchResetsExistingRetryBudget() async {
        let (manager, _, launcher, _) = await makeManager(
            timing: BridgeTiming(retryDelays: [0], stabilityWindow: 15)
        )

        manager.start()
        XCTAssertEqual(manager.state, .running)
        // Reach retry attempt 2 through two real short-lived crashes.
        for expectedAttempt in 1...2 {
            launcher.nextTerminationStatus = 1
            if let proc = launcher.lastProcess {
                await launcher.fireTermination(for: proc)
            }
            let expectedLaunches = expectedAttempt + 1
            for _ in 0..<200 where launcher.makeCount < expectedLaunches {
                try? await Task.sleep(nanoseconds: 2_000_000)
            }
            XCTAssertEqual(launcher.makeCount, expectedLaunches)
            XCTAssertEqual(
                manager.bannerMessage,
                AppStrings.reconnectingAttempt(current: expectedAttempt, max: 4)
            )
        }

        launcher.nextTerminationStatus = DaemonExitCode.loadedDriverBuildMismatch.rawValue
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        XCTAssertEqual(manager.state, .error(AppStrings.loadedDriverBuildMismatch))
        XCTAssertEqual(manager.bannerMessage, AppStrings.loadedDriverBuildMismatch)
        XCTAssertEqual(launcher.makeCount, 3)
        // Clearing the notice must not reveal a reconnecting banner: exit 44 reset the budget.
        manager.bannerMessage = nil
        XCTAssertNil(manager.bannerMessage)
    }

    func testSettingsRestartWhileIdleLeavesApplyingFalse() async {
        let (manager, _, launcher, _) = await makeManager()

        XCTAssertEqual(manager.state, .idle)
        XCTAssertFalse(manager.isApplyingSettings)

        await manager.restartForSettingsChange()

        XCTAssertFalse(manager.isApplyingSettings)
        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, 0)
    }

    func testApplyingSettingsTrueDuringRestartThenFalse() async {
        let launcher = MockProcessLauncher()
        launcher.terminationDelayNanoseconds = 200_000_000
        let (manager, _, _, _) = await makeManager(launcher: launcher)

        manager.start()
        XCTAssertEqual(launcher.makeCount, 1)
        XCTAssertFalse(manager.isApplyingSettings)

        let restartTask = Task { await manager.restartForSettingsChange() }

        for _ in 0..<200 {
            if case .stopping = manager.state { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        guard case .stopping = manager.state else {
            XCTFail("Expected stopping while settings restart waits, got \(manager.state)")
            await restartTask.value
            return
        }
        XCTAssertTrue(manager.isApplyingSettings)

        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        await restartTask.value

        XCTAssertEqual(manager.state, .running)
        XCTAssertFalse(manager.isApplyingSettings)
    }

    func testSettingsRestartCoalescingLaunchesAtMostOnceMore() async {
        let launcher = MockProcessLauncher()
        let (manager, settings, _, _) = await makeManager(launcher: launcher)

        manager.start()
        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 1)

        let first = Task { await manager.restartForSettingsChange() }
        for _ in 0..<200 {
            if case .stopping = manager.state { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        guard case .stopping = manager.state else {
            XCTFail("Expected stopping for in-flight restart, got \(manager.state)")
            await first.value
            return
        }

        settings.srcQualityOverride = .high
        let second = Task { await manager.restartForSettingsChange() }
        settings.srcQualityOverride = .best
        let third = Task { await manager.restartForSettingsChange() }

        for _ in 0..<300 {
            if case .stopping = manager.state, let proc = launcher.lastProcess {
                await launcher.fireTermination(for: proc)
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
            if launcher.makeCount == 3, manager.state == .running { break }
        }

        await first.value
        await second.value
        await third.value

        for _ in 0..<100 {
            if launcher.makeCount == 3, manager.state == .running { break }
            if case .stopping = manager.state, let proc = launcher.lastProcess {
                await launcher.fireTermination(for: proc)
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(launcher.makeCount, 3)
        XCTAssertEqual(manager.state, .running)
        XCTAssertFalse(manager.isApplyingSettings)
        let args = launcher.lastProcess?.arguments ?? []
        if let index = args.firstIndex(of: "--src-quality") {
            XCTAssertEqual(args[index + 1], "best")
        } else {
            XCTFail("Last launch must carry --src-quality, got \(args)")
        }
    }

    func testStartBlockedReasonUsesCachedValues() async {
        let (manager, _, _, source) = await makeManager()

        manager.start()
        XCTAssertEqual(manager.state, .running)
        XCTAssertNil(manager.startBlockedReason)

        source.halCheck = HalBuildCheck(
            halPresent: true,
            appBuildID: fixtureBuildID,
            driverBuildID: "0.12.7+other-build-mismatch"
        )
        manager.refreshRoutingMode()
        XCTAssertEqual(manager.startBlockedReason, AppStrings.driverBuildMismatch)

        source.halCheck = HalBuildCheck(
            halPresent: true,
            appBuildID: fixtureBuildID,
            driverBuildID: fixtureBuildID
        )
        manager.refreshRoutingMode()
        XCTAssertNil(manager.startBlockedReason)
    }

    // (1) The remembered output name survives a relaunch: a new manager built
    // on the same UserDefaults suite shows it while the device list is empty.
    func testDeviceNamePersistsAcrossManagersForSameSuite() async {
        let suite = "com.niko.apm44.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }

        let settings1 = BridgeSettings(defaults: defaults)
        settings1.outputDeviceUid = testDevice.uid
        let manager1 = BridgeProcessManager(
            settings: settings1,
            processLauncher: MockProcessLauncher(),
            binaryURLOverride: URL(fileURLWithPath: "/tmp/apm44-bridge"),
            deviceSource: FakeBridgeDeviceSource(
                halCheck: HalBuildCheck(
                    halPresent: true,
                    appBuildID: fixtureBuildID,
                    driverBuildID: fixtureBuildID
                ),
                devices: [testDevice]
            ),
            applicationTerminator: {}
        )
        await manager1.refreshDevices()
        XCTAssertEqual(settings1.outputDeviceName, testDevice.name)

        let settings2 = BridgeSettings(defaults: defaults)
        XCTAssertEqual(settings2.outputDeviceName, testDevice.name)
        let manager2 = BridgeProcessManager(
            settings: settings2,
            processLauncher: MockProcessLauncher(),
            binaryURLOverride: URL(fileURLWithPath: "/tmp/apm44-bridge"),
            deviceSource: FakeBridgeDeviceSource(
                halCheck: HalBuildCheck(
                    halPresent: true,
                    appBuildID: fixtureBuildID,
                    driverBuildID: fixtureBuildID
                ),
                devices: []
            ),
            applicationTerminator: {}
        )
        await manager2.refreshDevices()
        XCTAssertEqual(manager2.deviceDisplayName, testDevice.name)
    }

    // (2) The remembered name belongs to its uid only: it is not shown for a
    // different uid.
    func testDeviceNameNotShownForDifferentUid() async {
        let (manager, settings, _, source) = await makeManager()
        XCTAssertEqual(settings.outputDeviceName, testDevice.name)

        source.devices = []
        await manager.refreshDevices()
        settings.outputDeviceUid = "different-output-uid"

        XCTAssertNil(settings.outputDeviceName)
        XCTAssertEqual(manager.deviceDisplayName, AppStrings.selectedOutput)
    }

    // (3) A fresh resume request with an unblocked launch restarts the bridge
    // and clears the flag.
    func testResumeAfterUpdateStartsWhenFreshAndUnblocked() async {
        let (manager, settings, launcher, _) = await makeManager()
        settings.resumeAfterUpdateRequestedAt = Date()

        manager.resumeAfterUpdateIfRequested(now: Date())

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 1)
        XCTAssertNil(settings.resumeAfterUpdateRequestedAt)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        XCTAssertEqual(manager.state, .idle)
    }

    // (4) A stale request never starts the bridge but is still cleared.
    func testResumeAfterUpdateIgnoresStaleFlag() async {
        let (manager, settings, launcher, _) = await makeManager()
        settings.resumeAfterUpdateRequestedAt = Date().addingTimeInterval(-11 * 60)

        manager.resumeAfterUpdateIfRequested(now: Date())

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, 0)
        XCTAssertNil(settings.resumeAfterUpdateRequestedAt)
    }

    // (5) No request never starts the bridge.
    func testResumeAfterUpdateIgnoresMissingFlag() async {
        let (manager, settings, launcher, _) = await makeManager()
        XCTAssertNil(settings.resumeAfterUpdateRequestedAt)

        manager.resumeAfterUpdateIfRequested(now: Date())

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, 0)
    }

    // A fresh request with the selected output not yet enumerated keeps the
    // flag (Core Audio may still be rescanning after the update); once the
    // device appears, resume starts the bridge and clears the flag.
    func testResumeAfterUpdateKeepsFlagWhileDeviceMissingThenStarts() async {
        let (manager, settings, launcher, source) = await makeManager()
        source.devices = []
        await manager.refreshDevices()
        XCTAssertNotNil(manager.startBlockedReason)
        settings.resumeAfterUpdateRequestedAt = Date()

        manager.resumeAfterUpdateIfRequested(now: Date())

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, 0)
        XCTAssertNotNil(settings.resumeAfterUpdateRequestedAt)

        source.devices = [testDevice]
        await manager.refreshDevices()
        manager.resumeAfterUpdateIfRequested(now: Date())

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 1)
        XCTAssertNil(settings.resumeAfterUpdateRequestedAt)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        XCTAssertEqual(manager.state, .idle)
    }

    // A fresh request blocked for another reason (driver build mismatch) is
    // cleared without starting.
    func testResumeAfterUpdateClearsWhenBlockedForOtherReason() async {
        let (manager, settings, launcher, source) = await makeManager()
        source.halCheck = HalBuildCheck(
            halPresent: true,
            appBuildID: fixtureBuildID,
            driverBuildID: "0.12.7+other-build-mismatch"
        )
        manager.refreshRoutingMode()
        XCTAssertEqual(manager.startBlockedReason, AppStrings.driverBuildMismatch)
        settings.resumeAfterUpdateRequestedAt = Date()

        manager.resumeAfterUpdateIfRequested(now: Date())

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, 0)
        XCTAssertNil(settings.resumeAfterUpdateRequestedAt)
    }

    // A pending flag with the bridge already running is cleared without a
    // second launch.
    func testResumeAfterUpdateClearsWhenAlreadyRunning() async {
        let (manager, settings, launcher, _) = await makeManager()
        manager.start()
        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 1)
        settings.resumeAfterUpdateRequestedAt = Date()

        manager.resumeAfterUpdateIfRequested(now: Date())

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 1)
        XCTAssertNil(settings.resumeAfterUpdateRequestedAt)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        XCTAssertEqual(manager.state, .idle)
    }

    // The hotplug path starts a pending resume once the device appears.
    func testResumeAfterUpdateStartsViaHotplugWhenDeviceAppears() async {
        let (manager, settings, launcher, source) = await makeManager()
        source.devices = []
        settings.resumeAfterUpdateRequestedAt = Date()

        await manager.handleHotplug()

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, 0)
        XCTAssertNotNil(settings.resumeAfterUpdateRequestedAt)

        source.devices = [testDevice]
        await manager.handleHotplug()

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 1)
        XCTAssertNil(settings.resumeAfterUpdateRequestedAt)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        XCTAssertEqual(manager.state, .idle)
    }

    // (6a) Posting the will-install-update notification while running records
    // the resume request. The literal name is used because the
    // SparkleUpdateController declaration lands with the other worker.
    func testWillInstallUpdateSetsResumeFlagWhileRunning() async {
        let (manager, settings, launcher, _) = await makeManager()
        manager.start()
        XCTAssertEqual(manager.state, .running)

        NotificationCenter.default.post(
            name: Notification.Name("apm44.willInstallUpdate"),
            object: nil
        )

        XCTAssertNotNil(settings.resumeAfterUpdateRequestedAt)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        XCTAssertEqual(manager.state, .idle)
    }

    func testUserStopRevokesPendingUpdateResume() async {
        let (manager, settings, launcher, _) = await makeManager()
        manager.start()
        NotificationCenter.default.post(name: .apm44WillInstallUpdate, object: nil)
        XCTAssertNotNil(settings.resumeAfterUpdateRequestedAt)

        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        XCTAssertNil(settings.resumeAfterUpdateRequestedAt)

        await manager.handleHotplug()
        manager.resumeAfterUpdateIfRequested(now: Date())

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, 1)
    }

    func testAbandonedUpdateInstallRevokesResume() async {
        let (manager, settings, launcher, _) = await makeManager()
        manager.start()
        NotificationCenter.default.post(name: .apm44WillInstallUpdate, object: nil)
        NotificationCenter.default.post(name: .apm44UpdateInstallAbandoned, object: nil)

        XCTAssertNil(settings.resumeAfterUpdateRequestedAt)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
    }

    // (6b) Posting while idle records nothing.
    func testWillInstallUpdateLeavesFlagClearWhileIdle() async {
        let (manager, settings, _, _) = await makeManager()
        XCTAssertEqual(manager.state, .idle)

        NotificationCenter.default.post(
            name: Notification.Name("apm44.willInstallUpdate"),
            object: nil
        )

        XCTAssertNil(settings.resumeAfterUpdateRequestedAt)
    }

    func testAutomationStartDecision() {
        XCTAssertTrue(BridgeProcessManager.shouldAutomationStart(state: .idle, blockedReason: nil))
        XCTAssertFalse(BridgeProcessManager.shouldAutomationStart(state: .idle, blockedReason: "missing"))
        XCTAssertFalse(BridgeProcessManager.shouldAutomationStart(state: .running, blockedReason: nil))
        XCTAssertFalse(BridgeProcessManager.shouldAutomationStart(state: .starting, blockedReason: nil))
        XCTAssertFalse(BridgeProcessManager.shouldAutomationStart(state: .stopping, blockedReason: nil))
        XCTAssertFalse(BridgeProcessManager.shouldAutomationStart(state: .reconnecting, blockedReason: nil))
        XCTAssertFalse(BridgeProcessManager.shouldAutomationStart(state: .error("x"), blockedReason: nil))
    }

    // PROC-01: concurrent escalations must both observe failure when the
    // helper survives SIGKILL. restart() only escalates from .running, so
    // it must win the race: a restart arriving after .stopping only queues
    // pending and never joins the escalation. restart() therefore enters
    // first and stopAsync() joins ~300ms later, during the restart's SIGKILL
    // wait, so the restart's final catch drains the stop's still-pending
    // first wait. Before the fix that drain resumed with true and the
    // sibling skipped its SIGKILL (forceKilled stayed 1); after the fix
    // both escalate and fail, the restart surfaces .error(bridgeDidNotStop)
    // with no relaunch.
    func testConcurrentStopsBothFailWhenHelperSurvivesSigkill() async {
        var t = BridgeTiming.live
        t.stopTimeout = 0.2
        let (manager, _, launcher, _) = await makeManager(timing: t)
        launcher.terminateOnForceKill = false
        manager.start()
        XCTAssertEqual(manager.state, .running)

        let clock = ContinuousClock()
        let start = clock.now
        let restartTask = Task { @MainActor in await manager.restart(reason: .settingsChange) }
        await waitUntil { manager.state == .stopping }
        // Start the sibling during the restart's SIGKILL wait so the
        // restart's final catch drains a still-pending first wait.
        try? await Task.sleep(nanoseconds: 300_000_000)
        let stopTask = Task { @MainActor in await manager.stopAsync() }
        await restartTask.value
        await stopTask.value
        let elapsed = clock.now - start

        XCTAssertTrue(elapsed < .seconds(2), "concurrent stops hung: elapsed \(elapsed)")
        XCTAssertEqual(manager.state, .error(AppStrings.bridgeDidNotStop))
        XCTAssertEqual(launcher.makeCount, 1)
        XCTAssertEqual(launcher.forceKilled.count, 2)
    }

    func testStartRefusedWhileStuckHelperStillRunning() async {
        var t = BridgeTiming.live
        t.stopTimeout = 0.05
        let (manager, _, launcher, _) = await makeManager(timing: t)
        launcher.terminateOnForceKill = false
        manager.start()
        XCTAssertEqual(manager.state, .running)

        await manager.restart(reason: .settingsChange)
        XCTAssertEqual(manager.state, .error(AppStrings.bridgeDidNotStop))
        XCTAssertEqual(launcher.makeCount, 1)

        manager.start()
        XCTAssertEqual(launcher.makeCount, 1)
        XCTAssertEqual(manager.state, .error(AppStrings.bridgeDidNotStop))

        // The mock Process never launched, so stub the exit status that
        // handleTermination reads outside .stopping.
        launcher.nextTerminationStatus = 9
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        manager.start()
        XCTAssertEqual(launcher.makeCount, 2)
        XCTAssertEqual(manager.state, .running)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        XCTAssertEqual(manager.state, .idle)
    }

    func testMenuStopWithStuckHelperShowsErrorAndLateExitGoesIdle() async {
        var t = BridgeTiming.live
        t.stopTimeout = 0.05
        let (manager, _, launcher, _) = await makeManager(timing: t)
        launcher.terminateOnForceKill = false
        manager.start()
        XCTAssertEqual(manager.state, .running)

        // Menu Stop path: fire-and-forget stop(), not stopAsync().
        manager.stop()
        await waitUntil { manager.state == .error(AppStrings.bridgeDidNotStop) }
        XCTAssertEqual(manager.state, .error(AppStrings.bridgeDidNotStop))

        launcher.nextTerminationStatus = 9
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        await waitUntil { manager.state == .idle }
        XCTAssertEqual(manager.state, .idle)
    }

    func testHotplugParkLateExitDoesNotStart() async {
        var t = BridgeTiming.live
        t.stopTimeout = 0.05
        let (manager, _, launcher, source) = await makeManager(timing: t)
        launcher.terminateOnForceKill = false
        manager.start()
        XCTAssertEqual(manager.state, .running)

        // Hotplug loss parks with the stuck helper still tracked.
        source.devices = []
        await manager.handleHotplug()
        guard case .reconnecting = manager.state else {
            XCTFail("Expected reconnecting park, got \(manager.state)")
            return
        }
        XCTAssertEqual(manager.lastStopReason, .hotplug)
        XCTAssertEqual(launcher.makeCount, 1)

        launcher.nextTerminationStatus = 9
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        // Let any resume attempt run; the park must survive it.
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(manager.state, .reconnecting)
        XCTAssertEqual(launcher.makeCount, 1)
        manager.stop()
        XCTAssertEqual(manager.state, .idle)
    }
}
