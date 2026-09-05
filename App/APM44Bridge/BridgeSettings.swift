import Foundation

@MainActor
final class BridgeSettings: ObservableObject {
    private enum Keys {
        static let outputDeviceUid = "apm44.outputDeviceUid"
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
