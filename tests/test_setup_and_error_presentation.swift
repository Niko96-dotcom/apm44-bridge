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
        let errors: [BridgeError] = [
            .helperFailed(stderr: longHelperFailure()),
            .launchFailed(detail: bridgeDetail),
            .unstableLaunches(maxAttempts: 4, lastExitStatus: 1, lastStderr: "helper failed id=0x1"),
        ]
        XCTAssertGreaterThan(longHelperFailure().count, 60)
        for error in errors {
            let presentation = BridgeErrorPresentation.presentation(for: error)
            XCTAssertEqual(presentation.headline, AppStrings.couldNotStart, "\(error)")
            XCTAssertFalse(presentation.headline.contains("…"), "\(error)")
            XCTAssertLessThanOrEqual(presentation.headline.count, 60, "\(error)")
            XCTAssertEqual(presentation.recovery, AppStrings.genericFailureRecovery, "\(error)")
        }
        XCTAssertEqual(
            BridgeErrorPresentation.presentation(for: errors[0]).diagnostic,
            longHelperFailure()
        )
        XCTAssertFalse(BridgeErrorPresentation.presentation(for: errors[0]).headline.contains("0x3f2a"))
        XCTAssertTrue(BridgeErrorPresentation.presentation(for: errors[1]).diagnostic?.contains(bridgeDetail) == true)
        XCTAssertEqual(
            BridgeErrorPresentation.presentation(for: errors[2]).diagnostic,
            errors[2].message
        )
    }

    func testKnownShortErrorsStayAsHeadline() {
        let cases: [(BridgeError, String, BridgeErrorRecovery?)] = [
            (.bridgeNotFound, AppStrings.bridgeNotFound, nil),
            (.selectOutputDevice, AppStrings.selectOutputDevice, .chooseOutput),
            (.selectedOutputGone, AppStrings.selectedOutputGone, .chooseOutput),
            (.outputDeviceDisconnected, AppStrings.outputDeviceDisconnected, .selectDisconnectedOutput),
            (.bridgeDidNotStop, AppStrings.bridgeDidNotStop, .tryAgain),
            (.helperFailed(stderr: nil), AppStrings.couldNotStart, .tryAgain),
            (.driverIPCFailed, AppStrings.ipcFailed(), nil),
            (.loadedDriverBuildMismatch, AppStrings.loadedDriverBuildMismatch, .reloadCoreAudio),
            (.helperAlreadyRunning, AppStrings.helperAlreadyRunning, .quitOtherHelper),
        ]
        for (error, headline, recovery) in cases {
            let presentation = BridgeErrorPresentation.presentation(for: error)
            XCTAssertEqual(presentation.headline, headline, "\(error)")
            XCTAssertEqual(presentation.recovery, recovery?.text, "\(error)")
            XCTAssertNil(presentation.diagnostic, "short error should not need Details: \(error)")
        }
    }

    func testIncompatibleOutputKeepsHeadlineWithCompatibleRecovery() {
        let error = BridgeError.selectedOutputIncompatible(issue: "Stereo output unavailable")
        let presentation = BridgeErrorPresentation.presentation(for: error)
        XCTAssertEqual(
            presentation.headline,
            AppStrings.selectedOutputIncompatible(
                issue: AppStrings.compatibility("Stereo output unavailable")
            )
        )
        XCTAssertEqual(presentation.recovery, AppStrings.incompatibleOutputRecovery)
        XCTAssertNil(presentation.diagnostic)
    }

    /// The recovery choice belongs to the error kind. The presentation reads
    /// it without looking at any rendered text, so it cannot vary with the
    /// user's language or with wording in the payload.
    func testRecoveryChoiceComesFromKindNotWording() {
        XCTAssertEqual(BridgeError.selectedOutputIncompatible(issue: "Stereo output unavailable").recovery, .chooseCompatibleOutput)
        XCTAssertEqual(BridgeError.selectedOutputIncompatible(issue: "Ausgabe nicht stereo").recovery, .chooseCompatibleOutput)
        XCTAssertEqual(BridgeError.selectedOutputIncompatible(issue: nil).recovery, .chooseCompatibleOutput)
        // A helper line that happens to read like another known error is
        // still just helper output.
        let lookalikes = [
            AppStrings.bridgeNotFound,
            AppStrings.selectedOutputGone,
            AppStrings.ipcFailed(),
            AppStrings.driverBuildMismatchDetail(app: "a", driver: "b"),
        ]
        for line in lookalikes {
            let presentation = BridgeErrorPresentation.presentation(for: .helperFailed(stderr: line))
            XCTAssertEqual(presentation.headline, AppStrings.couldNotStart, line)
            XCTAssertEqual(presentation.recovery, BridgeErrorRecovery.tryAgain.text, line)
            XCTAssertEqual(presentation.diagnostic, line)
        }
    }

    func testUnknownStderrIsVerbatimDiagnosticWhileSummaryIsSanitized() {
        let raw = "fatal:\u{01} could not open\toutput\r device\u{7f} id=0x3f2a"
        var tail = DaemonStderrTail()
        tail.append("earlier line\n\(raw)")
        let failure = tail.failure(exitStatus: 1)
        XCTAssertEqual(failure, .helperFailed(stderr: raw))
        let presentation = BridgeErrorPresentation.presentation(for: failure)
        XCTAssertEqual(presentation.diagnostic, "fatal:\u{01} could not open\toutput\r device\u{7f} id=0x3f2a")
        XCTAssertEqual(presentation.headline, AppStrings.couldNotStart)

        // The retry summary that embeds stderr is the sanitized single line.
        var budget = BridgeRetryBudget()
        budget.recordUnexpectedExit(status: 1, stderr: BridgeDiagnostics.sanitized(raw))
        let summary = budget.exhaustedError.message
        XCTAssertTrue(summary.contains("fatal: could not openoutput  device id=0x3f2a"), summary)
        XCTAssertFalse(summary.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7f }, summary)
        XCTAssertEqual(BridgeErrorPresentation.presentation(for: budget.exhaustedError).diagnostic, summary)
    }
}

