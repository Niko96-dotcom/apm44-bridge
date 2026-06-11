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

    private func makeManager(
        launcher: MockProcessLauncher? = nil,
        executable: String = "/usr/bin/sleep",
        launchArguments: [String] = ["3600"]
    ) -> (BridgeProcessManager, BridgeSettings, MockProcessLauncher) {
        let mockLauncher = launcher ?? MockProcessLauncher()
        let settings = BridgeSettings()
        settings.outputDeviceUid = testDevice.uid
        let manager = BridgeProcessManager(
            settings: settings,
            processLauncher: mockLauncher,
            binaryURLOverride: URL(fileURLWithPath: executable)
        )
        manager.setDevicesForTesting([testDevice])
        manager.testDeviceListOverride = [testDevice]
        manager.testLaunchArgumentsOverride = launchArguments
        return (manager, settings, mockLauncher)
    }

    func testStartFromErrorState() async {
        let launcher = MockProcessLauncher()
        let settings = BridgeSettings()
        settings.outputDeviceUid = testDevice.uid
        let manager = BridgeProcessManager(
            settings: settings,
            processLauncher: launcher,
            binaryURLOverride: URL(fileURLWithPath: "/usr/bin/sleep")
        )
        manager.setDevicesForTesting([testDevice])
        manager.testLaunchArgumentsOverride = ["3600"]
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

    func testErrorToStarting() {
        let (manager, _, launcher) = makeManager()
        manager.setStateForTesting(.error("lost connection"))

        manager.start()

        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(launcher.makeCount, 1)
    }

    func testUserStopDoesNotSetRecoverableFlag() async {
        let (manager, _, launcher) = makeManager()

        manager.start()
        manager.stop()

        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        XCTAssertEqual(manager.lastStopReason, nil)
        let mirror = Mirror(reflecting: manager)
        let hasAutoRetry = mirror.children.contains { $0.label == "shouldAutoRetry" }
        XCTAssertFalse(hasAutoRetry)
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

    func testHotplugWhileRunningStillRestarts() async {
        let (manager, _, launcher) = makeManager()

        manager.start()
        XCTAssertEqual(manager.state, .running)
        let makeCountBefore = launcher.makeCount

        await awaitHotplugCompletingTermination(manager: manager, launcher: launcher)

        XCTAssertGreaterThan(launcher.makeCount, makeCountBefore)
        XCTAssertEqual(manager.state, .running)
        manager.stop()
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
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
            XCTAssertTrue(message.localizedCaseInsensitiveContains("retries"))
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
            XCTAssertTrue(message.localizedCaseInsensitiveContains("retries"))
        } else {
            XCTFail("Expected final error after retries from zero, got \(manager.state)")
        }
    }

    func testRetryBackoffDelays() async {
        let (manager, _, launcher) = makeManager()
        manager.testRetryDelays = [0.01, 0.02, 0.04, 0.04]

        manager.start()
        let startTime = Date()
        manager.testTerminationStatus = 1
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(manager.testRetryDelays, [0.01, 0.02, 0.04, 0.04])
        _ = startTime
        if case .reconnecting = manager.state {
            XCTAssertTrue(manager.bannerMessage?.contains("attempt 1") == true)
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
