#include "engine/BridgeMetrics.h"
#include "engine/MetricsPublisher.h"

#include <catch2/catch_test_macros.hpp>

#include <atomic>
#include <barrier>
#include <cmath>
#include <string>
#include <thread>
#include <vector>

namespace {

bool Contains(const std::string& haystack, const std::string& needle) {
  return haystack.find(needle) != std::string::npos;
}

}  // namespace

TEST_CASE("BridgeMetrics JSON contains required fields") {
  const auto metrics = apm44::MakeBridgeMetrics(15.2, 1.088435, 12.0, 1, 2, 3, 15.0, "medium");
  const std::string line = apm44::ToJsonLine(metrics);

  REQUIRE(Contains(line, "\"fill_ms\""));
  REQUIRE(Contains(line, "\"xruns\""));
  REQUIRE(Contains(line, "\"ratio\""));
  REQUIRE(Contains(line, "\"underruns\""));
  REQUIRE(Contains(line, "\"overruns\""));
  REQUIRE(Contains(line, "\"ppm\""));
  REQUIRE(Contains(line, "\"estimated_rt_ms\""));
  REQUIRE(Contains(line, "\"target_fill_ms\""));
  REQUIRE(Contains(line, "\"src_quality\""));
  REQUIRE(Contains(line, "\"input_dropped_frames\""));
  REQUIRE(Contains(line, "\"producer_overrun_events\""));
  REQUIRE(Contains(line, "\"producer_dropped_frames\""));
  REQUIRE(Contains(line, "\"producer_not_ready_dropped_frames\""));
  REQUIRE(Contains(line, "\"lane_queue_drops\""));
  REQUIRE(Contains(line, "\"lane_timestamp_mismatches\""));
  REQUIRE(Contains(line, "\"lane_frame_mismatch_dropped_frames\""));
  REQUIRE(Contains(line, "\"consumer_resets\""));
  REQUIRE(Contains(line, "\"output_starvation_frames\""));
  REQUIRE(Contains(line, "\"partial_shortage_events\""));
  REQUIRE(Contains(line, "\"converter_reset_events\""));
  REQUIRE(Contains(line, "\"rebuffer_events\""));
  REQUIRE(Contains(line, "\"recovery_fade_events\""));
  REQUIRE(Contains(line, "15.200"));
  REQUIRE(line.find('\n') == std::string::npos);
}

TEST_CASE("BridgeMetrics exposes every known frame-loss counter", "[metrics][F-05]") {
  apm44::MetricsSnapshot snapshot;
  snapshot.fillMs = 15.2;
  snapshot.smoothedRatio = 1.088435;
  snapshot.inputDroppedFrames = 11;
  snapshot.producerOverrunEvents = 2;
  snapshot.producerDroppedFrames = 13;
  snapshot.producerNotReadyDroppedFrames = 3;
  snapshot.laneQueueDrops = 5;
  snapshot.laneTimestampMismatches = 7;
  snapshot.laneFrameMismatchDroppedFrames = 17;
  snapshot.consumerResets = 19;
  snapshot.outputStarvationFrames = 23;
  snapshot.partialShortageEvents = 29;
  snapshot.converterResetEvents = 31;
  snapshot.rebufferEvents = 37;
  snapshot.recoveryFadeEvents = 41;

  const auto metrics = apm44::MakeBridgeMetrics(snapshot, 15.0, "medium");
  const std::string line = apm44::ToJsonLine(metrics);
  REQUIRE(Contains(line, "\"input_dropped_frames\":11"));
  REQUIRE(Contains(line, "\"producer_overrun_events\":2"));
  REQUIRE(Contains(line, "\"producer_dropped_frames\":13"));
  REQUIRE(Contains(line, "\"producer_not_ready_dropped_frames\":3"));
  REQUIRE(Contains(line, "\"lane_queue_drops\":5"));
  REQUIRE(Contains(line, "\"lane_timestamp_mismatches\":7"));
  REQUIRE(Contains(line, "\"lane_frame_mismatch_dropped_frames\":17"));
  REQUIRE(Contains(line, "\"consumer_resets\":19"));
  REQUIRE(Contains(line, "\"output_starvation_frames\":23"));
  REQUIRE(Contains(line, "\"partial_shortage_events\":29"));
  REQUIRE(Contains(line, "\"converter_reset_events\":31"));
  REQUIRE(Contains(line, "\"rebuffer_events\":37"));
  REQUIRE(Contains(line, "\"recovery_fade_events\":41"));
}

