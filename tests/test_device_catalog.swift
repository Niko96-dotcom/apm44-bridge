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
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows.contains { $0.uid == "AP-UID" })
        XCTAssertFalse(rows.contains { $0.uid == "BH-UID" })
        XCTAssertFalse(rows.contains { $0.uid == "MIC-UID" })
    }

    func testPreferredDefaultPicksAirPods() {
        let rows = DeviceCatalog.parseListDevicesOutput(fixture)
        XCTAssertEqual(DeviceCatalog.preferredDefault(from: rows)?.uid, "AP-UID")
    }

    func testFilterExcludesBlackHole() {
        let row = AudioDeviceRow(
            uid: "BH-UID",
            name: "BlackHole 2ch",
            nominalRate: 44_100,
            hasInput: true,
            hasOutput: true
        )
        XCTAssertTrue(DeviceCatalog.filterMonitoringOutputs([row]).isEmpty)
    }

    func testFilterExcludesAPM44Bridge() {
        let row = AudioDeviceRow(
            uid: "APM44-OUT",
            name: "APM44 Bridge",
            nominalRate: 48_000,
            hasInput: false,
            hasOutput: true
        )
        XCTAssertTrue(DeviceCatalog.filterMonitoringOutputs([row]).isEmpty)
    }

    func testFilterKeepsPhysicalUSB() {
        let airpods = AudioDeviceRow(
            uid: "AP-UID",
            name: "AirPods Max",
            nominalRate: 48_000,
            hasInput: false,
            hasOutput: true
        )
        let usb = AudioDeviceRow(
            uid: "USB-UID",
            name: "USB Audio",
            nominalRate: 48_000,
            hasInput: false,
            hasOutput: true
        )
        let filtered = DeviceCatalog.filterMonitoringOutputs([airpods, usb])
        XCTAssertEqual(filtered.count, 2)
    }

    func testRefreshDoesNotUseUnreadStderrPipe() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("App/APM44Bridge/DeviceCatalog.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("process.standardError = FileHandle.nullDevice"))
        XCTAssertFalse(source.contains("process.standardError = Pipe()"))
    }
}
