import Foundation

@MainActor
final class BridgeSettings: ObservableObject {
    private enum Keys {
        static let outputDeviceUid = "apm44.outputDeviceUid"
        static let latencyPreset = "apm44.latencyPreset"
        static let srcQualityOverride = "apm44.srcQualityOverride"
    }

    @Published var outputDeviceUid: String? {
        didSet { UserDefaults.standard.set(outputDeviceUid, forKey: Keys.outputDeviceUid) }
    }

    @Published var latencyPreset: LatencyPreset {
        didSet { UserDefaults.standard.set(latencyPreset.rawValue, forKey: Keys.latencyPreset) }
    }

    @Published var srcQualityOverride: SrcQuality? {
        didSet {
            if let srcQualityOverride {
                UserDefaults.standard.set(srcQualityOverride.rawValue, forKey: Keys.srcQualityOverride)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.srcQualityOverride)
            }
        }
    }

    var effectiveSrcQuality: SrcQuality {
        srcQualityOverride ?? latencyPreset.defaultSrcQuality
    }

    var effectiveTargetFillMs: Double {
        latencyPreset.targetFillMs
    }

    init() {
        let defaults = UserDefaults.standard
        outputDeviceUid = defaults.string(forKey: Keys.outputDeviceUid)
        if let raw = defaults.string(forKey: Keys.latencyPreset),
           let preset = LatencyPreset(rawValue: raw) {
            latencyPreset = preset
        } else {
            latencyPreset = .balanced
        }
        if let raw = defaults.string(forKey: Keys.srcQualityOverride) {
            srcQualityOverride = SrcQuality(rawValue: raw)
        } else {
            srcQualityOverride = nil
        }
    }

    func applyPresetDefaultsIfNeeded() {
        if srcQualityOverride == nil {
            srcQualityOverride = nil
        }
    }

    func onPresetChanged() {
        if srcQualityOverride == nil {
            // Preset default quality applies via effectiveSrcQuality.
        }
    }
}
