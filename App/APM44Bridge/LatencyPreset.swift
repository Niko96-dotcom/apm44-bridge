import Foundation

enum LatencyPreset: String, CaseIterable, Identifiable {
    case low
    case balanced
    case safe

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

    var menuTitle: String {
        switch self {
        case .low: return "Low (~8 ms)"
        case .balanced: return "Balanced (~15 ms)"
        case .safe: return "Safe (~30 ms)"
        }
    }

    var stoppedLatencyHint: String {
        switch self {
        case .low: return "About 10–12 ms in Low mode when running."
        case .balanced: return "About 12–18 ms in Balanced mode when running."
        case .safe: return "About 25–40 ms in Safe mode when running."
        }
    }
}
