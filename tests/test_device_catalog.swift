import XCTest
@testable import APM44Bridge

final class DeviceCatalogTests: XCTestCase {
    private let fixture = """
    UID\tNAME\tRATE\tI/O
    BH-UID\tBlackHole 2ch\t44100\tIO
    AP-UID\tAirPods Max\t48000\tO
    MIC-UID\tBuilt-in Mic\t48000\tI
    """

    func testParsesOutputsOnly() {
        let rows = DeviceCatalog.parseListDevicesOutput(fixture)
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.contains { $0.uid == "AP-UID" })
        XCTAssertTrue(rows.contains { $0.uid == "BH-UID" })
        XCTAssertFalse(rows.contains { $0.uid == "MIC-UID" })
    }

    func testPreferredDefaultPicksAirPods() {
        let rows = DeviceCatalog.parseListDevicesOutput(fixture)
        XCTAssertEqual(DeviceCatalog.preferredDefault(from: rows)?.uid, "AP-UID")
    }
}
