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
            "Update check blocked: the signed update feed could not be verified."
        )

        let unreachableError = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost,
                                       userInfo: [NSLocalizedDescriptionKey: "The server could not be reached"])
        XCTAssertEqual(
            SparkleUpdateController.userFacingErrorMessage(unreachableError),
            "Update check failed: The server could not be reached"
        )
    }

    func testNoUpdateErrorIsRecognizedAsSuccessfulCheck() {
        let noUpdateError = NSError(domain: "SUSparkleErrorDomain", code: 1001,
                                    userInfo: [NSLocalizedDescriptionKey: "You’re up to date!"])
        XCTAssertTrue(SparkleUpdateController.isNoUpdateError(noUpdateError))
        XCTAssertEqual(
            SparkleUpdateController.userFacingErrorMessage(noUpdateError),
            "No update is available."
        )
    }

}