TEST_CASE("BridgeMetrics JSON truncation fails closed without overreading buffer",
          "[metrics][JSON-01][JSON-02]") {
  const std::string longQuality(4096, 'q');
  const auto metrics =
      apm44::MakeBridgeMetrics(15.2, 1.088435, 12.0, 1, 2, 3, 15.0, longQuality);
  const std::string line = apm44::ToJsonLine(metrics);

  REQUIRE(line == "{}");
}

TEST_CASE("estimated_rt_ms equals fill_ms plus group delay") {
  const auto metrics = apm44::MakeBridgeMetrics(10.0, 1.0, 0.0, 0, 0, 0, 10.0, "medium");
  REQUIRE(std::abs(metrics.estimatedRtMs - (10.0 + apm44::kSrcGroupDelayMediumMs)) < 0.001);
  REQUIRE(metrics.estimatedRtMs > 0.0);
}

TEST_CASE("estimated_rt_ms distinguishes public SRC quality labels", "[metrics][SRC-01]") {
  const auto medium = apm44::MakeBridgeMetrics(15.0, 1.0, 0.0, 0, 0, 0, 15.0, "medium");
  const auto high = apm44::MakeBridgeMetrics(15.0, 1.0, 0.0, 0, 0, 0, 15.0, "high");
  const auto best = apm44::MakeBridgeMetrics(15.0, 1.0, 0.0, 0, 0, 0, 15.0, "best");

  REQUIRE(medium.estimatedRtMs < high.estimatedRtMs);
  REQUIRE(high.estimatedRtMs < best.estimatedRtMs);
}

TEST_CASE("MetricsPublisher keeps fields from the same publication", "[metrics][rt]") {
  apm44::MetricsPublisherState state;
  std::atomic<bool> done{false};
  std::atomic<bool> incoherent{false};
  constexpr int kReaderCount = 4;
  constexpr uint64_t kPublications = 50000;
  std::barrier ready(kReaderCount + 1);
  std::vector<std::thread> readers;

  for (int i = 0; i < kReaderCount; ++i) {
    readers.emplace_back([&] {
      ready.arrive_and_wait();
      do {
        const auto snapshot = apm44::ReadMetrics(state);
        // Independently increasing fields can still form a torn snapshot.
        // These relationships hold only when every field has the same version.
        if (snapshot.overruns != snapshot.underruns * 2 ||
            snapshot.xruns != snapshot.underruns * 3 ||
            snapshot.fillMs != static_cast<double>(snapshot.underruns) ||
            snapshot.ppm != -static_cast<double>(snapshot.underruns)) {
          incoherent.store(true, std::memory_order_relaxed);
        }
      } while (!done.load(std::memory_order_acquire));
    });
  }

  ready.arrive_and_wait();
  for (uint64_t i = 1; i <= kPublications; ++i) {
    apm44::MetricsSnapshot next;
    next.underruns = i;
    next.overruns = i * 2;
    next.xruns = i * 3;
    next.fillMs = static_cast<double>(i);
    next.ppm = -static_cast<double>(i);
    apm44::PublishMetrics(state, next);
  }
  done.store(true, std::memory_order_release);
  for (auto& reader : readers) {
    reader.join();
  }

  REQUIRE_FALSE(incoherent.load());
  REQUIRE(apm44::ReadMetrics(state).underruns == kPublications);
}

TEST_CASE("MetricsPublisherPackedFloatingFieldsRoundTrip",
          "[metrics][rt][METR-04]") {
  apm44::MetricsPublisherState state;
  apm44::MetricsSnapshot next;
  next.fillMs = 15.25;
  next.smoothedRatio = 48000.0 / 44100.0;
  next.ppm = -12.75;
  next.underruns = 2;
  next.overruns = 3;
  next.xruns = 5;
  next.partialShortageEvents = 7;
  next.converterResetEvents = 11;
  next.rebufferEvents = 13;
  next.recoveryFadeEvents = 17;

  apm44::PublishMetrics(state, next);
  const apm44::MetricsSnapshot read = apm44::ReadMetrics(state);

  REQUIRE(read.fillMs == next.fillMs);
  REQUIRE(read.smoothedRatio == next.smoothedRatio);
  REQUIRE(read.ppm == next.ppm);
  REQUIRE(read.underruns == next.underruns);
  REQUIRE(read.overruns == next.overruns);
  REQUIRE(read.xruns == next.xruns);
  REQUIRE(read.partialShortageEvents == next.partialShortageEvents);
  REQUIRE(read.converterResetEvents == next.converterResetEvents);
  REQUIRE(read.rebufferEvents == next.rebufferEvents);
  REQUIRE(read.recoveryFadeEvents == next.recoveryFadeEvents);
}
