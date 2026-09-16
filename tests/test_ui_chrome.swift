import XCTest
@testable import APM44Bridge

final class AppStringsChromeTests: XCTestCase {
    func testCubaseSubtitleIsPortConstraintOnly() {
        XCTAssertFalse(AppStrings.cubaseControlRoomHint.isEmpty)
        XCTAssertNotEqual(AppStrings.cubaseControlRoomHint, AppStrings.cubaseControlRoom)
        XCTAssertFalse(AppStrings.cubaseControlRoomHint.contains("."))
        XCTAssertFalse(AppStrings.cubaseControlRoomHint.localizedCaseInsensitiveContains("click-free"))
        XCTAssertFalse(AppStrings.cubaseControlRoomHint.localizedCaseInsensitiveContains("welcome"))
        XCTAssertFalse(AppStrings.cubaseControlRoomHint.localizedCaseInsensitiveContains("manage your"))
    }

    func testEmptyOutputStateDoesNotRestatePicker() {
        XCTAssertFalse(AppStrings.noOutputDevices.isEmpty)
        XCTAssertFalse(AppStrings.noOutputDevicesHint.isEmpty)
        XCTAssertNotEqual(AppStrings.noOutputDevicesHint, AppStrings.noOutputDevices)
        XCTAssertFalse(AppStrings.noOutputDevicesHint.localizedCaseInsensitiveContains("choose an output"))
    }

    func testAdminPasswordHelperIsPrivilegeConstraint() {
        XCTAssertFalse(AppStrings.enterAdminPassword.isEmpty)
        XCTAssertFalse(AppStrings.enterAdminPassword.localizedCaseInsensitiveContains("enter your"))
    }

    func testBufferingSubtitleIsDurationOrPathConstraint() {
        XCTAssertTrue(AppStrings.bufferTarget(100).contains("100"))
        XCTAssertTrue(AppStrings.bufferTargetMinimum(20).contains("20"))
        XCTAssertTrue(AppStrings.bufferTargetMinimum(20).localizedCaseInsensitiveContains("minimum"))
        XCTAssertFalse(AppStrings.bufferTarget(15).localizedCaseInsensitiveContains("buffer"))
    }

    func testStoppedLatencyHintAddsAdditionalLatencyOnly() {
        XCTAssertFalse(AppStrings.stoppedLatencyHint.isEmpty)
        XCTAssertFalse(AppStrings.stoppedLatencyHint.localizedCaseInsensitiveContains("buffer"))
        XCTAssertFalse(AppStrings.stoppedLatencyHint.contains("~"))
        XCTAssertEqual(LatencyPreset.safe.stoppedLatencyHint, AppStrings.stoppedLatencyHint)
    }

    func testReconnectBannerOmitsLaunchEssay() {
        let text = AppStrings.reconnectingAttempt(current: 2, max: 4)
        XCTAssertTrue(text.contains("2"))
        XCTAssertTrue(text.contains("4"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("stable"))
    }

    func testDriverDetailsAreStatusNotInstallerTours() {
        XCTAssertFalse(AppStrings.driverReloadHint.contains("."))
        XCTAssertFalse(AppStrings.driverRestartHint.contains("."))
        XCTAssertFalse(AppStrings.driverMissingDetail.localizedCaseInsensitiveContains("open the"))
        XCTAssertFalse(AppStrings.driverMissingDetail.localizedCaseInsensitiveContains(".pkg"))
    }

    func testGoneOutputErrorIsProblemWithoutFixEcho() {
        XCTAssertFalse(AppStrings.selectedOutputGone.isEmpty)
        XCTAssertFalse(AppStrings.selectedOutputGone.localizedCaseInsensitiveContains("choose another"))
    }

    func testPreviousOutputErrorIsOneLine() {
        let text = AppStrings.previousOutputUnavailable(name: "Studio Speakers")
        XCTAssertTrue(text.contains("Studio Speakers"))
        XCTAssertEqual(text.filter { $0 == "." }.count, 0)
    }
}
