import XCTest
@testable import APM44Bridge

final class MetricsParserTests: XCTestCase {
    func testValidLineDecodes() {
        let snapshot = MetricsParser.parse(line: MetricsParser.fixtureLine)
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.fillMs ?? 0, 15.2, accuracy: 0.01)
        XCTAssertGreaterThan(snapshot?.estimatedRtMs ?? 0, 0)
    }

    func testMalformedLineReturnsNil() {
        XCTAssertNil(MetricsParser.parse(line: "not json"))
    }

    func testLatencyLabelFormat() {
        let snapshot = MetricsParser.parse(line: MetricsParser.fixtureLine)!
        XCTAssertTrue(snapshot.latencyLabel.hasPrefix("~"))
        XCTAssertTrue(snapshot.latencyLabel.contains("monitoring latency"))
        XCTAssertFalse(snapshot.latencyLabel.contains("0 ms"))
    }
}
