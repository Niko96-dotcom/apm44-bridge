import Foundation

struct BridgeMetricsSnapshot: Codable, Equatable {
    var fillMs: Double
    var ratio: Double
    var ppm: Double
    var underruns: UInt64
    var overruns: UInt64
    var xruns: UInt64
    var estimatedRtMs: Double
    var targetFillMs: Double
    var srcQuality: String

    enum CodingKeys: String, CodingKey {
        case fillMs = "fill_ms"
        case ratio
        case ppm
        case underruns
        case overruns
        case xruns
        case estimatedRtMs = "estimated_rt_ms"
        case targetFillMs = "target_fill_ms"
        case srcQuality = "src_quality"
    }

    var latencyLabel: String {
        let ms = max(0.1, estimatedRtMs.rounded())
        return "~\(Int(ms)) ms monitoring latency"
    }

    var fillProgress: Double {
        guard targetFillMs > 0 else { return 0 }
        return min(1.0, max(0, fillMs / targetFillMs))
    }

    var isStale: Bool = false
}
