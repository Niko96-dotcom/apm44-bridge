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
        let message = longHelperFailure()
        XCTAssertGreaterThan(message.count, 60)
        let presentation = BridgeErrorPresentation.presentation(for: message)
        XCTAssertEqual(presentation.headline, AppStrings.couldNotStart)
        XCTAssertFalse(presentation.headline.hasSuffix("…"))
        XCTAssertFalse(presentation.headline.contains("0x3f2a"))
        XCTAssertEqual(presentation.recovery, AppStrings.genericFailureRecovery)
        XCTAssertEqual(presentation.diagnostic, message)
    }

    func testHeadlineNeverTruncatesWithEllipsis() {
        let message = longHelperFailure()
        let headline = BridgeErrorPresentation.headline(for: message)
        XCTAssertFalse(headline.contains("…"))
        XCTAssertLessThanOrEqual(headline.count, 60)
    }

    func testBridgeCouldNotStartKeepsFullDiagnostic() {
        let detail = "kAudioHardwareUnknownPropertyError endpoint unavailable"
        let message = AppStrings.bridgeCouldNotStart(detail: detail)
        let presentation = BridgeErrorPresentation.presentation(for: message)
        XCTAssertEqual(presentation.headline, AppStrings.couldNotStart)
        XCTAssertEqual(presentation.recovery, AppStrings.genericFailureRecovery)
        XCTAssertEqual(presentation.diagnostic, message)
        XCTAssertTrue(presentation.diagnostic?.contains(detail) == true)
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
        }
    }

    func testMissingSelectionMapsToChooseOutputRecovery() {
        let presentation = BridgeErrorPresentation.presentation(for: AppStrings.selectOutputDevice)
        XCTAssertEqual(presentation.recovery, AppStrings.chooseOutputToStart)
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

    func testUnstableLaunchesMapToGenericHeadlineWithFullDiagnostic() {
        let message = AppStrings.stoppedAfterUnstableLaunches(4, detail: ": helper failed id=0x1")
        let presentation = BridgeErrorPresentation.presentation(for: message)
        XCTAssertEqual(presentation.headline, AppStrings.couldNotStart)
        XCTAssertEqual(presentation.diagnostic, message)
        XCTAssertNotNil(presentation.recovery)
    }
}
