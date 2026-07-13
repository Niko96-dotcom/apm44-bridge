import Foundation

enum LatencyPreset: String, CaseIterable, Identifiable {
    case low
    case balanced
    case safe

    static let halMinimumTargetFillMs: Double = 20

    var id: String { rawValue }

    var targetFillMs: Double {
        switch self {
        case .low: return 8
        case .balanced: return 15
        case .safe: return 30
        }
    }

    var defaultSrcQuality: SrcQuality {
        switch self {
        case .low, .balanced: return .medium
        case .safe: return .best
        }
    }

    func effectiveTargetFillMs(halMode: Bool) -> Double {
        halMode ? max(targetFillMs, Self.halMinimumTargetFillMs) : targetFillMs
    }

    func menuTitle(halMode: Bool) -> String {
        let ms = Int(effectiveTargetFillMs(halMode: halMode))
        switch self {
        case .low: return halMode ? "Low (~\(ms) ms HAL min)" : "Low (~8 ms)"
        case .balanced: return halMode ? "Balanced (~\(ms) ms)" : "Balanced (~15 ms)"
        case .safe: return "Safe (~\(ms) ms)"
        }
    }

    var menuTitle: String { menuTitle(halMode: false) }

    /// Short label for the segmented control — the "~N ms" detail is shown
    /// separately beneath the picker so the segments don't clip.
    var shortTitle: String {
        switch self {
        case .low: return "Low"
        case .balanced: return "Balanced"
        case .safe: return "Safe"
        }
    }

    /// One-line target description shown under the buffering segmented control.
    func targetDescription(halMode: Bool) -> String {
        let ms = Int(effectiveTargetFillMs(halMode: halMode))
        if halMode, targetFillMs < Self.halMinimumTargetFillMs {
            return "~\(ms) ms buffer target (HAL minimum)"
        }
        return "~\(ms) ms buffer target"
    }

    var targetDescription: String { targetDescription(halMode: false) }

    func stoppedLatencyHint(halMode: Bool) -> String {
        let ms = Int(effectiveTargetFillMs(halMode: halMode))
        return "~\(ms) ms bridge buffer target; device, DAW, and hardware latency are additional."
    }

    var stoppedLatencyHint: String { stoppedLatencyHint(halMode: false) }
}