final class BridgeBuildMismatchPresentationTests: XCTestCase {
    private let appID = "0.12.7+3fc0b148b674"
    private let driverID = "0.12.7+c2728cba0591"

    func testMismatchShowsBothBuildIDsFromFieldsWithoutParsing() {
        let error = BridgeError.driverBuildMismatch(appBuildID: appID, driverBuildID: driverID)
        guard let diagnostic = BridgeErrorPresentation.presentation(for: error).diagnostic else {
            return XCTFail("mismatch must carry a diagnostic")
        }
        XCTAssertTrue(diagnostic.contains(appID), diagnostic)
        XCTAssertTrue(diagnostic.contains(driverID), diagnostic)
        XCTAssertEqual(diagnostic, AppStrings.driverBuildMismatchDetail(app: appID, driver: driverID))
    }

    func testMismatchHasShortHeadlineAndRecovery() {
        let presentation = BridgeErrorPresentation.presentation(
            for: .driverBuildMismatch(appBuildID: appID, driverBuildID: driverID)
        )
        XCTAssertEqual(presentation.headline, AppStrings.driverBuildMismatch)
        XCTAssertEqual(presentation.recovery, AppStrings.driverBuildMismatchRecovery)
        XCTAssertNotNil(presentation.recovery)
    }

    func testMissingBuildIDRendersPlaceholder() {
        let error = BridgeError.driverBuildMismatch(appBuildID: appID, driverBuildID: nil)
        let presentation = BridgeErrorPresentation.presentation(for: error)
        XCTAssertEqual(presentation.headline, AppStrings.driverBuildMismatch)
        XCTAssertEqual(
            presentation.diagnostic,
            AppStrings.driverBuildMismatchDetail(app: appID, driver: AppStrings.buildIDMissingPlaceholder)
        )
    }

    func testLoadedDriverBuildMismatchHasRecoveryWithoutDiagnostic() {
        let presentation = BridgeErrorPresentation.presentation(for: .loadedDriverBuildMismatch)
        XCTAssertEqual(presentation.headline, AppStrings.loadedDriverBuildMismatch)
        XCTAssertEqual(presentation.recovery, AppStrings.loadedDriverBuildMismatchRecovery)
        XCTAssertNil(presentation.diagnostic)
    }

    func testHelperAlreadyRunningHasRecoveryWithoutDiagnostic() {
        let presentation = BridgeErrorPresentation.presentation(for: .helperAlreadyRunning)
        XCTAssertEqual(presentation.headline, AppStrings.helperAlreadyRunning)
        XCTAssertEqual(presentation.recovery, AppStrings.helperAlreadyRunningRecovery)
        XCTAssertNil(presentation.diagnostic)
    }
}
