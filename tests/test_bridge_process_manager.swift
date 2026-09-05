import XCTest
@testable import APM44Bridge

final class MockProcessLauncher: ProcessLaunching {
    private(set) var makeCount = 0
    private(set) var lastProcess: Process?
    var terminationDelayNanoseconds: UInt64 = 0
    var shouldFailLaunch = false
    var failLaunchesAfterFirstSuccess = false
    private var successfulLaunches = 0
    private var running = Set<ObjectIdentifier>()

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

    func fireTermination(for proc: Process) async {
        if terminationDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: terminationDelayNanoseconds)
        }
        running.remove(ObjectIdentifier(proc))
        proc.terminationHandler?(proc)
    }
}

@MainActor
final class BridgeProcessManagerTests: XCTestCase {
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

    private func makeSettings() -> BridgeSettings {
        let suite = "com.niko.apm44.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return BridgeSettings(defaults: defaults)
    }

    private func makeManager(
        launcher: MockProcessLauncher? = nil,
        applicationTerminator: @escaping @MainActor () -> Void = {}
    ) -> (BridgeProcessManager, BridgeSettings, MockProcessLauncher) {
        let mockLauncher = launcher ?? MockProcessLauncher()
        let settings = makeSettings()
        settings.outputDeviceUid = testDevice.uid
        let manager = BridgeProcessManager(
            settings: settings,
            processLauncher: mockLauncher,
            binaryURLOverride: URL(fileURLWithPath: "/tmp/apm44-bridge"),
            applicationTerminator: applicationTerminator
        )
        manager.setDevicesForTesting([testDevice])
        manager.testDeviceListOverride = [testDevice]
        return (manager, settings, mockLauncher)
    }

    private func sampleMetrics() -> BridgeMetricsSnapshot {
        BridgeMetricsSnapshot(
            fillMs: 15,
            ratio: 1.0,
            ppm: 0,
            underruns: 0,
            overruns: 0,
            xruns: 0,
            estimatedRtMs: 15,
            targetFillMs: 15,
            srcQuality: "medium"
        )
    }

