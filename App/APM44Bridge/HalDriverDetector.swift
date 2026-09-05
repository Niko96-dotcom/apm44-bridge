import CoreAudio
import Foundation

/// Detects whether the APM44 HAL virtual device is installed and enumerated.
enum HalDriverDetector {
    static let deviceUid = "com.niko.apm44.bridge.device"
    static let deviceName = "APM44 Bridge"

    /// Absolute path where the HAL driver bundle is installed on disk.
    static let installedBundlePath = "/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver"

    /// True when the driver *bundle* exists on disk, whether or not Core Audio
    /// has enumerated it yet. A freshly installed HAL driver is on disk
    /// immediately but is often not loaded until coreaudiod is reloaded or the
    /// Mac is restarted once.
    static func isDriverBundleOnDisk() -> Bool {
        FileManager.default.fileExists(atPath: installedBundlePath)
    }

    /// Coarse install state that drives first-run guidance.
    static func status() -> DriverStatus {
        if isHalInstalled() { return .ready }
        if isDriverBundleOnDisk() { return .installedNotLoaded }
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
/// on disk, or absent entirely.
enum DriverStatus: Equatable {
    /// Core Audio has enumerated the APM44 Bridge device — ready to use.
    case ready
    /// Driver bundle is on disk but Core Audio has not loaded it yet
    /// (needs a Core Audio reload or a one-time restart).
    case installedNotLoaded
    /// No driver bundle on disk — the installer has not run, or it was removed.
    case notInstalled
}

enum RoutingMode: Equatable {
    case halVirtualDevice
    case blackHoleFallback

    var menuLabel: String {
        switch self {
        case .halVirtualDevice: return "APM44 Bridge (driver)"
        case .blackHoleFallback: return "BlackHole"
        }
    }

    func detail(outputName: String?) -> String {
        let output = outputName.map { "\($0) @ 48 kHz" } ?? "Choose output…"
        switch self {
        case .halVirtualDevice:
            return "DAW → APM44 Bridge @ 44.1 kHz → \(output)"
        case .blackHoleFallback:
            return "DAW → BlackHole @ 44.1 kHz → \(output)"
        }
    }
}

enum BridgeConnectionPhase: Equatable {
    case stopped
    case waitingForDAW
    case connected
    case running

    var label: String {
        switch self {
        case .stopped: return "Stopped"
        case .waitingForDAW: return "Waiting for DAW"
        case .connected: return "Connected"
        case .running: return "Running"
        }
    }
}
