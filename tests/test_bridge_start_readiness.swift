import XCTest
@testable import APM44Bridge

final class BridgeStartReadinessTests: XCTestCase {
    private let compatible = AudioDeviceRow(
        uid: "ok",
        name: "AirPods Max",
        nominalRate: 48_000,
        hasInput: false,
        hasOutput: true
    )

    func testMissingBinaryBlocksStart() {
        XCTAssertEqual(
            BridgeStartReadiness.blockedReason(
                binaryMissing: true,
                selectedUid: compatible.uid,
                devices: [compatible],
                lastKnownName: compatible.name
            ),
            AppStrings.bridgeNotFound
        )
    }

    func testMissingSelectionExplainsStart() {
        XCTAssertEqual(
            BridgeStartReadiness.blockedReason(
                binaryMissing: false,
                selectedUid: nil,
                devices: [compatible],
                lastKnownName: AppStrings.outputNotSelected
            ),
            AppStrings.chooseOutputToStart
        )
    }

    func testStaleSelectionKeepsNamedUnavailableReason() {
        XCTAssertEqual(
            BridgeStartReadiness.blockedReason(
                binaryMissing: false,
                selectedUid: "gone",
                devices: [compatible],
                lastKnownName: "Studio Speakers"
            ),
            AppStrings.previousOutputUnavailable(name: "Studio Speakers")
        )
    }

    func testIncompatibleSelectionUsesLocalizedIssue() {
        let mono = AudioDeviceRow(
            uid: "mono",
            name: "Mono Output",
            nominalRate: 48_000,
            hasInput: false,
            hasOutput: true,
            outputChannels: 1
        )
        XCTAssertEqual(
            BridgeStartReadiness.blockedReason(
                binaryMissing: false,
                selectedUid: mono.uid,
                devices: [mono],
                lastKnownName: mono.name
            ),
            AppStrings.selectedOutputIncompatible(
                issue: AppStrings.compatibility("Stereo output unavailable")
            )
        )
    }

    func testCompatibleSelectionAllowsStart() {
        XCTAssertNil(
            BridgeStartReadiness.blockedReason(
                binaryMissing: false,
                selectedUid: compatible.uid,
                devices: [compatible],
                lastKnownName: compatible.name
            )
        )
    }
}

final class AppControlLabelTests: XCTestCase {
    func testPrimaryActionsHaveUniqueNames() {
        let names = [
            AppStrings.startBridge,
            AppStrings.stopBridge,
            AppStrings.restart,
            AppStrings.quitApp,
            AppStrings.cubaseSetupGuide,
            AppStrings.setup,
            AppStrings.helpMenuSetup,
        ]
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertFalse(AppStrings.startBridge.isEmpty)
        XCTAssertFalse(AppStrings.quitApp.isEmpty)
    }

    func testSkipAndDoneAreDistinct() {
        XCTAssertNotEqual(AppStrings.skipSetup, AppStrings.done)
        XCTAssertNotEqual(AppStrings.skipSetup.lowercased(), "continue")
        XCTAssertNotEqual(AppStrings.done.lowercased(), "continue")
    }
}

final class HalBuildIDTests: XCTestCase {
    private let appID = "0.12.7+3fc0b148b674"
    private let driverID = "0.12.7+c2728cba0591"

    func testFullBuildIDsWithSameVersionDoNotMatch() {
        XCTAssertFalse(HalDriverDetector.buildIDsMatch(appBuildID: appID, driverBuildID: driverID))
    }

    func testIdenticalFullBuildIDsMatch() {
        XCTAssertTrue(HalDriverDetector.buildIDsMatch(appBuildID: appID, driverBuildID: appID))
    }

    func testMissingOrMalformedIDsFailClosed() {
        for bad in [nil, "", "   ", "unknown", "$(APM44_BUILD_ID)", "${APM44_BUILD_ID}"] {
            XCTAssertFalse(
                HalDriverDetector.buildIDsMatch(appBuildID: bad, driverBuildID: driverID),
                "app ID \(String(describing: bad)) must not match"
            )
            XCTAssertFalse(
                HalDriverDetector.buildIDsMatch(appBuildID: appID, driverBuildID: bad),
                "driver ID \(String(describing: bad)) must not match"
            )
        }
        XCTAssertFalse(HalDriverDetector.buildIDsMatch(appBuildID: nil, driverBuildID: nil))
    }

