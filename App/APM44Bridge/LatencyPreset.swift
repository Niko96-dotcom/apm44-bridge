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

    /// Short label for the segmented control. The static "~N ms" targets are
    /// intentionally not shown: musicians choose clicks-vs-delay, and the
    /// live measured badge while running is the only honest number.
    var shortTitle: String {
        switch self {
        case .low: return AppStrings.low
        case .balanced: return AppStrings.balanced
        case .safe: return AppStrings.safe
        }
    }

    /// One-line target description shown under the buffering segmented control.
    func targetDescription(halMode: Bool) -> String {
        let ms = Int(effectiveTargetFillMs(halMode: halMode))
        if halMode, targetFillMs < Self.halMinimumTargetFillMs {
            return AppStrings.bufferTargetMinimum(ms)
        }
        return AppStrings.bufferTarget(ms)
    }

    var targetDescription: String { targetDescription(halMode: false) }

    var stoppedLatencyHint: String { AppStrings.stoppedLatencyHint }
}
