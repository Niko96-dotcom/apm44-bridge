import XCTest
@testable import APM44Bridge

final class LatencyPresetTests: XCTestCase {
    func testTargetFillValues() {
        XCTAssertEqual(LatencyPreset.balanced.targetFillMs, 15)
        XCTAssertEqual(LatencyPreset.low.targetFillMs, 8)
        XCTAssertEqual(LatencyPreset.safe.targetFillMs, 100)
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

    func testHalEffectiveTargetFill() {
        XCTAssertEqual(LatencyPreset.low.effectiveTargetFillMs(halMode: true), 20)
        XCTAssertEqual(LatencyPreset.balanced.effectiveTargetFillMs(halMode: true), 20)
        XCTAssertEqual(LatencyPreset.safe.effectiveTargetFillMs(halMode: true), 100)
        XCTAssertEqual(LatencyPreset.low.effectiveTargetFillMs(halMode: false), 8)
    }

    func testHalTargetDescription() {
        XCTAssertTrue(LatencyPreset.low.targetDescription(halMode: true).contains("20"))
        XCTAssertTrue(LatencyPreset.low.targetDescription(halMode: true).contains("HAL minimum"))
    }
}
