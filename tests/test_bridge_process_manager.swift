import XCTest
@testable import APM44Bridge

final class MockProcessLauncher: ProcessLaunching {
    private(set) var makeCount = 0
    private(set) var lastProcess: Process?
    var terminationDelayNanoseconds: UInt64 = 0
    var shouldFailLaunch = false
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

        manager.start()
        XCTAssertEqual(manager.state, .running)

        manager.testTerminationStatus = 1
        if let proc = launcher.lastProcess {
            await launcher.fireTermination(for: proc)
        }

        if case .error = manager.state {
            // expected
        } else {
            XCTFail("Expected error state after unexpected exit, got \(manager.state)")
        }
        XCTAssertNil(manager.lastStopReason)
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
}
