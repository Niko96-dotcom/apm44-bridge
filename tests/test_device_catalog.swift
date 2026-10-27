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
            XCTAssertEqual(row.compatibilityIssue, .float32StereoStreamRequired)
        }
        XCTAssertNil(DeviceCatalog.preferredDefault(from: rows))
    }

    func testCompatibilityIssuesAreReportedInCheckOrder() {
        func row(
            alive: Bool = true, output: Bool = true, channels: Int = 2, supports48000: Bool = true,
            rate: Double = 48_000, formatId: UInt32 = 0, bits: Int = 0, float32Stereo: Bool = true
        ) -> AudioDeviceRow {
            AudioDeviceRow(
                uid: "U", name: "N", nominalRate: rate, hasInput: false, hasOutput: output,
                isAlive: alive, outputChannels: channels, outputFormatId: formatId,
                outputFormatBits: bits, supports48000: supports48000,
                outputFloat32Stereo: float32Stereo
            )
        }
        XCTAssertNil(row().compatibilityIssue)
        XCTAssertEqual(row(alive: false, output: false).compatibilityIssue, .disconnected)
        XCTAssertEqual(row(channels: 1, supports48000: false).compatibilityIssue, .stereoOutputUnavailable)
        XCTAssertEqual(row(output: false).compatibilityIssue, .stereoOutputUnavailable)
        XCTAssertEqual(row(supports48000: false, rate: 44_100).compatibilityIssue, .rate48000Unsupported)
        XCTAssertEqual(row(rate: 44_100, formatId: 1).compatibilityIssue, .currentRateNot48000)
        XCTAssertEqual(row(formatId: 1, bits: 16).compatibilityIssue, .linearPCMRequired)
        XCTAssertEqual(row(formatId: 1_819_304_813, bits: 16).compatibilityIssue, .float32OutputRequired)
        XCTAssertEqual(row(float32Stereo: false).compatibilityIssue, .float32StereoStreamRequired)
        XCTAssertEqual(row(bits: 16, float32Stereo: false).compatibilityIssue, .float32OutputRequired)
    }

    /// The strings are read through the app bundle at run time. The keys, the
    /// English defaults and the German text are pinned here. Two checks catch
    /// two different mistakes:
    /// - The de.lproj lookup with the pinned key fails when a translation is
    ///   lost or a key in Localizable.strings changes.
    /// - The rendered text of AppStrings is compared with the pinned text of the
    ///   active localization. A key typo in AppStrings makes a German-hosted run
    ///   render the English default instead of the pinned German text, and an
    ///   English-hosted run proves the English defaults.
    func testEveryCompatibilityIssueHasEnglishTextAndAGermanTranslation() throws {
        let expected: [(OutputCompatibilityIssue, key: String, english: String, german: String)] = [
            (.disconnected, "compat_disconnected", "Disconnected", "Getrennt"),
            (.stereoOutputUnavailable, "compat_stereo_output_unavailable",
             "Stereo output unavailable", "Stereoausgabe nicht verfügbar"),
            (.rate48000Unsupported, "compat_rate_48000_unsupported",
             "48 kHz is not supported", "48 kHz wird nicht unterstützt"),
            (.currentRateNot48000, "compat_current_rate_not_48000",
             "Set the current rate to 48 kHz", "Aktuelle Rate auf 48 kHz stellen"),
            (.linearPCMRequired, "compat_linear_pcm_required",
             "Linear PCM output is required", "Linear-PCM-Ausgabe erforderlich"),
            (.float32OutputRequired, "compat_float32_output_required",
             "32-bit float output is required", "32-Bit-Float-Ausgabe erforderlich"),
            (.float32StereoStreamRequired, "compat_float32_stereo_stream_required",
             "A 32-bit float stereo stream is required", "Stereo-Stream mit 32-Bit-Float erforderlich"),
        ]
        XCTAssertEqual(expected.count, OutputCompatibilityIssue.allCases.count)
        XCTAssertEqual(Set(expected.map(\.key)).count, expected.count, "keys must be unique")

        let germanPath = try XCTUnwrap(Bundle.main.path(forResource: "de", ofType: "lproj"))
        let german = try XCTUnwrap(Bundle(path: germanPath))
        let missing = "\u{0}missing"
        let germanUI = Bundle.main.preferredLocalizations.first == "de"
        for issue in OutputCompatibilityIssue.allCases {
            let entry = try XCTUnwrap(expected.first { $0.0 == issue }, "\(issue)")
            let text = AppStrings.compatibility(issue)
            XCTAssertFalse(text.isEmpty, "\(issue)")
            XCTAssertEqual(text, germanUI ? entry.german : entry.english, "rendered text for \(issue)")
            XCTAssertEqual(
                german.localizedString(forKey: entry.key, value: missing, table: "Localizable"),
                entry.german,
                "German entry for \(entry.key)"
            )
        }
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

    /// Runs `refresh` off the test thread so a broken drain or missing
    /// termination fails at a bounded watchdog instead of hanging the suite.
    /// On watchdog expiry it signals only the fixture process it created.
    private func runRefresh(
        helper: URL,
        pidFile: URL,
        timeout: TimeInterval,
        watchdog: TimeInterval = 10
    ) -> (result: Result<[AudioDeviceRow], Error>, elapsed: TimeInterval)? {
        let box = RefreshOutcome()
        let done = DispatchSemaphore(value: 0)
        let started = Date()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                box.set(.success(try DeviceCatalog.refresh(binaryURL: helper, timeout: timeout)))
            } catch {
                box.set(.failure(error))
            }
            done.signal()
        }
        guard done.wait(timeout: .now() + watchdog) == .success else {
            if let pid = fixturePID(pidFile) { kill(pid, SIGKILL) }
            XCTFail("DeviceCatalog.refresh did not return within \(watchdog) s")
            _ = done.wait(timeout: .now() + 5)
            return nil
        }
        guard let result = box.value else { return nil }
        return (result, Date().timeIntervalSince(started))
    }

    private func fixturePID(_ pidFile: URL) -> pid_t? {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8) else { return nil }
        return pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// A helper script that records its own PID in a file the test owns,
    /// then runs `body`. `exec` in the body keeps the recorded PID.
    private func makePIDRecordingHelper(_ body: String) throws -> (helper: URL, pidFile: URL) {
        let pidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("apm44-listing-pid-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: pidFile) }
        let helper = try makeListingHelper("echo $$ > '\(pidFile.path)'\n\(body)")
        return (helper, pidFile)
    }

    private func awaitProcessGone(_ pid: pid_t, within seconds: TimeInterval = 2) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if kill(pid, 0) == -1 && errno == ESRCH { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return kill(pid, 0) == -1 && errno == ESRCH
    }

    func testRefreshTimesOutWhenTheHelperHoldsStdoutOpen() throws {
        let (wedged, pidFile) = try makePIDRecordingHelper("exec /bin/sleep 30")

        let outcome = try XCTUnwrap(runRefresh(helper: wedged, pidFile: pidFile, timeout: 0.5, watchdog: 8))

        guard case .failure(let error) = outcome.result else {
            return XCTFail("a wedged helper must fail the refresh")
        }
        XCTAssertEqual((error as NSError).code, Int(ETIMEDOUT))
        XCTAssertLessThan(outcome.elapsed, 5)

        // The timed-out child was terminated and reaped, not left running or zombie.
        let pid = try XCTUnwrap(fixturePID(pidFile))
        XCTAssertTrue(awaitProcessGone(pid), "timed-out helper \(pid) still exists")

        // A later refresh still works once the helper answers.
        let healthy = try makeListingHelper(
            "printf 'UID\\tNAME\\tRATE\\tI/O\\nAP-UID\\tAirPods Max\\t48000\\tO\\n'"
        )
        let rows = try DeviceCatalog.refresh(binaryURL: healthy, timeout: 5)
        XCTAssertEqual(rows.map(\.uid), ["AP-UID"])
    }

    private static let manyRowsScript = """
    awk 'BEGIN { print "UID\\tNAME\\tRATE\\tI/O"; \
      for (i = 0; i < 8000; i++) printf "UID-%d\\tDevice %d\\t48000\\tO\\n", i, i }'
    """

    func testRefreshReturnsEveryRowWhenStdoutExceedsThePipeBuffer() throws {
        let (helper, pidFile) = try makePIDRecordingHelper(Self.manyRowsScript)

        let outcome = try XCTUnwrap(runRefresh(helper: helper, pidFile: pidFile, timeout: 4))

        guard case .success(let rows) = outcome.result else {
            return XCTFail("large stdout must not fail the refresh: \(outcome.result)")
        }
        // Output is ~250 KB, several times the ~64 KiB pipe capacity.
        XCTAssertEqual(rows.count, 8000)
        XCTAssertEqual(Set(rows.map(\.uid)).count, 8000)
        XCTAssertLessThan(outcome.elapsed, 3)
    }

    func testRefreshCompletesWhenTheHelperWritesLargeStderr() throws {
        // 1 MiB on stderr before and after the rows: a stderr pipe nobody
        // reads would block the child long before it printed its listing.
        let (helper, pidFile) = try makePIDRecordingHelper(
            "head -c 1048576 /dev/zero >&2\n\(Self.manyRowsScript)\nhead -c 1048576 /dev/zero >&2"
        )

        let outcome = try XCTUnwrap(runRefresh(helper: helper, pidFile: pidFile, timeout: 4))

        guard case .success(let rows) = outcome.result else {
            return XCTFail("large stderr must not fail the refresh: \(outcome.result)")
        }
        XCTAssertEqual(rows.count, 8000)
        XCTAssertLessThan(outcome.elapsed, 3)
    }

    func testRefreshReportsTheHelperExitStatusEvenWithLargeOutput() throws {
        let (helper, pidFile) = try makePIDRecordingHelper(
            "head -c 1048576 /dev/zero >&2\n\(Self.manyRowsScript)\nexit 7"
        )

        let outcome = try XCTUnwrap(runRefresh(helper: helper, pidFile: pidFile, timeout: 4))

        guard case .failure(let error) = outcome.result else {
            return XCTFail("a nonzero exit must fail the refresh")
        }
        let nsError = error as NSError
        XCTAssertEqual(nsError.domain, "DeviceCatalog")
        XCTAssertEqual(nsError.code, 7)
        XCTAssertLessThan(outcome.elapsed, 3)
    }

    func testRefreshMapsANonzeroExitWithoutOutputToItsStatus() throws {
        let (helper, pidFile) = try makePIDRecordingHelper("echo 'device query failed' >&2\nexit 3")

        let outcome = try XCTUnwrap(runRefresh(helper: helper, pidFile: pidFile, timeout: 4))

        guard case .failure(let error) = outcome.result else {
            return XCTFail("a nonzero exit must fail the refresh")
        }
        XCTAssertEqual((error as NSError).domain, "DeviceCatalog")
        XCTAssertEqual((error as NSError).code, 3)
    }
}

private final class RefreshOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<[AudioDeviceRow], Error>?

    func set(_ result: Result<[AudioDeviceRow], Error>) {
        lock.lock()
        stored = result
        lock.unlock()
    }

    var value: Result<[AudioDeviceRow], Error>? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