    func testStartFromErrorState() async {
        let launcher = MockProcessLauncher()
        let settings = makeSettings()
        settings.outputDeviceUid = testDevice.uid
        let manager = BridgeProcessManager(
            settings: settings,
            processLauncher: launcher,
            binaryURLOverride: URL(fileURLWithPath: "/usr/bin/sleep")
        )
        manager.setDevicesForTesting([testDevice])
        manager.setStateForTesting(.error("previous failure"))

        manager.start()

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 1)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        XCTAssertEqual(manager.state, .idle)
    }

    func testProductionLaunchUsesParentDeathPipe() async throws {
        let launcher = MockProcessLauncher()
        let settings = makeSettings()
        settings.outputDeviceUid = testDevice.uid
        let manager = BridgeProcessManager(
            settings: settings,
            processLauncher: launcher,
            binaryURLOverride: URL(fileURLWithPath: "/tmp/apm44-bridge")
        )
        manager.setDevicesForTesting([testDevice])

        manager.start()

        let process = try XCTUnwrap(launcher.lastProcess)
        XCTAssertTrue(process.arguments?.contains("--parent-watch-stdin") == true)
        XCTAssertTrue(process.standardInput is Pipe)

        manager.stop()
        await launcher.fireTermination(for: process)
    }

    func testIdleToRunning() async {
        let (manager, _, launcher) = makeManager()

        manager.start()

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 1)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        XCTAssertEqual(manager.state, .idle)
    }

    func testStartResetsMetricsStateAndTimestamp() {
        let (manager, _, _) = makeManager()
        manager.applyMetricsForTesting(sampleMetrics())
        manager.markMetricsStaleForTesting()
        XCTAssertNotNil(manager.latestMetrics)
        XCTAssertTrue(manager.hasLastMetricsTimestampForTesting)
        XCTAssertTrue(manager.metricsStale)

        manager.start()

        XCTAssertNil(manager.latestMetrics)
        XCTAssertFalse(manager.hasLastMetricsTimestampForTesting)
        XCTAssertFalse(manager.metricsStale)
    }

    func testRunningToIdleViaUserStop() async {
        let (manager, _, launcher) = makeManager()

        manager.start()
        XCTAssertEqual(manager.state, .running)

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
        let (manager, _, launcher) = makeManager()

        manager.start()
        manager.applyMetricsForTesting(sampleMetrics())
        manager.markMetricsStaleForTesting()
        XCTAssertNotNil(manager.latestMetrics)
        XCTAssertTrue(manager.hasLastMetricsTimestampForTesting)
        XCTAssertTrue(manager.metricsStale)

        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(manager.latestMetrics)
        XCTAssertFalse(manager.hasLastMetricsTimestampForTesting)
        XCTAssertFalse(manager.metricsStale)
    }

    func testCleanRunningTerminationUsesIdleTransition() async {
        let (manager, _, launcher) = makeManager()

        manager.start()
        manager.applyMetricsForTesting(sampleMetrics())
        manager.markMetricsStaleForTesting()
        XCTAssertEqual(manager.state, .running)
        XCTAssertNotNil(manager.latestMetrics)
        XCTAssertTrue(manager.hasLastMetricsTimestampForTesting)

        manager.testTerminationStatus = 0
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(manager.latestMetrics)
        XCTAssertFalse(manager.hasLastMetricsTimestampForTesting)
        XCTAssertFalse(manager.metricsStale)
        XCTAssertNil(manager.lastStopReason)
    }

    func testRunningUnexpectedExit() async {
        let (manager, _, launcher) = makeManager()
        manager.testRetryDelays = [60]

        manager.start()
        XCTAssertEqual(manager.state, .running)

        let generationBefore = manager.retryGeneration
        manager.testTerminationStatus = 1
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        if case .reconnecting = manager.state {
            XCTAssertGreaterThan(manager.retryGeneration, generationBefore)
            XCTAssertTrue(manager.bannerMessage?.localizedCaseInsensitiveContains("attempt") == true)
        } else {
            XCTFail("Expected reconnecting state after unexpected exit, got \(manager.state)")
        }
    }

    func testRestartFromErrorActuallyRelaunches() async {
        let (manager, _, launcher) = makeManager()
        manager.setStateForTesting(.error("lost connection"))

        await manager.restart(reason: .user)

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 1)
    }

    func testSleepStopsAndWakeResumesRunningBridge() async {
        let (manager, _, launcher) = makeManager()
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

    func testWakeDoesNotAutostartBridgeThatWasIdleBeforeSleep() async {
        let (manager, _, launcher) = makeManager()

        await manager.handleSystemWillSleep()
        await manager.handleSystemDidWake()

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, 0)
    }

    func testUserStopNoAutoRetry() async {
        let (manager, _, launcher) = makeManager()
        manager.testRetryDelays = [0.01]

        manager.start()
        let generationBefore = manager.retryGeneration
        manager.stop()

        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(manager.retryGeneration, generationBefore)
    }

    func testQuitApplicationStopsRunningBridgeBeforeTerminating() async {
        var didTerminate = false
        let (manager, _, launcher) = makeManager {
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
        let (manager, _, launcher) = makeManager {
            didTerminate = true
        }
        manager.testRetryDelays = [60]

        manager.start()
        manager.testTerminationStatus = 1
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
        let (manager, _, _) = makeManager()
        manager.setDevicesForTesting([])
        let generationBefore = manager.hotplugRefreshGeneration

        await manager.handleHotplug()

        XCTAssertGreaterThan(manager.hotplugRefreshGeneration, generationBefore)
    }

    func testHotplugWhileIdleDoesNotStartBridge() async {
        let (manager, _, launcher) = makeManager()
        XCTAssertEqual(manager.state, .idle)

        await manager.handleHotplug()

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, 0)
    }

    func testSelectedAudioDeviceChangeRestartsRunningBridge() async {
        let (manager, _, launcher) = makeManager()

        manager.start()
        XCTAssertEqual(manager.state, .running)
        let makeCountBefore = launcher.makeCount
        manager.testDeviceListOverride = [
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

    func testUnrelatedAudioDeviceChangeDoesNotRestartRunningBridge() async {
        let (manager, _, launcher) = makeManager()
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
        manager.testDeviceListOverride = [testDevice, unrelatedDevice]

        await manager.handleHotplug()

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, makeCountBefore)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
    }

    func testStartRejectsSelectedUidMissingFromCurrentDeviceList() {
        let (manager, settings, launcher) = makeManager()
        settings.outputDeviceUid = "missing-output"

        manager.start()

        XCTAssertEqual(manager.state, .error("Selected output is no longer available"))
        XCTAssertEqual(launcher.makeCount, 0)
    }

    func testStartRejectsIncompatibleSelectedOutputBeforeLaunch() {
        let (manager, settings, launcher) = makeManager()
        let incompatible = AudioDeviceRow(
            uid: "mono-output",
            name: "Mono Output",
            nominalRate: 48_000,
            hasInput: false,
            hasOutput: true,
            outputChannels: 1
        )
        settings.outputDeviceUid = incompatible.uid
        manager.setDevicesForTesting([incompatible])

        manager.start()

        XCTAssertEqual(launcher.makeCount, 0)
        if case .error(let message) = manager.state {
            XCTAssertTrue(message.localizedCaseInsensitiveContains("stereo"))
        } else {
            XCTFail("Expected compatibility error, got \(manager.state)")
        }
    }

    func testDisconnectWhileRunningEntersReconnecting() async {
        let (manager, settings, launcher) = makeManager()

        manager.start()
        XCTAssertEqual(manager.state, .running)

        settings.outputDeviceUid = testDevice.uid
        manager.testDeviceListOverride = []

        await awaitHotplugCompletingTermination(manager: manager, launcher: launcher)

        if case .reconnecting = manager.state {
            // expected
        } else {
            XCTFail("Expected reconnecting after disconnect, got \(manager.state)")
        }
        XCTAssertEqual(launcher.makeCount, 1)
        XCTAssertTrue(manager.bannerMessage?.localizedCaseInsensitiveContains("waiting for") == true)
    }

    func testReconnectAfterDisconnectAutoStarts() async {
        let (manager, settings, launcher) = makeManager()

        manager.start()
        XCTAssertEqual(manager.state, .running)

        manager.testDeviceListOverride = []
        await awaitHotplugCompletingTermination(manager: manager, launcher: launcher)

        if case .reconnecting = manager.state {
            // expected
        } else {
            XCTFail("Expected reconnecting before auto-restart, got \(manager.state)")
        }

        manager.testDeviceListOverride = [testDevice]
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
        let (manager, settings, launcher) = makeManager()
        settings.outputDeviceUid = testDevice.uid
        manager.testDeviceListOverride = []

        await manager.handleHotplug()

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, 0)
    }

    func testUserStopClearsWasRunningFlag() async {
        let (manager, _, launcher) = makeManager()

        manager.start()
        manager.setStateForTesting(.reconnecting)

        manager.stop()

        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        XCTAssertEqual(manager.state, .idle)
    }

    func testInvalidSelectedDeviceCleared() {
        let (manager, settings, _) = makeManager()
        settings.outputDeviceUid = "BH-UID"
        let airpods = AudioDeviceRow(
            uid: "AP-UID",
            name: "AirPods Max",
            nominalRate: 48_000,
            hasInput: false,
            hasOutput: true
        )

        manager.applyRefreshedDeviceListForTesting([airpods])

        XCTAssertNil(settings.outputDeviceUid)
        XCTAssertEqual(manager.bannerMessage, "Previous output unavailable — select a device")
    }

    func testUnexpectedExitSchedulesRetry() async {
        let (manager, _, launcher) = makeManager()
        manager.testRetryDelays = [60]

        manager.start()
        manager.testTerminationStatus = 1
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        if case .reconnecting = manager.state {
            XCTAssertTrue(manager.bannerMessage?.localizedCaseInsensitiveContains("attempt") == true)
        } else {
            XCTFail("Expected reconnecting with retry banner, got \(manager.state)")
        }
    }

    func testReconnectingRetryCanBeInterruptedByStop() async {
        let (manager, _, launcher) = makeManager()
        manager.testRetryDelays = [60]

        manager.start()
        manager.testTerminationStatus = 1
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

    func testRetryExhaustionLandsInError() async {
        let launcher = MockProcessLauncher()
        launcher.failLaunchesAfterFirstSuccess = true
        let (manager, _, _) = makeManager(launcher: launcher)
        manager.testRetryDelays = [0]

        manager.start()
        XCTAssertEqual(manager.state, .running)
        manager.setRetryAttemptForTesting(4)

        manager.testTerminationStatus = 1
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        for _ in 0..<100 {
            if case .error = manager.state { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        if case .error(let message) = manager.state {
            XCTAssertTrue(message.localizedCaseInsensitiveContains("unstable launches"))
        } else {
            XCTFail("Expected final error after retries, got \(manager.state)")
        }
    }

    func testRetryExhaustionFromZeroAttempt() async {
        let launcher = MockProcessLauncher()
        launcher.failLaunchesAfterFirstSuccess = true
        let (manager, _, _) = makeManager(launcher: launcher)
        manager.testRetryDelays = [0]

        manager.start()
        XCTAssertEqual(manager.state, .running)

        manager.testTerminationStatus = 1
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        for _ in 0..<200 {
            if case .error = manager.state { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        if case .error(let message) = manager.state {
            XCTAssertTrue(message.localizedCaseInsensitiveContains("unstable launches"))
        } else {
            XCTFail("Expected final error after retries from zero, got \(manager.state)")
        }
    }

    func testCrashLoopExhaustsAfterFourShortLivedSuccessfulLaunches() async {
        let (manager, _, launcher) = makeManager()
        manager.testRetryDelays = [0]

        manager.start()
        XCTAssertEqual(launcher.makeCount, 1)

        for unhealthyLaunch in 1...4 {
            guard let proc = launcher.lastProcess else {
                XCTFail("Missing process for unhealthy launch \(unhealthyLaunch)")
                return
            }
            manager.testTerminationStatus = 17
            await launcher.fireTermination(for: proc)

            if unhealthyLaunch < 4 {
                for _ in 0..<100 where launcher.makeCount == unhealthyLaunch {
                    try? await Task.sleep(nanoseconds: 2_000_000)
                }
                XCTAssertEqual(launcher.makeCount, unhealthyLaunch + 1)
            }
        }

        if case .error(let message) = manager.state {
            XCTAssertTrue(message.contains("4 unstable launches"))
            XCTAssertTrue(message.contains("last exit 17"))
        } else {
            XCTFail("Expected bounded crash-loop error, got \(manager.state)")
        }
        XCTAssertEqual(launcher.makeCount, 4, "A fifth unhealthy launch must never occur")
        XCTAssertEqual(manager.retryAttemptForTesting, 4)
    }

    func testRetryBudgetResetsOnlyAfterMetricsAndStabilityWindow() async {
        let (manager, _, launcher) = makeManager()
        manager.testStabilityWindow = 0
        manager.testRetryDelays = [0]

        manager.start()
        manager.testTerminationStatus = 17
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
        for _ in 0..<100 where launcher.makeCount < 2 {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(launcher.makeCount, 2)
        XCTAssertEqual(manager.processHealthForTesting, .spawning)
        XCTAssertEqual(manager.retryAttemptForTesting, 1)
        XCTAssertTrue(manager.bannerMessage?.contains("Reconnecting") == true)

        manager.applyMetricsForTesting(sampleMetrics())
        for _ in 0..<100 where manager.processHealthForTesting != .stable {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }

        XCTAssertEqual(manager.processHealthForTesting, .stable)
        XCTAssertEqual(manager.retryAttemptForTesting, 0)
        XCTAssertNil(manager.bannerMessage, "Recovery must remove its reconnecting banner")

        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
    }

    func testStopAndStartDuringRecoveryClearsRetryBanner() async {
        let (manager, _, launcher) = makeManager()
        manager.testRetryDelays = [0]
        manager.start()
        manager.testTerminationStatus = 17
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
        let (manager, _, launcher) = makeManager()
        manager.testStabilityWindow = 0
        manager.setRetryAttemptForTesting(1)
        manager.start(resetRetryAttempt: false)
        manager.bannerMessage = "Could not enable launch at login"
        manager.applyMetricsForTesting(sampleMetrics())
        for _ in 0..<100 where manager.processHealthForTesting != .stable {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(manager.processHealthForTesting, .stable)
        XCTAssertEqual(manager.bannerMessage, "Could not enable launch at login")
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }
    }

    func testSettingsRestartWhileIdleDoesNotStart() async {
        let (manager, _, launcher) = makeManager()

        XCTAssertEqual(manager.state, .idle)

        await manager.restartForSettingsChange()

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, 0)
    }

    func testRecoverableStaleRingExitTriggersRetry() async {
        let (manager, _, launcher) = makeManager()
        manager.testRetryDelays = [60]

        manager.start()
        XCTAssertEqual(manager.state, .running)

        manager.appendStderrForTesting("stale shm ring: could not remap shared-memory ring")
        manager.testTerminationStatus = 42
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        if case .reconnecting = manager.state {
            XCTAssertTrue(manager.bannerMessage?.localizedCaseInsensitiveContains("attempt") == true)
        } else {
            XCTFail("Expected reconnecting after recoverable stale ring exit, got \(manager.state)")
        }
    }

    func testUserStopSuppressesStaleRingRetry() async {
        let (manager, _, launcher) = makeManager()
        manager.testRetryDelays = [0.01]

        manager.start()
        manager.stop()

        manager.appendStderrForTesting("stale shm ring: invalid header")
        manager.testTerminationStatus = 42
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(manager.state, .idle)
    }

    func testStaleRingFailureMessageIsActionable() {
        let (manager, _, _) = makeManager()
        manager.appendStderrForTesting("stale shm ring: invalid shm ring header")
        let message = manager.bridgeFailureMessageForTesting(defaultMessage: "Lost connection to bridge.")
        XCTAssertTrue(message.localizedCaseInsensitiveContains("reinstall"))
        XCTAssertTrue(message.localizedCaseInsensitiveContains("driver"))
    }

    func testSettingsRestartWaitsForTermination() async {
        let launcher = MockProcessLauncher()
        launcher.terminationDelayNanoseconds = 200_000_000
        let (manager, _, _) = makeManager(launcher: launcher)

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
    // overwrite the first waiter; the new list-based implementation
    // appends each caller and drains the full list on termination.
    func testConcurrentTerminationWaitersAllComplete() async {
        let (manager, _, launcher) = makeManager()

        manager.start()
        XCTAssertEqual(manager.state, .running)

        // Kick off two concurrent stop calls. Each invokes
        // `finishStopWithEscalation` → `waitForTermination` →
        // `terminationContinuations.append`. Both must unblock when
        // the daemon fires its termination handler.
        let stop1 = Task { @MainActor in
            manager.stop()
        }
        let stop2 = Task { @MainActor in
            manager.stop()
        }

        // Give both tasks a moment to enter waitForTermination and append
        // their continuations to the list.
        try? await Task.sleep(nanoseconds: 20_000_000)

        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        // Both awaiters must complete without hanging.
        await stop1.value
        await stop2.value

        XCTAssertEqual(manager.state, .idle)
    }
}
