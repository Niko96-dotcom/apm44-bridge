import XCTest
@testable import APM44Bridge

@MainActor
final class SetupCoordinatorTests: XCTestCase {
    func testRequestPersistsUntilConsumed() {
        let coordinator = SetupCoordinator()
        XCTAssertFalse(coordinator.isSetupRequested)
        coordinator.requestSetup()
        XCTAssertTrue(coordinator.isSetupRequested)
        coordinator.consumeSetupRequest()
        XCTAssertFalse(coordinator.isSetupRequested)
    }

    func testFirstRunAutoClaimIsFirstComeWins() {
        let coordinator = SetupCoordinator()
        XCTAssertTrue(coordinator.claimFirstRunAuto())
        XCTAssertFalse(coordinator.claimFirstRunAuto())
        coordinator.resetForTesting()
        XCTAssertTrue(coordinator.claimFirstRunAuto())
    }

    func testMenuContentDefaultsToNonOwning() {
        let settings = BridgeSettings(defaults: UserDefaults(suiteName: "com.niko.apm44.tests.\(UUID().uuidString)")!)
        let manager = BridgeProcessManager(
            settings: settings,
            processLauncher: MockProcessLauncher(),
            binaryURLOverride: URL(fileURLWithPath: "/tmp/apm44-bridge")
        )
        let menuBarView = MenuContentView(manager: manager, settings: settings)
        XCTAssertFalse(menuBarView.presentsGlobalSetup)
        let settingsView = MenuContentView(manager: manager, settings: settings)
        XCTAssertFalse(settingsView.presentsGlobalSetup)
        let controlsView = MenuContentView(
            manager: manager,
            settings: settings,
            presentsGlobalSetup: true
        )
        XCTAssertTrue(controlsView.presentsGlobalSetup)
    }
}

final class BridgeErrorPresentationTests: XCTestCase {
    private func longHelperFailure() -> String {
        "helper exited with status 1: could not open output device (kAudioHardwareUnknownPropertyError, id=0x3f2a, endpoint unavailable after 250ms retry loop)"
    }

    func testLongHelperFailureUsesShortHeadlineWithRecoveryAndFullDiagnostic() {
        let bridgeDetail = "kAudioHardwareUnknownPropertyError endpoint unavailable"
        let messages = [
            longHelperFailure(),
            AppStrings.bridgeCouldNotStart(detail: bridgeDetail),
            AppStrings.stoppedAfterUnstableLaunches(4, detail: ": helper failed id=0x1"),
        ]
        XCTAssertGreaterThan(messages[0].count, 60)
        for message in messages {
            let presentation = BridgeErrorPresentation.presentation(for: message)
            XCTAssertEqual(presentation.headline, AppStrings.couldNotStart, "\(message)")
            XCTAssertFalse(presentation.headline.hasSuffix("…"), "\(message)")
            XCTAssertFalse(presentation.headline.contains("…"), "\(message)")
            XCTAssertLessThanOrEqual(presentation.headline.count, 60, "\(message)")
            XCTAssertEqual(presentation.recovery, AppStrings.genericFailureRecovery, "\(message)")
            XCTAssertNotNil(presentation.recovery, "\(message)")
            XCTAssertEqual(presentation.diagnostic, message, "\(message)")
        }
        XCTAssertFalse(BridgeErrorPresentation.presentation(for: messages[0]).headline.contains("0x3f2a"))
        XCTAssertTrue(BridgeErrorPresentation.presentation(for: messages[1]).diagnostic?.contains(bridgeDetail) == true)
        for message in messages {
            let headline = BridgeErrorPresentation.headline(for: message)
            XCTAssertFalse(headline.contains("…"), "\(message)")
            XCTAssertLessThanOrEqual(headline.count, 60, "\(message)")
        }
    }

    func testKnownShortMessagesStayAsHeadline() {
        for message in [
            AppStrings.bridgeNotFound,
            AppStrings.selectOutputDevice,
            AppStrings.selectedOutputGone,
            AppStrings.bridgeDidNotStop,
            AppStrings.outputDeviceDisconnected,
            AppStrings.couldNotStart,
            AppStrings.ipcFailed(),
        ] {
            let presentation = BridgeErrorPresentation.presentation(for: message)
            XCTAssertEqual(presentation.headline, message)
            XCTAssertNil(presentation.diagnostic, "short message should not need Details: \(message)")
            if message == AppStrings.selectOutputDevice {
                XCTAssertEqual(presentation.recovery, AppStrings.chooseOutputToStart)
            }
        }
    }

    func testIncompatibleOutputKeepsHeadlineWithCompatibleRecovery() {
        let message = AppStrings.selectedOutputIncompatible(
            issue: AppStrings.compatibility("Stereo output unavailable")
        )
        let presentation = BridgeErrorPresentation.presentation(for: message)
        XCTAssertEqual(presentation.headline, message)
        XCTAssertEqual(presentation.recovery, AppStrings.incompatibleOutputRecovery)
        XCTAssertNil(presentation.diagnostic)
    }
}

final class BridgeBuildMismatchPresentationTests: XCTestCase {
    private let appID = "0.12.7+3fc0b148b674"
    private let driverID = "0.12.7+c2728cba0591"

    func testMismatchDetailCarriesBothBuildIDs() {
        let detail = AppStrings.driverBuildMismatchDetail(app: appID, driver: driverID)
        XCTAssertTrue(detail.contains(appID), detail)
        XCTAssertTrue(detail.contains(driverID), detail)
    }

    func testShortMismatchMessageHasRecoveryWithoutDiagnostic() {
        let presentation = BridgeErrorPresentation.presentation(for: AppStrings.driverBuildMismatch)
        XCTAssertEqual(presentation.headline, AppStrings.driverBuildMismatch)
        XCTAssertEqual(presentation.recovery, AppStrings.driverBuildMismatchRecovery)
        XCTAssertNil(presentation.diagnostic)
        XCTAssertFalse(AppStrings.driverBuildMismatch.isEmpty)
        XCTAssertFalse(AppStrings.driverBuildMismatchRecovery.isEmpty)
    }

    func testDetailedMismatchKeepsFullDiagnostic() {
        let messages = [
            AppStrings.driverBuildMismatchDetail(app: appID, driver: driverID),
            AppStrings.driverBuildMismatchDetail(
                app: appID,
                driver: AppStrings.buildIDMissingPlaceholder
            ),
        ]
        for message in messages {
            let presentation = BridgeErrorPresentation.presentation(for: message)
            XCTAssertEqual(presentation.headline, AppStrings.driverBuildMismatch, "\(message)")
            XCTAssertEqual(presentation.recovery, AppStrings.driverBuildMismatchRecovery, "\(message)")
            XCTAssertNotNil(presentation.recovery, "\(message)")
            XCTAssertEqual(presentation.diagnostic, message, "\(message)")
        }
    }

    func testLoadedDriverBuildMismatchHasRecoveryWithoutDiagnostic() {
        let presentation = BridgeErrorPresentation.presentation(
            for: AppStrings.loadedDriverBuildMismatch
        )
        XCTAssertEqual(presentation.headline, AppStrings.loadedDriverBuildMismatch)
        XCTAssertEqual(presentation.recovery, AppStrings.loadedDriverBuildMismatchRecovery)
        XCTAssertNil(presentation.diagnostic)
        XCTAssertFalse(AppStrings.loadedDriverBuildMismatch.isEmpty)
        XCTAssertFalse(AppStrings.loadedDriverBuildMismatchRecovery.isEmpty)
    }
}
