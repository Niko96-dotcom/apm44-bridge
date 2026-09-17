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
        // A HAL host may deliver 4096 frames at once (~93 ms at 44.1 kHz).
        // Safe waits for the following burst before playback begins so output
        // devices with smaller callbacks never run to the edge between blocks.
        case .safe: return 100
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

    /// Short label for the segmented control.
    var shortTitle: String {
        switch self {
        case .low: return AppStrings.low
        case .balanced: return AppStrings.balanced
        case .safe: return AppStrings.safe
        }
    }

    var stoppedLatencyHint: String { AppStrings.stoppedLatencyHint }
}
