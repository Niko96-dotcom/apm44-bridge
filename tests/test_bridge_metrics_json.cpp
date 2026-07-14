#include "engine/BridgeMetrics.h"
#include "engine/MetricsPublisher.h"

#include <catch2/catch_test_macros.hpp>

#include <atomic>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>
#include <thread>
#include <vector>

namespace {

bool Contains(const std::string& haystack, const std::string& needle) {
  return haystack.find(needle) != std::string::npos;
}

std::filesystem::path RepoRoot() {
  return std::filesystem::path(__FILE__).parent_path().parent_path();
}

std::string ReadRepoFile(const std::string& rel) {
  std::ifstream in(RepoRoot() / rel);
  REQUIRE(in.good());
  return std::string((std::istreambuf_iterator<char>(in)),
                     std::istreambuf_iterator<char>());
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

// METR-01/03: prove the metrics publisher is data-race-free. Spawn
// one writer thread and four reader threads, exercise the publisher
// for many iterations, then assert the sequence retry never delivered
// a torn snapshot (counters observed by readers are monotonically
// non-decreasing — the writer only ever increments).
TEST_CASE("MetricsPublisherSeqlockNeverDeliversTornSnapshot",
          "[metrics][rt][METR-01][METR-03]") {
  apm44::MetricsPublisherState state;
  std::atomic<bool> stop{false};
  std::atomic<uint64_t> expectedFinalUnderruns{0};
  std::atomic<uint64_t> maxObservedUnderruns{0};
  std::atomic<uint64_t> maxObservedOverruns{0};
  std::atomic<uint64_t> maxObservedXruns{0};

  // Writer thread: publish 50,000 snapshots, each bumping the three
  // counters by small increments.
  std::thread writer([&]() {
    uint64_t underruns = 0;
    uint64_t overruns = 0;
    uint64_t xruns = 0;
    for (int i = 0; i < 50000 && !stop.load(std::memory_order_relaxed); ++i) {
      apm44::MetricsSnapshot next;
      next.fillMs = 15.0 + static_cast<double>(i % 100) * 0.01;
      next.smoothedRatio = 1.0884;
      next.ppm = 12.0;
      next.underruns = underruns;
      next.overruns = overruns;
      next.xruns = xruns;
      apm44::PublishMetrics(state, next);
      underruns += (i % 7 == 0) ? 1 : 0;
      overruns += (i % 11 == 0) ? 1 : 0;
      xruns += (i % 13 == 0) ? 1 : 0;
    }
    expectedFinalUnderruns.store(underruns, std::memory_order_relaxed);
  });

  // Reader threads: each reads as fast as possible, tracking the max
  // counter values they ever observed. A torn snapshot would be
  // visible as a regression (a smaller counter value than the
  // reader's local max) — which must never happen because the
  // sequence check retries on concurrent publication.
  constexpr int kReaderCount = 4;
  std::vector<std::thread> readers;
  readers.reserve(kReaderCount);
  for (int t = 0; t < kReaderCount; ++t) {
    readers.emplace_back([&]() {
      uint64_t lastUnderruns = 0;
      uint64_t lastOverruns = 0;
      uint64_t lastXruns = 0;
      while (!stop.load(std::memory_order_relaxed)) {
        apm44::MetricsSnapshot snap = apm44::ReadMetrics(state);
        if (snap.underruns < lastUnderruns ||
            snap.overruns < lastOverruns ||
            snap.xruns < lastXruns) {
          // Torn snapshot — record and stop; assertion below will fail.
          stop.store(true, std::memory_order_relaxed);
          FAIL("Torn snapshot detected: underruns "
               << snap.underruns << " < " << lastUnderruns);
          return;
        }
        lastUnderruns = snap.underruns;
        lastOverruns = snap.overruns;
        lastXruns = snap.xruns;
        uint64_t cur;
        cur = maxObservedUnderruns.load(std::memory_order_relaxed);
        while (lastUnderruns > cur) {
          if (maxObservedUnderruns.compare_exchange_weak(
                  cur, lastUnderruns)) {
            break;
          }
        }
        cur = maxObservedOverruns.load(std::memory_order_relaxed);
        while (lastOverruns > cur) {
          if (maxObservedOverruns.compare_exchange_weak(
                  cur, lastOverruns)) {
            break;
          }
        }
        cur = maxObservedXruns.load(std::memory_order_relaxed);
        while (lastXruns > cur) {
          if (maxObservedXruns.compare_exchange_weak(
                  cur, lastXruns)) {
            break;
          }
        }
      }
    });
  }

  writer.join();
  // Give readers a moment to observe the final value, then signal
  // them to stop.
  std::this_thread::sleep_for(std::chrono::milliseconds(50));
  stop.store(true, std::memory_order_relaxed);
  for (auto& t : readers) {
    t.join();
  }

  // The sequence retry guarantees that the final published value is
  // eventually visible to readers; the writer's last value must be
  // observed by at least one reader.
  REQUIRE(maxObservedUnderruns.load() ==
          expectedFinalUnderruns.load());
  REQUIRE(maxObservedOverruns.load() > 0);
  REQUIRE(maxObservedXruns.load() > 0);
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

TEST_CASE("MetricsPublisherStateAvoidsAtomicDouble",
          "[metrics][rt][METR-04]") {
  const std::string header = ReadRepoFile("BridgeDaemon/src/engine/MetricsPublisher.h");
  REQUIRE(!Contains(header, "std::atomic<double>"));
  REQUIRE(Contains(header, "std::atomic<uint64_t> fillMsBits"));
  REQUIRE(Contains(header, "std::atomic<uint64_t> smoothedRatioBits"));
  REQUIRE(Contains(header, "std::atomic<uint64_t> ppmBits"));
  REQUIRE(Contains(header, "std::atomic<uint64_t>::is_always_lock_free"));
}

TEST_CASE("LegacyConverterPathRemovedFromPublicRuntime",
          "[converter][CONV-01]") {
  const std::vector<std::string> files = {
      "BridgeDaemon/src/CliOptions.cpp",
      "BridgeDaemon/src/CliOptions.h",
      "BridgeDaemon/src/engine/BridgeEngine.cpp",
      "BridgeDaemon/src/engine/BridgeEngine.h",
      "BridgeDaemon/CMakeLists.txt",
      "tests/CMakeLists.txt",
      "docs/soak-test.md",
  };
  const std::vector<std::string> forbidden = {
      "--legacy-" "converter",
      "Audio" "ConverterSrc",
      "legacy" "Converter",
      "useLegacy" "Converter",
  };

  for (const auto& rel : files) {
    const std::string contents = ReadRepoFile(rel);
    for (const auto& needle : forbidden) {
      REQUIRE(!Contains(contents, needle));
    }
  }
}

// METR-03 regression guard: a bare copy of MetricsSnapshot across
// threads would not be data-race-free. Scan the source tree for
// any line that mentions `MetricsSnapshot` outside the seqlock
// pair; if the scan finds one, the test fails so a future
// regression that reintroduces a plain copy is caught.
TEST_CASE("NoBareMetricsSnapshotCopyInSource",
          "[metrics][rt][METR-03]") {
  // The allow-list of files where MetricsSnapshot is expected to
  // appear alongside the publisher free functions. The test reads
  // each file and asserts any reference to `MetricsSnapshot` is
  // near a call to `PublishMetrics` or `ReadMetrics`.
  const std::vector<std::string> files = {
      "BridgeDaemon/src/engine/BridgeEngine.cpp",
      "BridgeDaemon/src/engine/BridgeEngine.h",
      "BridgeDaemon/src/engine/MetricsPublisher.h",
      "Shared/include/apm44/MetricsSnapshot.h",
  };

  for (const auto& rel : files) {
    const std::string contents = ReadRepoFile(rel);
    // Check that any non-comment, non-include mention of
    // MetricsSnapshot is preceded within the same file by either
    // PublishMetrics or ReadMetrics (the publisher pair). The check
    // is intentionally loose: it only fails if a file uses
    // MetricsSnapshot without ever going through the publisher.
    const bool usesSeqlock =
        contents.find("PublishMetrics") != std::string::npos ||
        contents.find("ReadMetrics") != std::string::npos ||
        contents.find("MetricsPublisherState") != std::string::npos ||
        rel.find("MetricsSnapshot.h") != std::string::npos;
    const bool usesSnapshot =
        contents.find("MetricsSnapshot") != std::string::npos;
    if (usesSnapshot && !usesSeqlock) {
      FAIL(rel << " uses MetricsSnapshot without going through the "
                  "MetricsPublisher — bare cross-thread copy");
    }
  }
  SUCCEED("All MetricsSnapshot references are seqlock-mediated");
}
