import XCTest
@testable import APM44Bridge

final class BridgeStartReadinessTests: XCTestCase {
    private static let appID = "0.12.7+3fc0b148b674"
    private static let driverID = "0.12.7+c2728cba0591"
    private let compatible = AudioDeviceRow(
        uid: "ok",
        name: "AirPods Max",
        nominalRate: 48_000,
        hasInput: false,
        hasOutput: true
    )
    private let mono = AudioDeviceRow(
        uid: "mono",
        name: "Mono Output",
        nominalRate: 48_000,
        hasInput: false,
        hasOutput: true,
        outputChannels: 1
    )

    private struct GateCase {
        let name: String
        var binaryMissing = false
        var selectedUid: String? = "ok"
        var halPresent = false
        var appBuildID: String? = BridgeStartReadinessTests.appID
        var driverBuildID: String? = BridgeStartReadinessTests.appID
        let expected: BridgeError?
    }

    func testGateReturnsFirstBlockingCondition() {
        let cases = [
            GateCase(name: "missing binary wins over every other blocker",
                     binaryMissing: true, selectedUid: nil, halPresent: true,
                     driverBuildID: Self.driverID, expected: .bridgeNotFound),
            GateCase(name: "no output selected",
                     selectedUid: nil, expected: .selectOutputDevice),
            GateCase(name: "empty selection counts as none",
                     selectedUid: "", expected: .selectOutputDevice),
            GateCase(name: "no output selected wins over a build mismatch",
                     selectedUid: nil, halPresent: true, driverBuildID: Self.driverID,
                     expected: .selectOutputDevice),
            GateCase(name: "HAL present with mismatched build IDs",
                     halPresent: true, driverBuildID: Self.driverID,
                     expected: .driverBuildMismatch(appBuildID: Self.appID, driverBuildID: Self.driverID)),
            GateCase(name: "HAL present with a missing driver ID fails closed",
                     halPresent: true, driverBuildID: nil,
                     expected: .driverBuildMismatch(appBuildID: Self.appID, driverBuildID: nil)),
            GateCase(name: "malformed IDs are reported as missing",
                     halPresent: true, appBuildID: "unknown", driverBuildID: "$(APM44_BUILD_ID)",
                     expected: .driverBuildMismatch(appBuildID: nil, driverBuildID: nil)),
            GateCase(name: "build mismatch wins over a gone output",
                     selectedUid: "gone", halPresent: true, driverBuildID: Self.driverID,
                     expected: .driverBuildMismatch(appBuildID: Self.appID, driverBuildID: Self.driverID)),
            GateCase(name: "BlackHole fallback ignores a missing driver",
                     halPresent: false, driverBuildID: nil, expected: nil),
            GateCase(name: "selected output not in the device list",
                     selectedUid: "gone", expected: .selectedOutputGone),
            GateCase(name: "selected output incompatible",
                     selectedUid: "mono",
                     expected: .selectedOutputIncompatible(issue: .stereoOutputUnavailable)),
            GateCase(name: "HAL present with matching IDs and a compatible output",
                     halPresent: true, expected: nil),
            GateCase(name: "compatible output without HAL", expected: nil),
        ]
        for gate in cases {
            XCTAssertEqual(
                BridgeStartReadiness.blocker(
                    binaryMissing: gate.binaryMissing,
                    selectedUid: gate.selectedUid,
                    devices: [compatible, mono],
                    halDevicePresent: gate.halPresent,
                    appBuildID: gate.appBuildID,
                    driverBuildID: gate.driverBuildID
                ),
                gate.expected,
                gate.name
            )
        }
    }

