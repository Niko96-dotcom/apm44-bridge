import Foundation
import XCTest
@testable import APM44Bridge

/// Runs the built helper with `--print-contract` and compares the values it
/// reports with the app's copies, so a value changed on one side only fails.
/// scripts/ci.sh passes the helper path as TEST_RUNNER_APM44_DAEMON_PATH;
/// xcodebuild removes the prefix before the test process sees it.
final class HelperContractTests: XCTestCase {
    private struct Contract: Decodable {
        let exitCodes: [String: Int32]
        let halFillFloorMs: Double
        let deviceUid: String

        enum CodingKeys: String, CodingKey {
            case exitCodes = "exit_codes"
            case halFillFloorMs = "hal_fill_floor_ms"
            case deviceUid = "device_uid"
        }
    }

    /// The helper's name for each exit code. The switch is exhaustive, so a
    /// new app case does not compile until it gets the helper's name.
    private static func contractName(_ code: DaemonExitCode) -> String {
        switch code {
        case .staleShmRing: return "stale_shm_ring"
        case .singletonBusy: return "singleton_busy"
        case .loadedDriverBuildMismatch: return "loaded_driver_build_mismatch"
        }
    }

    func testHelperReportsTheValuesTheAppCopies() throws {
        let contract = try printContract(helper: try helperURL())

        let appExitCodes = Dictionary(
            uniqueKeysWithValues: DaemonExitCode.allCases.map { (Self.contractName($0), $0.rawValue) }
        )
        XCTAssertEqual(contract.exitCodes, appExitCodes)
        XCTAssertEqual(contract.halFillFloorMs, LatencyPreset.halMinimumTargetFillMs)
        XCTAssertEqual(contract.deviceUid, HalDriverDetector.deviceUid)
    }

    private func helperURL() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["APM44_DAEMON_PATH"], !path.isEmpty else {
            if let ci = environment["CI"], !ci.isEmpty {
                XCTFail("APM44_DAEMON_PATH is not set; CI must pass the built helper to this test")
                throw HelperContractError.missingHelperPath
            }
            throw XCTSkip(
                "Set TEST_RUNNER_APM44_DAEMON_PATH to the built apm44-bridge helper "
                    + "when you run xcodebuild test, or run scripts/ci.sh"
            )
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            XCTFail("APM44_DAEMON_PATH is not an executable file: \(path)")
            throw HelperContractError.missingHelperPath
        }
        return URL(fileURLWithPath: path)
    }

    private func printContract(helper: URL) throws -> Contract {
        let process = Process()
        process.executableURL = helper
        process.arguments = ["--print-contract"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationReason, .exit)
        XCTAssertEqual(process.terminationStatus, 0)
        return try JSONDecoder().decode(Contract.self, from: output)
    }
}

private enum HelperContractError: Error {
    case missingHelperPath
}
