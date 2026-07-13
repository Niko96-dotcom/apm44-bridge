#include "tools/SoakHarness.h"

#include "engine/LibSamplerateSrc.h"

#include <apm44/DriftController.h>
#include <apm44/InputFrameDemand.h>
#include <apm44/PlanarRingBuffer.h>

#include <algorithm>
#include <cmath>
#include <vector>

namespace apm44 {

namespace {

constexpr double kInputRate = 44100.0;
constexpr double kOutputRate = 48000.0;
constexpr std::size_t kOutputBlockFrames = 256;

double InputRatioForSkew(double skewPpm) {
  const double skewFactor = 1.0 + skewPpm / 1'000'000.0;
  return DriftController::kNominalRatio / skewFactor;
}

}  // namespace

SoakMetrics RunSoakHarness(const SoakOptions& options) {
  SoakMetrics metrics{};

  const std::size_t targetFillFrames =
      PlanarRingBuffer::framesForMilliseconds(options.targetFillMs, kInputRate);

  PlanarRingBuffer ring;
  ring.prepare(std::max(targetFillFrames * 2 + 512, std::size_t{1024}));

  DriftController drift;
  drift.reset();
  drift.setTargetFillFrames(targetFillFrames);

  LibSamplerateSrc src;
  if (!src.prepare(LibSamplerateSrc::Quality::Medium)) {
    return metrics;
  }

  std::vector<float> in0(kOutputBlockFrames * 2);
  std::vector<float> in1(kOutputBlockFrames * 2);
  std::vector<float> out0(kOutputBlockFrames * 2);
  std::vector<float> out1(kOutputBlockFrames * 2);
  std::vector<float> pop0(kOutputBlockFrames * 2);
  std::vector<float> pop1(kOutputBlockFrames * 2);

  {
    std::vector<float> pre0(targetFillFrames, 0.0f);
    std::vector<float> pre1(targetFillFrames, 0.0f);
    const float* preIn[2] = {pre0.data(), pre1.data()};
    ring.push(preIn, targetFillFrames);
  }

  const std::size_t totalOutputBlocks = static_cast<std::size_t>(std::max(
      1.0, std::ceil(options.durationSec * kOutputRate / static_cast<double>(kOutputBlockFrames))));

  double fillSumMs = 0.0;
  std::size_t fillSamples = 0;
  metrics.maxFillMs = 0.0;

  const double maxFillMsLimit = options.targetFillMs * 2.0;
  std::size_t overfillBlocks = 0;

  std::size_t inPhase = 0;
  InputFrameDemand producerDemand;
  InputFrameDemand consumerDemand;

  for (std::size_t block = 0; block < totalOutputBlocks; ++block) {
    const double skew = (block % 200 < 100) ? options.skewPpm : -options.skewPpm;
    const std::size_t inputFrames =
        producerDemand.consume(kOutputBlockFrames, InputRatioForSkew(skew));

    for (std::size_t i = 0; i < inputFrames; ++i) {
      const double t = static_cast<double>(i + inPhase) / kInputRate;
      const float s = static_cast<float>(std::sin(2.0 * M_PI * 440.0 * t));
      in0[i] = s;
      in1[i] = s;
    }
    inPhase += inputFrames;

    const float* inCh[2] = {in0.data(), in1.data()};
    const std::size_t pushed = ring.push(inCh, inputFrames);
    if (pushed < inputFrames) {
      drift.notifyOverrun();
    }

    const std::size_t fill = ring.fillFrames();
    const double fillMs = ring.fillMs(kInputRate);
    fillSumMs += fillMs;
    ++fillSamples;
    metrics.maxFillMs = std::max(metrics.maxFillMs, fillMs);

    if (fillMs > maxFillMsLimit) {
      ++overfillBlocks;
    } else {
      overfillBlocks = 0;
    }
    if (overfillBlocks > static_cast<std::size_t>(kOutputRate / kOutputBlockFrames)) {
      metrics.passed = false;
      metrics.durationSec =
          static_cast<double>(block * kOutputBlockFrames) / kOutputRate;
      metrics.meanFillMs = fillSumMs / static_cast<double>(fillSamples);
      metrics.underruns = drift.underrunCount();
      metrics.overruns = drift.overrunCount();
      metrics.finalPpm = drift.currentPpm();
      return metrics;
    }

    const double ratio = drift.update(fill, kOutputBlockFrames, kOutputRate);
    src.setRatio(ratio);

    const std::size_t neededIn = consumerDemand.consume(kOutputBlockFrames, ratio);
    const std::size_t toPop = std::min(neededIn, std::min(fill, pop0.size()));
    if (toPop == 0) {
      drift.notifyUnderrun();
      continue;
    }
    float* popCh[2] = {pop0.data(), pop1.data()};
    const std::size_t popped = ring.pop(popCh, toPop);

    const float* procIn[2] = {popCh[0], popCh[1]};
    float* procOut[2] = {out0.data(), out1.data()};
    std::size_t written = 0;
    if (!src.process(procIn, popped, procOut, kOutputBlockFrames, written) || written == 0) {
      drift.notifyUnderrun();
    }
    if (popped < neededIn) {
      drift.notifyUnderrun();
    }
  }

  metrics.durationSec =
      static_cast<double>(totalOutputBlocks * kOutputBlockFrames) / kOutputRate;
  metrics.meanFillMs = fillSamples ? fillSumMs / static_cast<double>(fillSamples) : 0.0;
  metrics.underruns = drift.underrunCount();
  metrics.overruns = drift.overrunCount();
  metrics.finalPpm = drift.currentPpm();

  const double underrunBudget =
      options.durationSec <= 10.0 ? 10.0 : 10.0 * (options.durationSec / 60.0);
  const bool fillOk = metrics.maxFillMs <= maxFillMsLimit + 1.0;
  metrics.passed =
      static_cast<double>(metrics.underruns) <= underrunBudget && fillOk;
  return metrics;
}

}  // namespace apm44