    func testWhitespaceIsTrimmedBeforeCompare() {
        XCTAssertTrue(HalDriverDetector.buildIDsMatch(
            appBuildID: "  \(appID)\n",
            driverBuildID: appID
        ))
    }

    func testMismatchStatusIsNotReady() {
        XCTAssertEqual(
            HalDriverDetector.status(
                halPresent: true,
                appBuildID: appID,
                driverBuildID: driverID,
                driverBundleOnDisk: true
            ),
            .buildMismatch
        )
    }

    func testMatchingStatusIsReady() {
        XCTAssertEqual(
            HalDriverDetector.status(
                halPresent: true,
                appBuildID: appID,
                driverBuildID: appID,
                driverBundleOnDisk: true
            ),
            .ready
        )
    }

    func testMissingDriverIDWithHalEnumeratedIsMismatch() {
        XCTAssertEqual(
            HalDriverDetector.status(
                halPresent: true,
                appBuildID: appID,
                driverBuildID: nil,
                driverBundleOnDisk: true
            ),
            .buildMismatch
        )
    }

    func testFallbackWithoutHalNeverReportsMismatch() {
        XCTAssertEqual(
            HalDriverDetector.status(
                halPresent: false,
                appBuildID: nil,
                driverBuildID: nil,
                driverBundleOnDisk: false
            ),
            .notInstalled
        )
        XCTAssertEqual(
            HalDriverDetector.status(
                halPresent: false,
                appBuildID: appID,
                driverBuildID: driverID,
                driverBundleOnDisk: false
            ),
            .notInstalled
        )
    }

    func testDriverBuildIDReadsPlistFixture() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("APM44DriverFixture-\(UUID().uuidString).plist")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let dict: NSDictionary = ["APM44BuildID": driverID]
        XCTAssertTrue(dict.write(to: url, atomically: true))
        XCTAssertEqual(HalDriverDetector.driverBuildID(plistURL: url), driverID)
        XCTAssertFalse(HalDriverDetector.buildIDsMatch(
            appBuildID: appID,
            driverBuildID: HalDriverDetector.driverBuildID(plistURL: url)
        ))
    }

    func testDriverBuildIDMissingKeyReturnsNil() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("APM44DriverEmpty-\(UUID().uuidString).plist")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let dict: NSDictionary = ["CFBundleName": "APM44Bridge"]
        XCTAssertTrue(dict.write(to: url, atomically: true))
        XCTAssertNil(HalDriverDetector.driverBuildID(plistURL: url))
    }
}

final class BridgeStartReadinessBuildMismatchTests: XCTestCase {
    private let appID = "0.12.7+3fc0b148b674"
    private let driverID = "0.12.7+c2728cba0591"
    private let compatible = AudioDeviceRow(
        uid: "ok",
        name: "AirPods Max",
        nominalRate: 48_000,
        hasInput: false,
        hasOutput: true
    )

    func testMismatchBlocksCompatibleOutput() {
        XCTAssertEqual(
            BridgeStartReadiness.blockedReason(
                binaryMissing: false,
                selectedUid: compatible.uid,
                devices: [compatible],
                lastKnownName: compatible.name,
                halDevicePresent: true,
                appBuildID: appID,
                driverBuildID: driverID
            ),
            AppStrings.driverBuildMismatch
        )
    }

    func testMatchingIDsAllowCompatibleOutputToStart() {
        XCTAssertNil(
            BridgeStartReadiness.blockedReason(
                binaryMissing: false,
                selectedUid: compatible.uid,
                devices: [compatible],
                lastKnownName: compatible.name,
                halDevicePresent: true,
                appBuildID: appID,
                driverBuildID: appID
            )
        )
    }

