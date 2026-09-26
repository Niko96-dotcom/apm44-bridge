import AppKit
import XCTest
@testable import APM44Bridge

final class SparkleUpdaterTests: XCTestCase {
    func testCurrentAndDowngradeVersionsDoNotCountAsNewer() {
        XCTAssertEqual(AppUpdateVersionComparator.compare("0.12.2", to: "0.12.2"), .same)
        XCTAssertEqual(AppUpdateVersionComparator.compare("0.12.1", to: "0.12.2"), .older)
        XCTAssertFalse(AppUpdateVersionComparator.isNewer("0.12.2", than: "0.12.2"))
        XCTAssertFalse(AppUpdateVersionComparator.isNewer("0.12.1", than: "0.12.2"))
        XCTAssertTrue(AppUpdateVersionComparator.isNewer("0.12.3", than: "0.12.2"))
        XCTAssertTrue(AppUpdateVersionComparator.isNewer("1.0", than: "0.99.99"))
    }

    func testMalformedVersionIsRejected() {
        XCTAssertEqual(AppUpdateVersionComparator.compare("0.12.beta", to: "0.12.2"), .invalid)
        XCTAssertFalse(AppUpdateVersionComparator.isNewer("", than: "0.12.2"))
    }

    func testSecurityAndNetworkErrorsAreSafeAndUserFacing() {
        let signatureError = NSError(domain: "SUSparkleErrorDomain", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "invalid EdDSA signature"])
        XCTAssertEqual(
            SparkleUpdateController.userFacingErrorMessage(signatureError),
            AppStrings.updateFeedUnverified
        )

