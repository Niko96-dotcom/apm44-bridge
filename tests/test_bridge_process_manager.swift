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
        manager.halBuildCheckOverride = (halPresent: true, appID: fixtureBuildID, driverID: fixtureBuildID)
        manager.setDevicesForTesting([testDevice])
        manager.testDeviceListOverride = [testDevice]
        return (manager, settings, mockLauncher)
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
        manager.halBuildCheckOverride = (halPresent: true, appID: fixtureBuildID, driverID: fixtureBuildID)
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
        manager.halBuildCheckOverride = (halPresent: true, appID: fixtureBuildID, driverID: fixtureBuildID)
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
            XCTAssertEqual(
                manager.bannerMessage,
                AppStrings.reconnectingAttempt(current: manager.retryAttemptForTesting, max: 4)
            )
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

        XCTAssertEqual(manager.state, .error(AppStrings.selectedOutputGone))
        XCTAssertNil(manager.bannerMessage)
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
        XCTAssertEqual(manager.bannerMessage, AppStrings.waitingForOutput(manager.deviceDisplayName))
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
        XCTAssertEqual(manager.bannerMessage, AppStrings.previousOutputSelect)
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
            XCTAssertEqual(
                manager.bannerMessage,
                AppStrings.reconnectingAttempt(current: manager.retryAttemptForTesting, max: 4)
            )
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
            assertStoppedAfterUnstableLaunches(message, lastExit: 1)
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
            assertStoppedAfterUnstableLaunches(message, lastExit: 1)
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
            assertStoppedAfterUnstableLaunches(message, lastExit: 17)
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
        XCTAssertEqual(
            manager.bannerMessage,
            AppStrings.reconnectingAttempt(current: 1, max: 4)
        )

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
            XCTAssertEqual(
                manager.bannerMessage,
                AppStrings.reconnectingAttempt(current: manager.retryAttemptForTesting, max: 4)
            )
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
        XCTAssertEqual(message, AppStrings.ipcFailed())
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

    // Stale-route repair: start() must derive launch args and connection
    // phase from the same live halPresent used for the build gate, not
    // from a stale cached routingMode. Uses halBuildCheckOverride so no
    // real audio or HAL enumeration runs.
    func testStartWithStaleFallbackCacheUsesLiveHalRoute() async {
        let (manager, _, launcher) = makeManager()
        manager.setRoutingModeForTesting(.blackHoleFallback)
        manager.halBuildCheckOverride = (halPresent: true, appID: fixtureBuildID, driverID: fixtureBuildID)

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
        let (manager, _, launcher) = makeManager()
        manager.setRoutingModeForTesting(.halVirtualDevice)
        manager.halBuildCheckOverride = (halPresent: false, appID: fixtureBuildID, driverID: nil)

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

    func testStaleHalCacheWithMismatchStillBlocksWithoutFallbackLaunch() {
        let (manager, _, launcher) = makeManager()
        manager.setRoutingModeForTesting(.halVirtualDevice)
        manager.halBuildCheckOverride = (
            halPresent: true,
            appID: fixtureBuildID,
            driverID: "0.12.7+other-build-mismatch"
        )

        manager.start()

        XCTAssertEqual(launcher.makeCount, 0)
        if case .error = manager.state {
        } else {
            XCTFail("expected .error on build mismatch, got \(manager.state)")
        }
    }

    func testLoadedDriverBuildMismatchWhileRunningShowsErrorWithoutRetry() async {
        let (manager, _, launcher) = makeManager()
        manager.testRetryDelays = [60]

        manager.start()
        XCTAssertEqual(manager.state, .running)

        let generationBefore = manager.retryGeneration
        XCTAssertEqual(BridgeProcessManager.loadedDriverBuildMismatchExitStatus, 44)
        manager.testTerminationStatus = BridgeProcessManager.loadedDriverBuildMismatchExitStatus
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        XCTAssertEqual(manager.state, .error(AppStrings.loadedDriverBuildMismatch))
        if case .reconnecting = manager.state {
            XCTFail("Exit 44 must not auto-retry, got reconnecting")
        }
        XCTAssertEqual(manager.retryAttemptForTesting, 0)
        XCTAssertEqual(manager.bannerMessage, AppStrings.loadedDriverBuildMismatch)
        XCTAssertEqual(manager.retryGeneration, generationBefore)
        XCTAssertEqual(launcher.makeCount, 1)
    }

    func testLoadedDriverBuildMismatchWhileStartingShowsErrorWithoutRetry() async {
        let (manager, _, launcher) = makeManager()
        manager.testRetryDelays = [60]

        manager.start()
        XCTAssertEqual(manager.state, .running)
        manager.setStateForTesting(.starting)

        let generationBefore = manager.retryGeneration
        manager.testTerminationStatus = 44
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        XCTAssertEqual(manager.state, .error(AppStrings.loadedDriverBuildMismatch))
        if case .reconnecting = manager.state {
            XCTFail("Exit 44 in .starting must not auto-retry, got reconnecting")
        }
        XCTAssertEqual(manager.retryAttemptForTesting, 0)
        XCTAssertEqual(manager.bannerMessage, AppStrings.loadedDriverBuildMismatch)
        XCTAssertEqual(manager.retryGeneration, generationBefore)
        XCTAssertEqual(launcher.makeCount, 1)
    }

    func testLoadedDriverBuildMismatchResetsExistingRetryBudget() async {
        let (manager, _, launcher) = makeManager()
        manager.testRetryDelays = [60]

        manager.start()
        XCTAssertEqual(manager.state, .running)
        manager.setRetryAttemptForTesting(2)

        manager.testTerminationStatus = 44
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        XCTAssertEqual(manager.state, .error(AppStrings.loadedDriverBuildMismatch))
        XCTAssertEqual(manager.retryAttemptForTesting, 0)
        XCTAssertEqual(manager.bannerMessage, AppStrings.loadedDriverBuildMismatch)
        XCTAssertEqual(launcher.makeCount, 1)
    }

    func testExitOneWhileRunningStillAutoRetries() async {
        let (manager, _, launcher) = makeManager()
        manager.testRetryDelays = [60]

        manager.start()
        XCTAssertEqual(manager.state, .running)

        manager.testTerminationStatus = 1
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        if case .reconnecting = manager.state {
            XCTAssertEqual(
                manager.bannerMessage,
                AppStrings.reconnectingAttempt(current: manager.retryAttemptForTesting, max: 4)
            )
        } else {
            XCTFail("Expected reconnecting after exit 1, got \(manager.state)")
        }
        XCTAssertEqual(launcher.makeCount, 1)
    }

    func testSettingsRestartWhileIdleLeavesApplyingFalse() async {
        let (manager, _, launcher) = makeManager()

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
        let (manager, _, _) = makeManager(launcher: launcher)

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
        let (manager, settings, _) = makeManager(launcher: launcher)

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

    func testStartBlockedReasonUsesCachedValues() {
        let (manager, _, _) = makeManager()

        manager.start()
        XCTAssertEqual(manager.state, .running)
        XCTAssertNil(manager.startBlockedReason)

        manager.halBuildCheckOverride = (
            halPresent: true,
            appID: fixtureBuildID,
            driverID: "0.12.7+other-build-mismatch"
        )
        XCTAssertEqual(manager.startBlockedReason, AppStrings.driverBuildMismatch)

        manager.halBuildCheckOverride = (
            halPresent: true,
            appID: fixtureBuildID,
            driverID: fixtureBuildID
        )
        XCTAssertNil(manager.startBlockedReason)
    }

    // (1) The remembered output name survives a relaunch: a new manager built
    // on the same UserDefaults suite shows it while the device list is empty.
    func testDeviceNamePersistsAcrossManagersForSameSuite() {
        let suite = "com.niko.apm44.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }

        let settings1 = BridgeSettings(defaults: defaults)
        settings1.outputDeviceUid = testDevice.uid
        let manager1 = BridgeProcessManager(
            settings: settings1,
            processLauncher: MockProcessLauncher(),
            binaryURLOverride: URL(fileURLWithPath: "/tmp/apm44-bridge"),
            applicationTerminator: {}
        )
        manager1.applyRefreshedDeviceListForTesting([testDevice])
        XCTAssertEqual(settings1.outputDeviceName, testDevice.name)

        let settings2 = BridgeSettings(defaults: defaults)
        XCTAssertEqual(settings2.outputDeviceName, testDevice.name)
        let manager2 = BridgeProcessManager(
            settings: settings2,
            processLauncher: MockProcessLauncher(),
            binaryURLOverride: URL(fileURLWithPath: "/tmp/apm44-bridge"),
            applicationTerminator: {}
        )
        manager2.setDevicesForTesting([])
        XCTAssertEqual(manager2.deviceDisplayName, testDevice.name)
    }

    // (2) The remembered name belongs to its uid only: it is not shown for a
    // different uid.
    func testDeviceNameNotShownForDifferentUid() {
        let (manager, settings, _) = makeManager()
        manager.applyRefreshedDeviceListForTesting([testDevice])
        XCTAssertEqual(settings.outputDeviceName, testDevice.name)

        manager.setDevicesForTesting([])
        settings.outputDeviceUid = "different-output-uid"

        XCTAssertNil(settings.outputDeviceName)
        XCTAssertEqual(manager.deviceDisplayName, AppStrings.selectedOutput)
    }

    // (3) A fresh resume request with an unblocked launch restarts the bridge
    // and clears the flag.
    func testResumeAfterUpdateStartsWhenFreshAndUnblocked() async {
        let (manager, settings, launcher) = makeManager()
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
    func testResumeAfterUpdateIgnoresStaleFlag() {
        let (manager, settings, launcher) = makeManager()
        settings.resumeAfterUpdateRequestedAt = Date().addingTimeInterval(-11 * 60)

        manager.resumeAfterUpdateIfRequested(now: Date())

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, 0)
        XCTAssertNil(settings.resumeAfterUpdateRequestedAt)
    }

    // (5) No request never starts the bridge.
    func testResumeAfterUpdateIgnoresMissingFlag() {
        let (manager, settings, launcher) = makeManager()
        XCTAssertNil(settings.resumeAfterUpdateRequestedAt)

        manager.resumeAfterUpdateIfRequested(now: Date())

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, 0)
    }

    // A fresh request with a blocked launch (selected output absent) never
    // starts the bridge but is still cleared.
    func testResumeAfterUpdateDoesNotStartWhenBlocked() {
        let (manager, settings, launcher) = makeManager()
        manager.setDevicesForTesting([])
        manager.testDeviceListOverride = []
        XCTAssertNotNil(manager.startBlockedReason)
        settings.resumeAfterUpdateRequestedAt = Date()

        manager.resumeAfterUpdateIfRequested(now: Date())

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(launcher.makeCount, 0)
        XCTAssertNil(settings.resumeAfterUpdateRequestedAt)
    }

    // (6a) Posting the will-install-update notification while running records
    // the resume request. The literal name is used because the
    // SparkleUpdateController declaration lands with the other worker.
    func testWillInstallUpdateSetsResumeFlagWhileRunning() async {
        let (manager, settings, launcher) = makeManager()
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

    // (6b) Posting while idle records nothing.
    func testWillInstallUpdateLeavesFlagClearWhileIdle() {
        let (manager, settings, _) = makeManager()
        XCTAssertEqual(manager.state, .idle)

        NotificationCenter.default.post(
            name: Notification.Name("apm44.willInstallUpdate"),
            object: nil
        )

        XCTAssertNil(settings.resumeAfterUpdateRequestedAt)
    }
}
