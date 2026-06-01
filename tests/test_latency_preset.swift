import XCTest
@testable import APM44Bridge

final class LatencyPresetTests: XCTestCase {
    func testTargetFillValues() {
        XCTAssertEqual(LatencyPreset.balanced.targetFillMs, 15)
        XCTAssertEqual(LatencyPreset.low.targetFillMs, 8)
        XCTAssertEqual(LatencyPreset.safe.targetFillMs, 30)
    }

    func testDefaultSrcQuality() {
        XCTAssertEqual(LatencyPreset.balanced.defaultSrcQuality, .medium)
        XCTAssertEqual(LatencyPreset.safe.defaultSrcQuality, .best)
    }

    func testCliFlags() {
        XCTAssertEqual(SrcQuality.medium.cliArgument, "medium")
        XCTAssertEqual(SrcQuality.high.cliArgument, "high")
        XCTAssertEqual(SrcQuality.best.cliArgument, "best")
    }
}
