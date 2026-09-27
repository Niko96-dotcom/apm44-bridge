import Foundation
import XCTest
@testable import APM44Bridge

final class UpdateErrorPolicyTests: XCTestCase {
    private func wrapped(leaf: NSError, wrappers: Int) -> NSError {
        var current: Error = leaf
        for index in 0..<wrappers {
            current = NSError(
                domain: "com.example.wrapper",
                code: 9000 + index,
                userInfo: [
                    NSLocalizedDescriptionKey: "wrapper \(index)",
                    NSUnderlyingErrorKey: current,
                ]
            )
        }
        return current as NSError
    }

    func testIsDownloadFailureTopLevel2001() {
        let top = NSError(
            domain: "SUSparkleErrorDomain",
            code: 2001,
            userInfo: [NSLocalizedDescriptionKey: "download failed"]
        )
        XCTAssertTrue(SparkleUpdateController.isDownloadFailure(top))
    }

    func testIsDownloadFailureNestedThreeDeep() {
        let leaf = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut,
            userInfo: [NSLocalizedDescriptionKey: "timed out"]
        )
        XCTAssertTrue(SparkleUpdateController.isDownloadFailure(wrapped(leaf: leaf, wrappers: 3)))
    }

    func testIsDownloadFailureDepthBound() {
        let leaf = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut,
            userInfo: [NSLocalizedDescriptionKey: "timed out"]
        )
        // Depth 0...9 are examined (at most 10 errors): leaf at index 9 is found.
        XCTAssertTrue(SparkleUpdateController.isDownloadFailure(wrapped(leaf: leaf, wrappers: 9)))
        // Leaf at index 10 falls outside the old loop's bound.
        XCTAssertFalse(SparkleUpdateController.isDownloadFailure(wrapped(leaf: leaf, wrappers: 10)))
    }

    func testIsDownloadFailureUnrelatedDomain() {
        let other = NSError(
            domain: "com.example.other",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "something else"]
        )
        XCTAssertFalse(SparkleUpdateController.isDownloadFailure(other))
    }

    func testIsNetworkInterruptionCodes() {
        for code in [-1001, -1003, -1004, -1005, -1009, -1018, -1020] {
            let error = NSError(
                domain: NSURLErrorDomain,
                code: code,
                userInfo: [NSLocalizedDescriptionKey: "interrupted"]
            )
            XCTAssertTrue(SparkleUpdateController.isNetworkInterruptionError(error), "code \(code)")
        }
    }

    func testIsNetworkInterruptionRejectsOtherCode() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: -1011,
            userInfo: [NSLocalizedDescriptionKey: "bad server response"]
        )
        XCTAssertFalse(SparkleUpdateController.isNetworkInterruptionError(error))
    }

    func testSharedPrefixMatchesBothMessages() {
        let noUpdate = NSError(
            domain: "SUSparkleErrorDomain",
            code: 1001,
            userInfo: [NSLocalizedDescriptionKey: "You are up to date!"]
        )
        XCTAssertEqual(SparkleUpdateController.downloadErrorMessage(noUpdate), AppStrings.noUpdateAvailable)
        XCTAssertEqual(SparkleUpdateController.userFacingErrorMessage(noUpdate), AppStrings.noUpdateAvailable)

        let signature = NSError(
            domain: "SUSparkleErrorDomain",
            code: 3001,
            userInfo: [NSLocalizedDescriptionKey: "invalid EdDSA signature"]
        )
        XCTAssertEqual(SparkleUpdateController.downloadErrorMessage(signature), AppStrings.updateFeedUnverified)
        XCTAssertEqual(SparkleUpdateController.userFacingErrorMessage(signature), AppStrings.updateFeedUnverified)

        let cancelled = NSError(
            domain: "SUSparkleErrorDomain",
            code: 4007,
            userInfo: [NSLocalizedDescriptionKey: "Update cancelled before authorization password step"]
        )
        XCTAssertEqual(
            SparkleUpdateController.downloadErrorMessage(cancelled),
            AppStrings.updateCancelledBeforeReplace
        )
        XCTAssertEqual(
            SparkleUpdateController.userFacingErrorMessage(cancelled),
            AppStrings.updateCancelledBeforeReplace
        )
    }

    func testEmptyDescriptionDiffers() {
        let empty = NSError(
            domain: "com.example.empty",
            code: 999,
            userInfo: [NSLocalizedDescriptionKey: ""]
        )
        XCTAssertEqual(
            SparkleUpdateController.downloadErrorMessage(empty),
            AppStrings.updateDownloadFailed(detail: "com.example.empty (999)")
        )
        XCTAssertEqual(
            SparkleUpdateController.userFacingErrorMessage(empty),
            AppStrings.updateCheckFailedRetry
        )
    }
}
