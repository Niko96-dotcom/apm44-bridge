import Foundation

@MainActor
final class BridgeSettings: ObservableObject {
    private enum Keys {
        static let outputDeviceUid = "apm44.outputDeviceUid"
        static let outputDeviceName = "apm44.outputDeviceName"
        static let resumeAfterUpdateAt = "apm44.resumeAfterUpdateAt"
        static let latencyPreset = "apm44.latencyPreset"
        static let srcQualityOverride = "apm44.srcQualityOverride"
    }

    private let defaults: UserDefaults

    @Published var outputDeviceUid: String? {
        didSet {
            defaults.set(outputDeviceUid, forKey: Keys.outputDeviceUid)
            NotificationCenter.default.post(
                name: .apm44OutputDeviceChanged,
                object: nil,
                userInfo: ["uid": outputDeviceUid ?? ""]
            )
        }
    }

    @Published var latencyPreset: LatencyPreset {
        didSet { defaults.set(latencyPreset.rawValue, forKey: Keys.latencyPreset) }
    }

    /// Last seen display name for the selected output, so the UI can show it
    /// while the device is absent (e.g. after relaunch before Core Audio
    /// re-enumerates). Only ever names the current outputDeviceUid: it is
    /// cleared whenever the uid changes to a device not in the list.
    @Published var outputDeviceName: String? {
        didSet { defaults.set(outputDeviceName, forKey: Keys.outputDeviceName) }
    }

    /// Set when an in-app (Sparkle) update starts installing while the bridge
    /// is running, so the next launch can resume it. Cleared on launch.
    @Published var resumeAfterUpdateRequestedAt: Date? {
        didSet {
            if let resumeAfterUpdateRequestedAt {
                defaults.set(resumeAfterUpdateRequestedAt, forKey: Keys.resumeAfterUpdateAt)
            } else {
                defaults.removeObject(forKey: Keys.resumeAfterUpdateAt)
            }
        }
    }

    @Published var srcQualityOverride: SrcQuality? {
        didSet {
            if let srcQualityOverride {
                defaults.set(srcQualityOverride.rawValue, forKey: Keys.srcQualityOverride)
            } else {
                defaults.removeObject(forKey: Keys.srcQualityOverride)
            }
        }
    }

    var effectiveSrcQuality: SrcQuality {
        srcQualityOverride ?? latencyPreset.defaultSrcQuality
    }

    func effectiveTargetFillMs(halMode: Bool) -> Double {
        latencyPreset.effectiveTargetFillMs(halMode: halMode)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        outputDeviceUid = defaults.string(forKey: Keys.outputDeviceUid)
        outputDeviceName = defaults.string(forKey: Keys.outputDeviceName)
        resumeAfterUpdateRequestedAt = defaults.object(forKey: Keys.resumeAfterUpdateAt) as? Date
        if let raw = defaults.string(forKey: Keys.latencyPreset),
           let preset = LatencyPreset(rawValue: raw) {
            latencyPreset = preset
        } else {
            // Safe default reduces rare HAL/Cubase underrun clicks for new installs.
            latencyPreset = .safe
        }
        if let raw = defaults.string(forKey: Keys.srcQualityOverride) {
            srcQualityOverride = SrcQuality(rawValue: raw)
        } else {
            srcQualityOverride = nil
        }
    }
}

extension Notification.Name {
    static let apm44OutputDeviceChanged = Notification.Name("apm44.outputDeviceChanged")
}
