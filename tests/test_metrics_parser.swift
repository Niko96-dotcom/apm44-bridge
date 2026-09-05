import XCTest
@testable import APM44Bridge

final class MetricsParserTests: XCTestCase {
    private let fixtureLine =
        #"{"fill_ms":15.200,"ratio":1.08843537,"ppm":12.00,"underruns":0,"overruns":0,"xruns":0,"estimated_rt_ms":17.700,"target_fill_ms":15.000,"src_quality":"medium"}"#

    func testValidLineDecodes() {
        let snapshot = MetricsParser.parse(line: fixtureLine)
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.fillMs ?? 0, 15.2, accuracy: 0.01)
        XCTAssertGreaterThan(snapshot?.estimatedRtMs ?? 0, 0)
    }

    func testMalformedLineReturnsNil() {
        XCTAssertNil(MetricsParser.parse(line: "not json"))
    }

    func testBridgeBufferingLabelFormat() {
        let snapshot = MetricsParser.parse(line: fixtureLine)!
        XCTAssertTrue(snapshot.bridgeBufferingLabel.hasPrefix("~"))
        XCTAssertTrue(snapshot.bridgeBufferingLabel.contains("bridge buffering"))
        XCTAssertFalse(snapshot.bridgeBufferingLabel.contains("monitoring latency"))
        XCTAssertFalse(snapshot.bridgeBufferingLabel.contains("0 ms"))
    }

    func testRecoveriesDecodeSeparatelyFromHardXruns() {
        let line = #"{"fill_ms":30.100,"ratio":1.08843537,"ppm":120.00,"underruns":7,"overruns":0,"xruns":0,"estimated_rt_ms":32.600,"target_fill_ms":30.000,"src_quality":"best"}"#
        let snapshot = MetricsParser.parse(line: line)
        XCTAssertEqual(snapshot?.underruns, 7)
        XCTAssertEqual(snapshot?.xruns, 0)
    }

    func testKnownFrameLossCountersDecodeAndAggregate() {
        let line = #"{"fill_ms":30.100,"ratio":1.08843537,"ppm":120.00,"underruns":7,"overruns":1,"xruns":2,"input_dropped_frames":11,"producer_overrun_events":2,"producer_dropped_frames":13,"producer_not_ready_dropped_frames":3,"lane_queue_drops":5,"lane_timestamp_mismatches":7,"lane_frame_mismatch_dropped_frames":17,"consumer_resets":19,"output_starvation_frames":23,"partial_shortage_events":29,"converter_reset_events":31,"rebuffer_events":37,"recovery_fade_events":41,"estimated_rt_ms":32.600,"target_fill_ms":30.000,"src_quality":"best"}"#
        let snapshot = MetricsParser.parse(line: line)
        XCTAssertEqual(snapshot?.producerDroppedFrames, 13)
        XCTAssertEqual(snapshot?.outputStarvationFrames, 23)
        XCTAssertEqual(snapshot?.partialShortageEvents, 29)
        XCTAssertEqual(snapshot?.converterResetEvents, 31)
        XCTAssertEqual(snapshot?.rebufferEvents, 37)
        XCTAssertEqual(snapshot?.recoveryFadeEvents, 41)
        XCTAssertEqual(snapshot?.knownFrameLoss, 47)
    }

    func testOlderMetricsPayloadDefaultsNewCountersToZero() {
        let snapshot = MetricsParser.parse(line: fixtureLine)
        XCTAssertEqual(snapshot?.knownFrameLoss, 0)
        XCTAssertEqual(snapshot?.producerOverrunEvents, 0)
        XCTAssertEqual(snapshot?.partialShortageEvents, 0)
        XCTAssertEqual(snapshot?.converterResetEvents, 0)
        XCTAssertEqual(snapshot?.rebufferEvents, 0)
        XCTAssertEqual(snapshot?.recoveryFadeEvents, 0)
    }
}
