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

    func testParsesSelectedEndpointFingerprintFields() {
        let text = """
        UID\tNAME\tRATE\tI/O\tALIVE\tOUTPUT_CHANNELS\tBUFFER_FRAMES\tTRANSPORT\tFORMAT_ID\tFORMAT_BITS\tSUPPORTS_48000\tFLOAT32_STEREO
        USB-UID\tUSB Headphones\t48000\tO\t1\t2\t512\t1970496032\t1819304813\t32\t1\t1
        """

        let row = DeviceCatalog.parseListDevicesOutput(text).first

        XCTAssertEqual(row?.uid, "USB-UID")
        XCTAssertEqual(row?.outputChannels, 2)
        XCTAssertEqual(row?.bufferFrameSize, 512)
        XCTAssertEqual(row?.transportType, 1_970_496_032)
        XCTAssertEqual(row?.outputFormatId, 1_819_304_813)
        XCTAssertEqual(row?.outputFormatBits, 32)
        XCTAssertEqual(row?.isAlive, true)
        XCTAssertEqual(row?.supports48000, true)
        XCTAssertEqual(row?.transportLabel, "USB")
        XCTAssertEqual(row?.isMonitoringCompatible, true)
    }

    func testPreferredDefaultPicksCompatibleUSBAirPodsOverBluetooth() {
        let bluetooth = AudioDeviceRow(
            uid: "BT",
            name: "AirPods Max",
            nominalRate: 48_000,
            hasInput: false,
            hasOutput: true,
            transportType: 1_651_275_109
        )
        let usb = AudioDeviceRow(
            uid: "USB",
            name: "AirPods Max",
            nominalRate: 48_000,
            hasInput: false,
            hasOutput: true,
            transportType: 1_970_496_032
        )

        XCTAssertEqual(DeviceCatalog.preferredDefault(from: [bluetooth, usb])?.uid, "USB")
        let rows = DeviceCatalog.parseListDevicesOutput(fixture)
        XCTAssertEqual(DeviceCatalog.preferredDefault(from: rows)?.uid, "AP-UID")
    }

    func testStreamTheHelperRefusesIsNotReady() {
        // 32-bit integer stereo and a single 8-channel float stream both
        // report LPCM/32 bits; only the helper's layout check tells them apart.
        let text = """
        UID\tNAME\tRATE\tI/O\tALIVE\tOUTPUT_CHANNELS\tBUFFER_FRAMES\tTRANSPORT\tFORMAT_ID\tFORMAT_BITS\tSUPPORTS_48000\tFLOAT32_STEREO
        INT-UID\tInteger DAC\t48000\tO\t1\t2\t512\t1970496032\t1819304813\t32\t1\t0
        MULTI-UID\tEight Channel\t48000\tO\t1\t8\t512\t1970496032\t1819304813\t32\t1\t0
        """

        let rows = DeviceCatalog.parseListDevicesOutput(text)

        XCTAssertEqual(rows.count, 2)
        for row in rows {
            XCTAssertFalse(row.isMonitoringCompatible, row.uid)
            XCTAssertEqual(row.compatibilityIssue, "A 32-bit float stereo stream is required")
        }
        XCTAssertNil(DeviceCatalog.preferredDefault(from: rows))
    }

    func testIncompatibleOutputRemainsVisibleButCannotBeStarted() {
        let unsupported = AudioDeviceRow(
            uid: "MONO",
            name: "Mono Output",
            nominalRate: 44_100,
            hasInput: false,
            hasOutput: true,
            outputChannels: 1,
            supports48000: false
        )

        XCTAssertEqual(DeviceCatalog.filterMonitoringOutputs([unsupported]), [unsupported])
        XCTAssertFalse(unsupported.isMonitoringCompatible)
        XCTAssertTrue(unsupported.pickerLabel.contains(AppStrings.unsupportedPrefix))
        XCTAssertNil(DeviceCatalog.preferredDefault(from: [unsupported]))
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
        let blackHole = AudioDeviceRow(
            uid: "BH-UID",
            name: "BlackHole 2ch",
            nominalRate: 44_100,
            hasInput: true,
            hasOutput: true
        )
        let apm44Bridge = AudioDeviceRow(
            uid: "APM44-OUT",
            name: "APM44 Bridge",
            nominalRate: 48_000,
            hasInput: false,
            hasOutput: true
        )
        XCTAssertTrue(DeviceCatalog.filterMonitoringOutputs([blackHole]).isEmpty)
        XCTAssertTrue(DeviceCatalog.filterMonitoringOutputs([apm44Bridge]).isEmpty)
        let filtered = DeviceCatalog.filterMonitoringOutputs([airpods, usb])
        XCTAssertEqual(filtered.count, 2)
    }

    private func makeListingHelper(_ body: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("apm44-listing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("apm44-bridge")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func testRefreshTimesOutWhenTheHelperHoldsStdoutOpen() throws {
        let wedged = try makeListingHelper("exec /bin/sleep 30")
        let started = Date()

        XCTAssertThrowsError(try DeviceCatalog.refresh(binaryURL: wedged, timeout: 0.5)) { error in
            XCTAssertEqual((error as NSError).code, Int(ETIMEDOUT))
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)

        // A later refresh still works once the helper answers.
        let healthy = try makeListingHelper(
            "printf 'UID\\tNAME\\tRATE\\tI/O\\nAP-UID\\tAirPods Max\\t48000\\tO\\n'"
        )
        let rows = try DeviceCatalog.refresh(binaryURL: healthy, timeout: 5)
        XCTAssertEqual(rows.map(\.uid), ["AP-UID"])
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