    func testStartBlockedTextForEachGateResult() {
        let cases: [(BridgeError, String)] = [
            (.bridgeNotFound, AppStrings.bridgeNotFound),
            (.selectOutputDevice, AppStrings.chooseOutputToStart),
            (.driverBuildMismatch(appBuildID: Self.appID, driverBuildID: Self.driverID), AppStrings.driverBuildMismatch),
            (.driverBuildMismatch(appBuildID: Self.appID, driverBuildID: nil), AppStrings.driverBuildMismatch),
            (.selectedOutputGone, AppStrings.previousOutputUnavailable(name: "Studio Speakers")),
            (
                .selectedOutputIncompatible(issue: .stereoOutputUnavailable),
                AppStrings.selectedOutputIncompatible(
                    issue: AppStrings.compatibility(.stereoOutputUnavailable)
                )
            ),
        ]
        for (error, expected) in cases {
            XCTAssertEqual(
                error.startBlockedText(outputName: "Studio Speakers"),
                expected,
                String(describing: error)
            )
        }
        let gone = BridgeError.selectedOutputGone.startBlockedText(outputName: "Studio Speakers")
        XCTAssertTrue(gone.contains("Studio Speakers"))
        XCTAssertEqual(gone.filter { $0 == "." }.count, 0)
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
        for bad in [nil, "", "   ", "unknown", "Unknown", "UNKNOWN", "UnKnOwN", "  Unknown  ", "$(APM44_BUILD_ID)", "${APM44_BUILD_ID}", "$APM44_BUILD_ID"] {
            XCTAssertNil(
                HalDriverDetector.normalizedBuildID(bad),
                "normalizedBuildID(\(String(describing: bad))) must be nil"
            )
            XCTAssertFalse(
                HalDriverDetector.buildIDsMatch(appBuildID: bad, driverBuildID: driverID),
                "app ID \(String(describing: bad)) must not match"
            )
            XCTAssertFalse(
                HalDriverDetector.buildIDsMatch(appBuildID: appID, driverBuildID: bad),
                "driver ID \(String(describing: bad)) must not match"
            )
            XCTAssertFalse(
                HalDriverDetector.buildIDsMatch(appBuildID: bad, driverBuildID: bad),
                "placeholder \(String(describing: bad)) must never match itself"
            )
        }
        XCTAssertFalse(HalDriverDetector.buildIDsMatch(appBuildID: nil, driverBuildID: nil))
        XCTAssertTrue(
            HalDriverDetector.buildIDsMatch(appBuildID: appID, driverBuildID: appID),
            "valid exact full-ID comparison must still match"
        )
    }

    func testWhitespaceIsTrimmedBeforeCompare() {
        XCTAssertTrue(HalDriverDetector.buildIDsMatch(
            appBuildID: "  \(appID)\n",
            driverBuildID: appID
        ))
    }

    func testMismatchStatusIsNotReady() {
        let status = HalDriverDetector.status(
            halPresent: true,
            appBuildID: appID,
            driverBuildID: driverID,
            driverBundleOnDisk: true
        )
        XCTAssertEqual(status, .buildMismatch)
        XCTAssertNotEqual(status, .ready)
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

    private func makeManager(
        launcher: MockProcessLauncher,
        halCheck: HalBuildCheck
    ) async -> (BridgeProcessManager, BridgeSettings) {
        let suite = "com.niko.apm44.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = BridgeSettings(defaults: defaults)
        settings.outputDeviceUid = testDevice.uid
        let manager = BridgeProcessManager(
            settings: settings,
            processLauncher: launcher,
            binaryURLOverride: URL(fileURLWithPath: "/tmp/apm44-bridge"),
            deviceSource: FakeBridgeDeviceSource(
                halCheck: halCheck,
                devices: [testDevice]
            ),
            applicationTerminator: {}
        )
        await manager.refreshDevices()
        return (manager, settings)
    }

    func testStartBlockedOnMismatchLaunchesNothing() async {
        let launcher = MockProcessLauncher()
        let (manager, _) = await makeManager(
            launcher: launcher,
            halCheck: HalBuildCheck(halPresent: true, appBuildID: appID, driverBuildID: driverID)
        )
        manager.start()
        XCTAssertEqual(launcher.makeCount, 0)
        if case .error(let error) = manager.state {
            XCTAssertEqual(error, .driverBuildMismatch(appBuildID: appID, driverBuildID: driverID))
            XCTAssertEqual(
                BridgeErrorPresentation.headline(for: error),
                AppStrings.driverBuildMismatch
            )
        } else {
            XCTFail("expected .error on build mismatch, got \(manager.state)")
        }
    }

    func testStartBlockedOnMissingDriverID() async {
        let launcher = MockProcessLauncher()
        let (manager, _) = await makeManager(
            launcher: launcher,
            halCheck: HalBuildCheck(halPresent: true, appBuildID: appID, driverBuildID: nil)
        )
        manager.start()
        XCTAssertEqual(launcher.makeCount, 0)
        if case .error = manager.state { } else {
            XCTFail("expected .error when driver ID is missing with HAL present")
        }
    }

    func testStartAllowedWhenIDsMatch() async {
        let launcher = MockProcessLauncher()
        let (manager, _) = await makeManager(
            launcher: launcher,
            halCheck: HalBuildCheck(halPresent: true, appBuildID: appID, driverBuildID: appID)
        )
        manager.start()
        XCTAssertEqual(launcher.makeCount, 1)
        XCTAssertEqual(manager.state, .running)
    }

    func testStartAllowedInBlackHoleFallbackWithoutDriver() async {
        let launcher = MockProcessLauncher()
        let (manager, _) = await makeManager(
            launcher: launcher,
            halCheck: HalBuildCheck(halPresent: false, appBuildID: appID, driverBuildID: nil)
        )
        manager.start()
        XCTAssertEqual(launcher.makeCount, 1)
        XCTAssertEqual(manager.state, .running)
    }
}