    func testFallbackWithoutHalDoesNotBlockOnMissingDriver() {
        XCTAssertNil(
            BridgeStartReadiness.blockedReason(
                binaryMissing: false,
                selectedUid: compatible.uid,
                devices: [compatible],
                lastKnownName: compatible.name,
                halDevicePresent: false,
                appBuildID: appID,
                driverBuildID: nil
            )
        )
    }

    func testMissingDriverIDWithHalEnumeratedBlocks() {
        XCTAssertEqual(
            BridgeStartReadiness.blockedReason(
                binaryMissing: false,
                selectedUid: compatible.uid,
                devices: [compatible],
                lastKnownName: compatible.name,
                halDevicePresent: true,
                appBuildID: appID,
                driverBuildID: nil
            ),
            AppStrings.driverBuildMismatch
        )
    }

    func testNoOutputSelectedKeepsOutputWarningDespiteMismatch() {
        XCTAssertEqual(
            BridgeStartReadiness.blockedReason(
                binaryMissing: false,
                selectedUid: nil,
                devices: [compatible],
                lastKnownName: AppStrings.outputNotSelected,
                halDevicePresent: true,
                appBuildID: appID,
                driverBuildID: driverID
            ),
            AppStrings.chooseOutputToStart
        )
    }
}

@MainActor
final class BridgeProcessManagerBuildMismatchTests: XCTestCase {
    private let appID = "0.12.7+3fc0b148b674"
    private let driverID = "0.12.7+c2728cba0591"
    private let testDevice = AudioDeviceRow(
        uid: "test-output-uid",
        name: "Test Output",
        nominalRate: 48_000,
        hasInput: false,
        hasOutput: true
    )

    private func makeManager(launcher: MockProcessLauncher) -> (BridgeProcessManager, BridgeSettings) {
        let suite = "com.niko.apm44.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = BridgeSettings(defaults: defaults)
        settings.outputDeviceUid = testDevice.uid
        let manager = BridgeProcessManager(
            settings: settings,
            processLauncher: launcher,
            binaryURLOverride: URL(fileURLWithPath: "/tmp/apm44-bridge"),
            applicationTerminator: {}
        )
        manager.setDevicesForTesting([testDevice])
        manager.testDeviceListOverride = [testDevice]
        return (manager, settings)
    }

    func testStartBlockedOnMismatchLaunchesNothing() {
        let launcher = MockProcessLauncher()
        let (manager, _) = makeManager(launcher: launcher)
        manager.halBuildCheckOverride = (halPresent: true, appID: appID, driverID: driverID)
        manager.start()
        XCTAssertEqual(launcher.makeCount, 0)
        if case .error(let message) = manager.state {
            XCTAssertTrue(message.contains(driverID) || message.contains(appID),
                          "diagnostic should carry build IDs: \(message)")
            XCTAssertEqual(
                BridgeErrorPresentation.headline(for: message),
                AppStrings.driverBuildMismatch
            )
        } else {
            XCTFail("expected .error on build mismatch, got \(manager.state)")
        }
    }

    func testStartBlockedOnMissingDriverID() {
        let launcher = MockProcessLauncher()
        let (manager, _) = makeManager(launcher: launcher)
        manager.halBuildCheckOverride = (halPresent: true, appID: appID, driverID: nil)
        manager.start()
        XCTAssertEqual(launcher.makeCount, 0)
        if case .error = manager.state { } else {
            XCTFail("expected .error when driver ID is missing with HAL present")
        }
    }

    func testStartAllowedWhenIDsMatch() {
        let launcher = MockProcessLauncher()
        let (manager, _) = makeManager(launcher: launcher)
        manager.halBuildCheckOverride = (halPresent: true, appID: appID, driverID: appID)
        manager.start()
        XCTAssertEqual(launcher.makeCount, 1)
        XCTAssertEqual(manager.state, .running)
    }

    func testStartAllowedInBlackHoleFallbackWithoutDriver() {
        let launcher = MockProcessLauncher()
        let (manager, _) = makeManager(launcher: launcher)
        manager.halBuildCheckOverride = (halPresent: false, appID: appID, driverID: nil)
        manager.start()
        XCTAssertEqual(launcher.makeCount, 1)
        XCTAssertEqual(manager.state, .running)
    }
}
