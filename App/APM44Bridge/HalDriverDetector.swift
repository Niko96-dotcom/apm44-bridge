import CoreAudio
import Foundation

/// Detects whether the APM44 HAL virtual device is installed and enumerated.
enum HalDriverDetector {
    static let deviceUid = "com.niko.apm44.bridge.device"
    static let deviceName = "APM44 Bridge"

    /// Absolute path where the HAL driver bundle is installed on disk.
    static let installedBundlePath = "/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver"

    /// Info.plist inside the installed HAL driver bundle.
    static var installedDriverPlistPath: String {
        (installedBundlePath as NSString).appendingPathComponent("Contents/Info.plist")
    }

    /// The app/helper build fingerprint from this bundle's Info.plist.
    /// Returns the raw value (may be nil when missing); use
    /// `normalizedBuildID(_:)` / `buildIDsMatch` for fail-closed comparison.
    static func appBuildID(bundle: Bundle = .main) -> String? {
        bundle.object(forInfoDictionaryKey: "APM44BuildID") as? String
    }

    /// The installed HAL driver's build fingerprint from its Info.plist.
    /// `plistURL` is injectable for deterministic tests; defaults to the
    /// installed driver plist. Reading two small plists is fine on any thread.
    static func driverBuildID(plistURL: URL? = nil) -> String? {
        let url = plistURL ?? URL(fileURLWithPath: installedDriverPlistPath)
        guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
            return nil
        }
        return dict["APM44BuildID"] as? String
    }

    /// Fail-closed normalization: trims whitespace and rejects missing,
    /// empty, placeholder (`unknown`, unresolved `$(…)`/`${…}`) values.
    /// Returns nil for anything that must not compare equal.
    static func normalizedBuildID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed != "unknown" else { return nil }
        if trimmed.contains("$(") || trimmed.contains("${") { return nil }
        return trimmed
    }

    /// Compares full build IDs (e.g. `0.12.7+3fc0…` vs `0.12.7+c27…`),
    /// not just the `0.12.7` version. Missing/malformed IDs never match
    /// (fail closed).
    static func buildIDsMatch(appBuildID: String?, driverBuildID: String?) -> Bool {
        guard let app = normalizedBuildID(appBuildID),
              let driver = normalizedBuildID(driverBuildID) else {
            return false
        }
        return app == driver
    }

    /// True when the driver *bundle* exists on disk, whether or not Core Audio
    /// has enumerated it yet. A freshly installed HAL driver is on disk
    /// immediately but is often not loaded until coreaudiod is reloaded or the
    /// Mac is restarted once.
    static func isDriverBundleOnDisk() -> Bool {
        FileManager.default.fileExists(atPath: installedBundlePath)
    }

    /// Coarse install state that drives first-run guidance.
    /// When the HAL device is enumerated, the installed driver build ID
    /// must match the app's build ID or the status is `.buildMismatch`
    /// (never a green ready). When the HAL device is absent, existing
    /// fallback logic applies and a missing driver does not block.
    static func status() -> DriverStatus {
        status(
            halPresent: isHalInstalled(),
            appBuildID: appBuildID(),
            driverBuildID: driverBuildID(),
            driverBundleOnDisk: isDriverBundleOnDisk()
        )
    }

    /// Testable overload with injectable presence/IDs. `driverBundleOnDisk`
    /// defaults to the live on-disk check when nil.
    static func status(
        halPresent: Bool,
        appBuildID: String?,
        driverBuildID: String?,
        driverBundleOnDisk: Bool? = nil
    ) -> DriverStatus {
        if halPresent {
            return buildIDsMatch(appBuildID: appBuildID, driverBuildID: driverBuildID)
                ? .ready : .buildMismatch
        }
        let onDisk = driverBundleOnDisk ?? isDriverBundleOnDisk()
        if onDisk { return .installedNotLoaded }
        return .notInstalled
    }

    /// True when Core Audio lists an output device named APM44 Bridge (or matching UID).
    static func isHalInstalled() -> Bool {
        findHalDevice() != nil
    }

    /// Returns nominal rate of APM44 Bridge when present.
    static func halNominalRate() -> Double? {
        findHalDevice()?.nominalRate
    }

    static func findHalDevice() -> AudioDeviceRow? {
        let devices = enumerateOutputDevices()
        if let byUid = devices.first(where: { $0.uid == deviceUid }) {
            return byUid
        }
        return devices.first { $0.name == deviceName }
    }

    static func enumerateOutputDevices() -> [AudioDeviceRow] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &ids
        ) == noErr else {
            return []
        }

        var rows: [AudioDeviceRow] = []
        for id in ids {
            guard hasOutputScope(id) else { continue }
            guard let uid = stringProperty(id, kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(id, kAudioObjectPropertyName) else {
                continue
            }
            let rate = nominalRate(id)
            rows.append(
                AudioDeviceRow(
                    uid: uid,
                    name: name,
                    nominalRate: rate,
                    hasInput: hasInputScope(id),
                    hasOutput: true
                )
            )
        }
        return rows
    }

    private static func hasOutputScope(_ deviceId: AudioDeviceID) -> Bool {
        channelCount(deviceId, scope: kAudioDevicePropertyScopeOutput) > 0
    }

    private static func hasInputScope(_ deviceId: AudioDeviceID) -> Bool {
        channelCount(deviceId, scope: kAudioDevicePropertyScopeInput) > 0
    }

    private static func channelCount(_ deviceId: AudioDeviceID, scope: AudioObjectPropertyScope) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceId, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return 0
        }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(deviceId, &address, 0, nil, &dataSize, buffer) == noErr else {
            return 0
        }
        let list = buffer.assumingMemoryBound(to: AudioBufferList.self)
        var channels: UInt32 = 0
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        for buf in buffers {
            channels += buf.mNumberChannels
        }
        return channels
    }

    private static func nominalRate(_ deviceId: AudioDeviceID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(deviceId, &address, 0, nil, &size, &rate) == noErr else {
            return 0
        }
        return rate
    }

    private static func stringProperty(_ objectId: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objectId, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return nil
        }
        var cfString: CFString?
        guard AudioObjectGetPropertyData(objectId, &address, 0, nil, &dataSize, &cfString) == noErr,
              let cfString else {
            return nil
        }
        return cfString as String
    }
}

/// Whether the APM44 HAL driver is enumerated by Core Audio, merely installed
/// on disk, absent entirely, or enumerated with a mismatched build.
enum DriverStatus: Equatable {
    /// Core Audio has enumerated the APM44 Bridge device with a driver
    /// build ID matching the app — ready to use.
    case ready
    /// Core Audio has enumerated the device but the installed driver build
    /// ID differs from (or is missing alongside) the app's build ID.
    /// Setup must not show green; Start is blocked until repaired.
    case buildMismatch
    /// Driver bundle is on disk but Core Audio has not loaded it yet
    /// (needs a Core Audio reload or a one-time restart).
    case installedNotLoaded
    /// No driver bundle on disk — the installer has not run, or it was removed.
    case notInstalled
}

enum RoutingMode: Equatable {
    case halVirtualDevice
    case blackHoleFallback
}

enum BridgeConnectionPhase: Equatable {
    case stopped
    case waitingForDAW
    case connected
    case running

    var label: String {
        switch self {
        case .stopped: return AppStrings.stopped
        case .waitingForDAW: return AppStrings.waitingForDAW
        case .connected: return AppStrings.connected
        case .running: return AppStrings.running
        }
    }
}
