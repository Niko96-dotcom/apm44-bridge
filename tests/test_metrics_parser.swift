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

    func testRecoveriesDecodeSeparatelyFromHardXruns() {
        let line = #"{"fill_ms":30.100,"ratio":1.08843537,"ppm":120.00,"underruns":7,"overruns":0,"xruns":0,"estimated_rt_ms":32.600,"target_fill_ms":30.000,"src_quality":"best"}"#
        let snapshot = MetricsParser.parse(line: line)
        XCTAssertEqual(snapshot?.underruns, 7)
        XCTAssertEqual(snapshot?.xruns, 0)
    }
}
