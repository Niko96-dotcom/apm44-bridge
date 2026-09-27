import Foundation

/// Injected retry timing for BridgeProcessManager. Production uses `.live`.
struct BridgeRetryTiming: Equatable, Sendable {
    var retryDelays: [TimeInterval]
    var stabilityWindow: TimeInterval

    static let live = BridgeRetryTiming(
        retryDelays: [1.0, 2.0, 4.0, 4.0],
        stabilityWindow: 15.0
    )
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
