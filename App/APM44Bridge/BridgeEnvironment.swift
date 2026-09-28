import Foundation

/// Injected retry, stability, stale-metrics and glitch-flash timing for
/// BridgeProcessManager. Production uses `.live`.
struct BridgeTiming: Equatable, Sendable {
    var retryDelays: [TimeInterval]
    var stabilityWindow: TimeInterval
    var staleCheckInterval: TimeInterval = 0.5
    var staleAfter: TimeInterval = 2.0
    var glitchFlashDuration: TimeInterval = 2.0
    var stopTimeout: TimeInterval = 5.0

    static let live = BridgeTiming(
        retryDelays: [1.0, 2.0, 4.0, 4.0],
        stabilityWindow: 15.0,
        staleCheckInterval: 0.5,
        staleAfter: 2.0,
        glitchFlashDuration: 2.0,
        stopTimeout: 5.0
    )
}

/// Injectable wall-clock for BridgeProcessManager's time-based UI state
/// (the stale-metrics watch). Production uses `LiveBridgeClock`.
protocol BridgeClock: Sendable {
    func now() -> Date
}

struct LiveBridgeClock: BridgeClock {
    func now() -> Date { Date() }
}

/// Injectable HAL build check. When the HAL virtual device is enumerated,
/// the installed driver build ID must equal the app's full build ID.
struct HalBuildCheck: Equatable, Sendable {
    var halPresent: Bool
    var appBuildID: String?
    var driverBuildID: String?
}

/// Device/HAL reads for BridgeProcessManager. Called from `Task.detached`
/// during device refresh, so conformers must be `Sendable`.
protocol BridgeDeviceSource: Sendable {
    func halBuildCheck() -> HalBuildCheck
    func listDevices(binaryURL: URL) throws -> [AudioDeviceRow]
}

/// Live device source: Core Audio HAL enumeration plus the two small
/// Info.plists for the build gate, and `DeviceCatalog.refresh` for listing.
struct LiveBridgeDeviceSource: BridgeDeviceSource {
    func halBuildCheck() -> HalBuildCheck {
        HalBuildCheck(
            halPresent: HalDriverDetector.isHalInstalled(),
            appBuildID: HalDriverDetector.appBuildID(),
            driverBuildID: HalDriverDetector.driverBuildID()
        )
    }

    func listDevices(binaryURL: URL) throws -> [AudioDeviceRow] {
        try DeviceCatalog.refresh(binaryURL: binaryURL)
    }
}
