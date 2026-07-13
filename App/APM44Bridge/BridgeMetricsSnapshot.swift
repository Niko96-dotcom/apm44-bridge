import Foundation

struct BridgeMetricsSnapshot: Codable, Equatable {
    var fillMs: Double
    var ratio: Double
    var ppm: Double
    var underruns: UInt64
    var overruns: UInt64
    var xruns: UInt64
    var inputDroppedFrames: UInt64
    var producerOverrunEvents: UInt64
    var producerDroppedFrames: UInt64
    var producerNotReadyDroppedFrames: UInt64
    var laneQueueDrops: UInt64
    var laneTimestampMismatches: UInt64
    var laneFrameMismatchDroppedFrames: UInt64
    var consumerResets: UInt64
    var outputStarvationFrames: UInt64
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
        case inputDroppedFrames = "input_dropped_frames"
        case producerOverrunEvents = "producer_overrun_events"
        case producerDroppedFrames = "producer_dropped_frames"
        case producerNotReadyDroppedFrames = "producer_not_ready_dropped_frames"
        case laneQueueDrops = "lane_queue_drops"
        case laneTimestampMismatches = "lane_timestamp_mismatches"
        case laneFrameMismatchDroppedFrames = "lane_frame_mismatch_dropped_frames"
        case consumerResets = "consumer_resets"
        case outputStarvationFrames = "output_starvation_frames"
        case estimatedRtMs = "estimated_rt_ms"
        case targetFillMs = "target_fill_ms"
        case srcQuality = "src_quality"
    }

    init(
        fillMs: Double,
        ratio: Double,
        ppm: Double,
        underruns: UInt64,
        overruns: UInt64,
        xruns: UInt64,
        inputDroppedFrames: UInt64 = 0,
        producerOverrunEvents: UInt64 = 0,
        producerDroppedFrames: UInt64 = 0,
        producerNotReadyDroppedFrames: UInt64 = 0,
        laneQueueDrops: UInt64 = 0,
        laneTimestampMismatches: UInt64 = 0,
        laneFrameMismatchDroppedFrames: UInt64 = 0,
        consumerResets: UInt64 = 0,
        outputStarvationFrames: UInt64 = 0,
        estimatedRtMs: Double,
        targetFillMs: Double,
        srcQuality: String,
        isStale: Bool = false
    ) {
        self.fillMs = fillMs
        self.ratio = ratio
        self.ppm = ppm
        self.underruns = underruns
        self.overruns = overruns
        self.xruns = xruns
        self.inputDroppedFrames = inputDroppedFrames
        self.producerOverrunEvents = producerOverrunEvents
        self.producerDroppedFrames = producerDroppedFrames
        self.producerNotReadyDroppedFrames = producerNotReadyDroppedFrames
        self.laneQueueDrops = laneQueueDrops
        self.laneTimestampMismatches = laneTimestampMismatches
        self.laneFrameMismatchDroppedFrames = laneFrameMismatchDroppedFrames
        self.consumerResets = consumerResets
        self.outputStarvationFrames = outputStarvationFrames
        self.estimatedRtMs = estimatedRtMs
        self.targetFillMs = targetFillMs
        self.srcQuality = srcQuality
        self.isStale = isStale
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fillMs = try values.decode(Double.self, forKey: .fillMs)
        ratio = try values.decode(Double.self, forKey: .ratio)
        ppm = try values.decode(Double.self, forKey: .ppm)
        underruns = try values.decode(UInt64.self, forKey: .underruns)
        overruns = try values.decode(UInt64.self, forKey: .overruns)
        xruns = try values.decode(UInt64.self, forKey: .xruns)
        inputDroppedFrames = try values.decodeIfPresent(UInt64.self, forKey: .inputDroppedFrames) ?? 0
        producerOverrunEvents = try values.decodeIfPresent(UInt64.self, forKey: .producerOverrunEvents) ?? 0
        producerDroppedFrames = try values.decodeIfPresent(UInt64.self, forKey: .producerDroppedFrames) ?? 0
        producerNotReadyDroppedFrames = try values.decodeIfPresent(UInt64.self, forKey: .producerNotReadyDroppedFrames) ?? 0
        laneQueueDrops = try values.decodeIfPresent(UInt64.self, forKey: .laneQueueDrops) ?? 0
        laneTimestampMismatches = try values.decodeIfPresent(UInt64.self, forKey: .laneTimestampMismatches) ?? 0
        laneFrameMismatchDroppedFrames = try values.decodeIfPresent(UInt64.self, forKey: .laneFrameMismatchDroppedFrames) ?? 0
        consumerResets = try values.decodeIfPresent(UInt64.self, forKey: .consumerResets) ?? 0
        outputStarvationFrames = try values.decodeIfPresent(UInt64.self, forKey: .outputStarvationFrames) ?? 0
        estimatedRtMs = try values.decode(Double.self, forKey: .estimatedRtMs)
        targetFillMs = try values.decode(Double.self, forKey: .targetFillMs)
        srcQuality = try values.decode(String.self, forKey: .srcQuality)
        isStale = false
    }

    var knownFrameLoss: UInt64 {
        inputDroppedFrames &+ producerDroppedFrames &+ outputStarvationFrames
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
