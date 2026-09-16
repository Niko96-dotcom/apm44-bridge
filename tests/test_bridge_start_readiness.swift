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