        let unreachableError = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost,
                                       userInfo: [NSLocalizedDescriptionKey: "The server could not be reached"])
        XCTAssertEqual(
            SparkleUpdateController.userFacingErrorMessage(unreachableError),
            AppStrings.updateCheckFailed(detail: "The server could not be reached")
        )
    }

    func testNoUpdateErrorIsRecognizedAsSuccessfulCheck() {
        let noUpdateError = NSError(domain: "SUSparkleErrorDomain", code: 1001,
                                    userInfo: [NSLocalizedDescriptionKey: "You’re up to date!"])
        XCTAssertTrue(SparkleUpdateController.isNoUpdateError(noUpdateError))
        XCTAssertEqual(
            SparkleUpdateController.userFacingErrorMessage(noUpdateError),
            AppStrings.noUpdateAvailable
        )
    }

    func testShouldRunLaunchCheck() {
        let launchDate = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertFalse(SparkleUpdateController.shouldRunLaunchCheck(
            automaticallyChecks: false, lastCheckDate: nil, launchDate: launchDate))
        XCTAssertFalse(SparkleUpdateController.shouldRunLaunchCheck(
            automaticallyChecks: false,
            lastCheckDate: launchDate.addingTimeInterval(-86400),
            launchDate: launchDate))
        XCTAssertTrue(SparkleUpdateController.shouldRunLaunchCheck(
            automaticallyChecks: true, lastCheckDate: nil, launchDate: launchDate))
        XCTAssertTrue(SparkleUpdateController.shouldRunLaunchCheck(
            automaticallyChecks: true,
            lastCheckDate: launchDate.addingTimeInterval(-86400),
            launchDate: launchDate))
        XCTAssertFalse(SparkleUpdateController.shouldRunLaunchCheck(
            automaticallyChecks: true,
            lastCheckDate: launchDate.addingTimeInterval(1),
            launchDate: launchDate))
        XCTAssertFalse(SparkleUpdateController.shouldRunLaunchCheck(
            automaticallyChecks: true, lastCheckDate: launchDate, launchDate: launchDate))
    }

    func testCheckForUpdatesString() {
        XCTAssertFalse(AppStrings.checkForUpdates.isEmpty)
        XCTAssertTrue(AppStrings.checkForUpdates.hasSuffix("…"))
    }


    func testManualCheckIsBlockedWhileBusyOrInstalling() {
        // Idle, cancelled, and failed follow canCheckForUpdates.
        let gated: [AppUpdateState] = [
            .idle,
            .cancelled,
            .failed(message: "x"),
        ]
        for state in gated {
            XCTAssertTrue(SparkleUpdateController.canStartManualCheck(canCheckForUpdates: true, state: state), "\(state)")
            XCTAssertFalse(SparkleUpdateController.canStartManualCheck(canCheckForUpdates: false, state: state), "\(state)")
        }
        // Available and ready-to-install stay enabled even when Sparkle's
        // session is open (deferred scheduled update), so the footer link
        // can reach showPendingUpdate.
        let pending: [AppUpdateState] = [
            .available(version: "1.0"),
            .readyToInstall(version: "1.0"),
        ]
        for state in pending {
            XCTAssertTrue(SparkleUpdateController.canStartManualCheck(canCheckForUpdates: true, state: state), "\(state)")
            XCTAssertTrue(SparkleUpdateController.canStartManualCheck(canCheckForUpdates: false, state: state), "\(state)")
        }
        let busy: [AppUpdateState] = [.checking, .installing(version: "1.0")]
        for state in busy {
            XCTAssertFalse(SparkleUpdateController.canStartManualCheck(canCheckForUpdates: true, state: state), "\(state)")
            XCTAssertFalse(SparkleUpdateController.canStartManualCheck(canCheckForUpdates: false, state: state), "\(state)")
        }
    }

    func testReadyToInstallAllowsShowPendingUpdate() {
        XCTAssertTrue(SparkleUpdateController.canShowPendingUpdate(state: .readyToInstall(version: "0.12.12")))
        XCTAssertTrue(SparkleUpdateController.canShowPendingUpdate(state: .available(version: "0.12.12")))
        XCTAssertFalse(SparkleUpdateController.canShowPendingUpdate(state: .idle))
        XCTAssertFalse(SparkleUpdateController.canShowPendingUpdate(state: .checking))
        XCTAssertFalse(SparkleUpdateController.canShowPendingUpdate(state: .installing(version: "0.12.12")))
        XCTAssertFalse(SparkleUpdateController.canShowPendingUpdate(state: .cancelled))
        XCTAssertFalse(SparkleUpdateController.canShowPendingUpdate(state: .failed(message: "x")))
        // Both pending states must reach showPendingUpdate via the generic check path.
        XCTAssertTrue(SparkleUpdateController.canStartManualCheck(canCheckForUpdates: true, state: .readyToInstall(version: "0.12.12")))
        XCTAssertTrue(SparkleUpdateController.canStartManualCheck(canCheckForUpdates: false, state: .readyToInstall(version: "0.12.12")))
        XCTAssertTrue(SparkleUpdateController.canStartManualCheck(canCheckForUpdates: true, state: .available(version: "0.12.12")))
        XCTAssertTrue(SparkleUpdateController.canStartManualCheck(canCheckForUpdates: false, state: .available(version: "0.12.12")))
        XCTAssertFalse(SparkleUpdateController.canStartManualCheck(canCheckForUpdates: true, state: .checking))
        XCTAssertFalse(SparkleUpdateController.canStartManualCheck(canCheckForUpdates: true, state: .installing(version: "0.12.12")))
    }

    func testDownloadInterruptionMappingDirectAndWrapped() {
        let direct = NSError(
            domain: NSURLErrorDomain,
            code: -1005,
            userInfo: [NSLocalizedDescriptionKey: "Die Netzwerkverbindung wurde unterbrochen."]
        )
        XCTAssertEqual(
            SparkleUpdateController.downloadErrorMessage(direct),
            AppStrings.updateDownloadInterrupted
        )

        let underlying = NSError(
            domain: NSURLErrorDomain,
            code: -1005,
            userInfo: [NSLocalizedDescriptionKey: "Die Netzwerkverbindung wurde unterbrochen."]
        )
        let wrapped = NSError(
            domain: "SUSparkleErrorDomain",
            code: 2001,
            userInfo: [
                NSLocalizedDescriptionKey: "Beim Laden des Updates ist ein Fehler aufgetreten.",
                NSUnderlyingErrorKey: underlying,
            ]
        )
        XCTAssertEqual(
            SparkleUpdateController.downloadErrorMessage(wrapped),
            AppStrings.updateDownloadInterrupted
        )
    }

    func testOtherDownloadErrorMapsToDownloadFailed() {
        let other = NSError(
            domain: "SUSparkleErrorDomain",
            code: 2001,
            userInfo: [NSLocalizedDescriptionKey: "Download failed for another reason."]
        )
        XCTAssertEqual(
            SparkleUpdateController.downloadErrorMessage(other),
            AppStrings.updateDownloadFailed(detail: "Download failed for another reason.")
        )
    }

    func testCheckFailureMappingUnchanged() {
        let checkError = NSError(
            domain: "SUSparkleErrorDomain",
            code: 1002,
            userInfo: [NSLocalizedDescriptionKey: "The update server returned an error."]
        )
        XCTAssertEqual(
            SparkleUpdateController.userFacingErrorMessage(checkError),
            AppStrings.updateCheckFailed(detail: "The update server returned an error.")
        )
    }

    func testSignatureMappingUnchangedForDownload() {
        let signatureError = NSError(
            domain: "SUSparkleErrorDomain",
            code: 3001,
            userInfo: [NSLocalizedDescriptionKey: "invalid EdDSA signature"]
        )
        XCTAssertEqual(
            SparkleUpdateController.downloadErrorMessage(signatureError),
            AppStrings.updateFeedUnverified
        )
        XCTAssertEqual(
            SparkleUpdateController.userFacingErrorMessage(signatureError),
            AppStrings.updateFeedUnverified
        )
    }

    func testBenignInstallationErrorTreatedAsSuccess() {
        let alreadyInstalled = NSError(
            domain: "SUSparkleErrorDomain",
            code: 4005,
            userInfo: [NSLocalizedDescriptionKey: "remote port connection was invalidated"]
        )
        XCTAssertTrue(SparkleUpdateController.shouldTreatInstallationErrorAsSuccess(
            state: .installing(version: "0.12.12"),
            error: alreadyInstalled,
            currentVersion: "0.12.12"
        ))
        XCTAssertFalse(SparkleUpdateController.shouldTreatInstallationErrorAsSuccess(
            state: .installing(version: "0.12.12"),
            error: alreadyInstalled,
            currentVersion: "0.12.11"
        ))
        let downloadError = NSError(
            domain: "SUSparkleErrorDomain",
            code: 2001,
            userInfo: [NSLocalizedDescriptionKey: "download failed"]
        )
        XCTAssertFalse(SparkleUpdateController.shouldTreatInstallationErrorAsSuccess(
            state: .installing(version: "0.12.12"),
            error: downloadError,
            currentVersion: "0.12.12"
        ))
        XCTAssertFalse(SparkleUpdateController.shouldTreatInstallationErrorAsSuccess(
            state: .available(version: "0.12.12"),
            error: alreadyInstalled,
            currentVersion: "0.12.12"
        ))
        let agentInvalidation = NSError(
            domain: "SUSparkleErrorDomain",
            code: 4010,
            userInfo: [NSLocalizedDescriptionKey: "agent invalidated"]
        )
        XCTAssertTrue(SparkleUpdateController.shouldTreatInstallationErrorAsSuccess(
            state: .installing(version: "0.12.12"),
            error: agentInvalidation,
            currentVersion: "0.12.12"
        ))
    }

    func testPlain4005WithoutRemotePortTextIsNotAccepted() {
        let plain = NSError(
            domain: "SUSparkleErrorDomain",
            code: 4005,
            userInfo: [NSLocalizedDescriptionKey: "Beim Ausführen des Aktualisierungsprogramms ist ein Fehler aufgetreten."]
        )
        XCTAssertFalse(SparkleUpdateController.shouldTreatInstallationErrorAsSuccess(
            state: .installing(version: "0.12.12"),
            error: plain,
            currentVersion: "0.12.12"
        ))
        XCTAssertFalse(SparkleUpdateController.containsRemotePortInvalidation(plain))
    }

    func test4005WithRemotePortTextInUnderlyingErrorIsAccepted() {
        let underlying = NSError(
            domain: NSURLErrorDomain,
            code: -1001,
            userInfo: [NSLocalizedDescriptionKey: "The remote port connection was invalidated from the updater."]
        )
        let wrapped = NSError(
            domain: "SUSparkleErrorDomain",
            code: 4005,
            userInfo: [
                NSLocalizedDescriptionKey: "Beim Ausführen des Aktualisierungsprogramms ist ein Fehler aufgetreten.",
                NSUnderlyingErrorKey: underlying,
            ]
        )
        XCTAssertTrue(SparkleUpdateController.containsRemotePortInvalidation(wrapped))
        XCTAssertTrue(SparkleUpdateController.shouldTreatInstallationErrorAsSuccess(
            state: .installing(version: "0.12.12"),
            error: wrapped,
            currentVersion: "0.12.12"
        ))
        // Failure reason carries the text as well.
        let reasoned = NSError(
            domain: "SUSparkleErrorDomain",
            code: 4005,
            userInfo: [NSLocalizedFailureReasonErrorKey: "REMOTE PORT CONNECTION WAS INVALIDATED"]
        )
        XCTAssertTrue(SparkleUpdateController.shouldTreatInstallationErrorAsSuccess(
            state: .installing(version: "0.12.12"),
            error: reasoned,
            currentVersion: "0.12.12"
        ))
    }

    @MainActor
    func testBenignLatchPreventsSecondFailure() {
        let controller = SparkleUpdateController(
            currentVersion: "0.12.12",
            activationPolicySetter: { _ in true },
            appActivator: {},
            menuPanelDismisser: {},
            deferredRunner: { work in work() },
            isAppActive: { true },
            startUpdater: false
        )
        controller.seedStateForTests(.installing(version: "0.12.12"))
        let remotePortError = NSError(
            domain: "SUSparkleErrorDomain",
            code: 4005,
            userInfo: [NSLocalizedDescriptionKey: "The remote port connection was invalidated from the updater."]
        )
        controller.handleAbort(error: remotePortError)
        XCTAssertTrue(controller.benignInstallationSuccessLatched)
        XCTAssertEqual(controller.state, .idle)
        // The following finish with the same error must not fail; the latch
        // covers the state change to .idle that would otherwise lose the
        // .installing context.
        controller.handleFinish(error: remotePortError)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(controller.benignInstallationSuccessLatched)
    }

    @MainActor
    func testWillInstallUpdateOnQuitSetsReadyToInstallWithoutNotification() {
        let controller = SparkleUpdateController(
            currentVersion: "0.12.12",
            activationPolicySetter: { _ in true },
            appActivator: {},
            menuPanelDismisser: {},
            deferredRunner: { work in work() },
            isAppActive: { true },
            startUpdater: false
        )
        var notifications = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .apm44WillInstallUpdate,
            object: nil,
            queue: nil
        ) { _ in notifications += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        controller.handleWillInstallUpdateOnQuit(versionString: "0.12.13")
        XCTAssertEqual(controller.state, .readyToInstall(version: "0.12.13"))
        XCTAssertEqual(notifications, 0)
    }

    @MainActor
    func testDidExtractBringsUIToFrontTwice() {
        var policies: [NSApplication.ActivationPolicy] = []
        var activations = 0
        var dismissals = 0
        let controller = SparkleUpdateController(
            currentVersion: "0.12.12",
            activationPolicySetter: { policy in policies.append(policy); return true },
            appActivator: { activations += 1 },
            menuPanelDismisser: { dismissals += 1 },
            deferredRunner: { work in work() },
            isAppActive: { true },
            startUpdater: false
        )
        controller.handleDidExtract()
        XCTAssertEqual(policies, [.regular, .regular])
        XCTAssertEqual(activations, 2)
        XCTAssertEqual(dismissals, 2)
    }

    @MainActor
    func testActivationPolicyTransitionsWithInjectedClosures() {
        var policies: [NSApplication.ActivationPolicy] = []
        var activations = 0
        var dismissals = 0
        let coordinator = UpdateActivationCoordinator(
            activationPolicySetter: { policies.append($0); return true },
            appActivator: { activations += 1 },
            panelDismisser: { dismissals += 1 },
            deferredRunner: { work in work() },
            isAppActive: { true }
        )
        coordinator.bringUpdateUIToFront()
        coordinator.willFinishUpdateSession()
        XCTAssertEqual(policies, [.regular, .accessory])
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(dismissals, 1)
    }

    @MainActor
    func testWillFinishUpdateSessionAloneDoesNotChangePolicy() {
        var policies: [NSApplication.ActivationPolicy] = []
        let coordinator = UpdateActivationCoordinator(
            activationPolicySetter: { policies.append($0); return true },
            appActivator: {},
            panelDismisser: {},
            deferredRunner: { work in work() },
            isAppActive: { true }
        )
        coordinator.willFinishUpdateSession()
        XCTAssertTrue(policies.isEmpty)
    }

    @MainActor
    func testAccessoryRestoreFailureRetriesOnce() {
        var policies: [NSApplication.ActivationPolicy] = []
        var calls = 0
        let coordinator = UpdateActivationCoordinator(
            activationPolicySetter: { policy in
                policies.append(policy)
                calls += 1
                // First restore fails, the scheduled retry succeeds.
                return calls != 2
            },
            appActivator: {},
            panelDismisser: {},
            deferredRunner: { work in work() },
            isAppActive: { true }
        )
        coordinator.bringUpdateUIToFront()
        coordinator.willFinishUpdateSession()
        XCTAssertEqual(policies, [.regular, .accessory, .accessory])
    }

    @MainActor
    func testExtractionActivatesImmediatelyAndDeferred() {
        var activations = 0
        var deferredCalls = 0
        let coordinator = UpdateActivationCoordinator(
            activationPolicySetter: { _ in true },
            appActivator: { activations += 1 },
            panelDismisser: {},
            deferredRunner: { work in
                deferredCalls += 1
                work()
            },
            isAppActive: { true }
        )
        coordinator.bringUpdateUIToFrontAfterExtraction()
        XCTAssertEqual(activations, 2)
        XCTAssertEqual(deferredCalls, 1)
    }

    func testNewUpdateStringsArePresent() {
        XCTAssertFalse(AppStrings.tryAgain.isEmpty)
        XCTAssertFalse(AppStrings.updateDownloadInterrupted.isEmpty)
        XCTAssertTrue(AppStrings.installUpdateAndRelaunch("0.12.12").contains("0.12.12"))
        XCTAssertTrue(AppStrings.updateDownloadFailed(detail: "boom").contains("boom"))
    }

    @MainActor
    func testBringToFrontRequestsAttentionWhenInactive() {
        var requests = 0
        var cancels: [Int] = []
        let coordinator = UpdateActivationCoordinator(
            activationPolicySetter: { _ in true },
            appActivator: {},
            panelDismisser: {},
            deferredRunner: { work in work() },
            isAppActive: { false },
            attentionRequester: { requests += 1; return 42 },
            attentionCanceller: { cancels.append($0) }
        )
        coordinator.bringUpdateUIToFront()
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(cancels.isEmpty)
    }

    @MainActor
    func testBringToFrontDoesNotRequestWhenActive() {
        var requests = 0
        let coordinator = UpdateActivationCoordinator(
            activationPolicySetter: { _ in true },
            appActivator: {},
            panelDismisser: {},
            deferredRunner: { work in work() },
            isAppActive: { true },
            attentionRequester: { requests += 1; return 1 },
            attentionCanceller: { _ in }
        )
        coordinator.bringUpdateUIToFront()
        XCTAssertEqual(requests, 0)
    }

    @MainActor
    func testFinishCancelsOutstandingAttentionRequest() {
        var requests = 0
        var cancels: [Int] = []
        let coordinator = UpdateActivationCoordinator(
            activationPolicySetter: { _ in true },
            appActivator: {},
            panelDismisser: {},
            deferredRunner: { work in work() },
            isAppActive: { false },
            attentionRequester: { requests += 1; return 42 },
            attentionCanceller: { cancels.append($0) }
        )
        coordinator.bringUpdateUIToFront()
        XCTAssertEqual(requests, 1)
        coordinator.willFinishUpdateSession()
        XCTAssertEqual(cancels, [42])
    }

    @MainActor
    func testSecondBringDoesNotStackAttentionRequests() {
        var requests = 0
        var cancels: [Int] = []
        let coordinator = UpdateActivationCoordinator(
            activationPolicySetter: { _ in true },
            appActivator: {},
            panelDismisser: {},
            deferredRunner: { work in work() },
            isAppActive: { false },
            attentionRequester: { requests += 1; return 7 },
            attentionCanceller: { cancels.append($0) }
        )
        coordinator.bringUpdateUIToFront()
        coordinator.bringUpdateUIToFront()
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(cancels.isEmpty)
    }

    @MainActor
    func testBecomeActiveCancelsOutstandingAttentionRequest() {
        var requests = 0
        var cancels: [Int] = []
        let coordinator = UpdateActivationCoordinator(
            activationPolicySetter: { _ in true },
            appActivator: {},
            panelDismisser: {},
            deferredRunner: { work in work() },
            isAppActive: { false },
            attentionRequester: { requests += 1; return 7 },
            attentionCanceller: { cancels.append($0) }
        )
        coordinator.bringUpdateUIToFront()
        XCTAssertEqual(requests, 1)
        coordinator.handleAppDidBecomeActive()
        XCTAssertEqual(cancels, [7])
    }
}
