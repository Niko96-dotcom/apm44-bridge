import XCTest
@testable import APM44Bridge

final class HalDriverDetectorTests: XCTestCase {
    func testRoutingModeLabels() {
        XCTAssertEqual(RoutingMode.halVirtualDevice.menuLabel, "APM44 Bridge (driver)")
        XCTAssertEqual(RoutingMode.blackHoleFallback.menuLabel, "BlackHole")
    }

    func testConnectionPhaseLabels() {
        XCTAssertEqual(BridgeConnectionPhase.waitingForDAW.label, "Waiting for DAW")
        XCTAssertEqual(BridgeConnectionPhase.connected.label, "Connected")
        XCTAssertEqual(BridgeConnectionPhase.running.label, "Running")
    }

    func testHalDetectorConstants() {
        XCTAssertEqual(HalDriverDetector.deviceUid, "com.niko.apm44.bridge.device")
        XCTAssertEqual(HalDriverDetector.expectedRate, 44100)
    }
}
