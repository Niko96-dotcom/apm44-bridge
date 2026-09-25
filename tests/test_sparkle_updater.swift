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
        let allowed: [AppUpdateState] = [.idle, .available(version: "1.0"), .cancelled, .failed(message: "x")]
        for state in allowed {
            XCTAssertTrue(SparkleUpdateController.canStartManualCheck(canCheckForUpdates: true, state: state), "\(state)")
            XCTAssertFalse(SparkleUpdateController.canStartManualCheck(canCheckForUpdates: false, state: state), "\(state)")
        }
        let busy: [AppUpdateState] = [.checking, .readyToInstall(version: "1.0"), .installing(version: "1.0")]
        for state in busy {
            XCTAssertFalse(SparkleUpdateController.canStartManualCheck(canCheckForUpdates: true, state: state), "\(state)")
        }
    }
}
