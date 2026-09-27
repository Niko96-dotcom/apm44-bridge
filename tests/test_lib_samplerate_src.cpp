#include <catch2/catch_test_macros.hpp>

#include "engine/LibSamplerateSrc.h"

#include <samplerate.h>

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <vector>

TEST_CASE("LibSamplerateSrc 147 to ~160 frames", "[lib_samplerate_src]") {
  apm44::LibSamplerateSrc src;
  REQUIRE(src.prepare(apm44::LibSamplerateSrc::Quality::Medium));

  constexpr std::size_t kInFrames = 147;
  std::vector<float> in0(kInFrames);
  std::vector<float> in1(kInFrames);
  for (std::size_t i = 0; i < kInFrames; ++i) {
    const double t = static_cast<double>(i) / 44100.0;
    const float sample = static_cast<float>(std::sin(2.0 * M_PI * 440.0 * t));
    in0[i] = sample;
    in1[i] = sample;
  }

  const float* inCh[2] = {in0.data(), in1.data()};
  std::vector<float> out0(512);
  std::vector<float> out1(512);
  float* outCh[2] = {out0.data(), out1.data()};

  std::size_t written = 0;
  REQUIRE(src.process(inCh, kInFrames, outCh, 256, written));
  float* flushOut[2] = {out0.data() + written, out1.data() + written};
  std::size_t flushed = 0;
  if (written < out0.size() && src.flush(flushOut, out0.size() - written, flushed)) {
    written += flushed;
  }
  REQUIRE(written > 0);
  const double ratio = static_cast<double>(written) / static_cast<double>(kInFrames);
  REQUIRE(ratio > (160.0 / 147.0) * 0.95);
  REQUIRE(ratio < (160.0 / 147.0) * 1.05);
}

TEST_CASE("LibSamplerateSrc positive ppm yields more output than negative ppm", "[lib_samplerate_src]") {
  constexpr std::size_t kBlockFrames = 147;
  constexpr std::size_t kBlocks = 600;
  constexpr double kNominal = 48000.0 / 44100.0;
  constexpr double kPpm = 1000.0;
  const double ratioPlus = kNominal * (1.0 + kPpm / 1'000'000.0);
  const double ratioMinus = kNominal * (1.0 - kPpm / 1'000'000.0);
  const std::size_t totalInputFrames = kBlockFrames * kBlocks;

  apm44::LibSamplerateSrc plus;
  apm44::LibSamplerateSrc minus;
  REQUIRE(plus.prepare(apm44::LibSamplerateSrc::Quality::Medium));
  REQUIRE(minus.prepare(apm44::LibSamplerateSrc::Quality::Medium));
  plus.setRatio(ratioPlus);
  minus.setRatio(ratioMinus);

  // Capacity rules from LibSamplerateSrc::prepare/process: max 1024 input
  // frames, max output ceil(1024 * 48000/44100) + 32 = 1147 frames.
  // 147 in -> ~160 out, so 512 is safely within limits with ratio headroom.
  constexpr std::size_t kOutCapacity = 512;
  std::vector<float> in0(kBlockFrames);
  std::vector<float> in1(kBlockFrames);
  std::vector<float> out0(kOutCapacity);
  std::vector<float> out1(kOutCapacity);

  std::size_t plusTotal = 0;
  std::size_t minusTotal = 0;
  for (std::size_t block = 0; block < kBlocks; ++block) {
    for (std::size_t i = 0; i < kBlockFrames; ++i) {
      const double t = static_cast<double>(block * kBlockFrames + i) / 44100.0;
      const float s = static_cast<float>(std::sin(2.0 * M_PI * 440.0 * t));
      in0[i] = s;
      in1[i] = s;
    }
    const float* inCh[2] = {in0.data(), in1.data()};
    float* outCh[2] = {out0.data(), out1.data()};

    std::size_t writtenPlus = 0;
    REQUIRE(plus.process(inCh, kBlockFrames, outCh, kOutCapacity, writtenPlus));
    REQUIRE(writtenPlus > 0);
    for (std::size_t i = 0; i < writtenPlus; ++i) {
      REQUIRE(std::isfinite(out0[i]));
      REQUIRE(std::isfinite(out1[i]));
    }
    plusTotal += writtenPlus;

    std::size_t writtenMinus = 0;
    REQUIRE(minus.process(inCh, kBlockFrames, outCh, kOutCapacity, writtenMinus));
    REQUIRE(writtenMinus > 0);
    for (std::size_t i = 0; i < writtenMinus; ++i) {
      REQUIRE(std::isfinite(out0[i]));
      REQUIRE(std::isfinite(out1[i]));
    }
    minusTotal += writtenMinus;
  }

  const double expectedPlus = static_cast<double>(totalInputFrames) * ratioPlus;
  const double expectedMinus = static_cast<double>(totalInputFrames) * ratioMinus;
  const double expectedGap = static_cast<double>(totalInputFrames) * kNominal * 2e-3;
  // The +/-1000 ppm gap is ~192 frames for 88200 input frames. Both converters
  // share the same filter delay, so the gap itself is exact to a few frames; a
  // no-op setRatio (gap 0) or a +/-600 ppm ratio (gap ~115) fails here.
  const double gap = static_cast<double>(plusTotal) - static_cast<double>(minusTotal);
  REQUIRE(std::abs(gap - expectedGap) <= 4.0);
  // Unflushed sinc delay leaves each total ~21 frames short of input * ratio;
  // 32 frames of headroom still rejects a converter left at the nominal ratio
  // (~96 frames off) or any shared ratio error above ~0.03%.
  REQUIRE(std::abs(static_cast<double>(plusTotal) - expectedPlus) <= 32.0);
  REQUIRE(std::abs(static_cast<double>(minusTotal) - expectedMinus) <= 32.0);
}

TEST_CASE("LibSamplerateSrc quality selects the matching libsamplerate converter",
          "[lib_samplerate_src]") {
  constexpr std::size_t kInFrames = 512;
  constexpr std::size_t kOutCapacity = 1024;
  constexpr double kRatio = 48000.0 / 44100.0;

  std::vector<float> in0(kInFrames);
  std::vector<float> in1(kInFrames);
  for (std::size_t i = 0; i < kInFrames; ++i) {
    const double t = static_cast<double>(i) / 44100.0;
    const float s = static_cast<float>(std::sin(2.0 * M_PI * 440.0 * t) +
                                       0.5 * std::sin(2.0 * M_PI * 5173.0 * t));
    in0[i] = s;
    in1[i] = s;
  }

  // Raw reference mirroring LibSamplerateSrc::process call pattern: stereo
  // interleaving, end_of_input=0, src_ratio=kRatio, looping over remaining
  // input / remaining output capacity until drained or stalled.
  auto runReference = [&](int converterType, std::vector<float>& ref0,
                          std::vector<float>& ref1, std::size_t& refWritten) {
    int error = 0;
    SRC_STATE* state = src_new(converterType, 2, &error);
    REQUIRE(state != nullptr);
    REQUIRE(error == 0);
    REQUIRE(src_set_ratio(state, kRatio) == 0);

    std::vector<float> interleavedIn(kInFrames * 2);
    for (std::size_t i = 0; i < kInFrames; ++i) {
      interleavedIn[i * 2 + 0] = in0[i];
      interleavedIn[i * 2 + 1] = in1[i];
    }
    std::vector<float> interleavedOut(kOutCapacity * 2, 0.0f);

    long inOffset = 0;
    long outOffset = 0;
    long inRemaining = static_cast<long>(kInFrames);
    const long outCap = static_cast<long>(kOutCapacity);
    while (inRemaining > 0 && outOffset < outCap) {
      SRC_DATA data{};
      data.data_in = interleavedIn.data() + static_cast<std::size_t>(inOffset) * 2;
      data.data_out = interleavedOut.data() + static_cast<std::size_t>(outOffset) * 2;
      data.input_frames = inRemaining;
      data.output_frames = outCap - outOffset;
      data.end_of_input = 0;
      data.src_ratio = kRatio;
      REQUIRE(src_process(state, &data) == 0);
      inOffset += data.input_frames_used;
      inRemaining -= data.input_frames_used;
      outOffset += data.output_frames_gen;
      if (data.input_frames_used == 0 && data.output_frames_gen == 0) {
        break;
      }
    }
    refWritten = static_cast<std::size_t>(outOffset);
    ref0.resize(refWritten);
    ref1.resize(refWritten);
    for (std::size_t i = 0; i < refWritten; ++i) {
      ref0[i] = interleavedOut[i * 2 + 0];
      ref1[i] = interleavedOut[i * 2 + 1];
    }
    src_delete(state);
  };

  struct Case {
    apm44::LibSamplerateSrc::Quality quality;
    int expectedType;
  };
  const Case cases[3] = {
      {apm44::LibSamplerateSrc::Quality::Medium, SRC_SINC_FASTEST},
      {apm44::LibSamplerateSrc::Quality::High, SRC_SINC_MEDIUM_QUALITY},
      {apm44::LibSamplerateSrc::Quality::Best, SRC_SINC_BEST_QUALITY},
  };
  const int allTypes[3] = {SRC_SINC_FASTEST, SRC_SINC_MEDIUM_QUALITY, SRC_SINC_BEST_QUALITY};

  for (const Case& c : cases) {
    apm44::LibSamplerateSrc src;
    REQUIRE(src.prepare(c.quality));

    std::vector<float> out0(kOutCapacity);
    std::vector<float> out1(kOutCapacity);
    const float* inCh[2] = {in0.data(), in1.data()};
    float* outCh[2] = {out0.data(), out1.data()};
    std::size_t written = 0;
    REQUIRE(src.process(inCh, kInFrames, outCh, kOutCapacity, written));
    REQUIRE(written > 0);

    std::vector<float> ref0;
    std::vector<float> ref1;
    std::size_t refWritten = 0;
    runReference(c.expectedType, ref0, ref1, refWritten);
    REQUIRE(written == refWritten);
    for (std::size_t i = 0; i < written; ++i) {
      REQUIRE(std::fabs(out0[i] - ref0[i]) < 1e-6);
      REQUIRE(std::fabs(out1[i] - ref1[i]) < 1e-6);
    }

    for (int other : allTypes) {
      if (other == c.expectedType) {
        continue;
      }
      std::vector<float> other0;
      std::vector<float> other1;
      std::size_t otherWritten = 0;
      runReference(other, other0, other1, otherWritten);
      const std::size_t cmp = std::min(written, otherWritten);
      REQUIRE(cmp > 0);
      float maxDiff = 0.0f;
      for (std::size_t i = 0; i < cmp; ++i) {
        maxDiff = std::max(maxDiff, std::fabs(out0[i] - other0[i]));
        maxDiff = std::max(maxDiff, std::fabs(out1[i] - other1[i]));
      }
      CAPTURE(c.expectedType, other, maxDiff);
      REQUIRE(maxDiff > 1e-4);
    }
  }
}

TEST_CASE("LibSamplerateSrc carries unconsumed input across full output blocks",
          "[lib_samplerate_src]") {
  apm44::LibSamplerateSrc src;
  REQUIRE(src.prepare(apm44::LibSamplerateSrc::Quality::Medium));

  constexpr std::size_t kInputFramesPerBlock = 471;
  constexpr std::size_t kOutputFramesPerBlock = 512;
  constexpr std::size_t kBlocks = 96;
  constexpr double kRatio = 48000.0 / 44100.0;

  std::vector<float> in0(kInputFramesPerBlock);
  std::vector<float> in1(kInputFramesPerBlock);
  std::vector<float> out0(kOutputFramesPerBlock);
  std::vector<float> out1(kOutputFramesPerBlock);

  std::size_t totalInputFrames = 0;
  std::size_t totalOutputFrames = 0;
  for (std::size_t block = 0; block < kBlocks; ++block) {
    for (std::size_t i = 0; i < kInputFramesPerBlock; ++i) {
      const double t = static_cast<double>(totalInputFrames + i) / 44100.0;
      const float sample = static_cast<float>(std::sin(2.0 * M_PI * 440.0 * t));
      in0[i] = sample;
      in1[i] = sample;
    }
    totalInputFrames += kInputFramesPerBlock;

    const float* inCh[2] = {in0.data(), in1.data()};
    float* outCh[2] = {out0.data(), out1.data()};
    std::size_t written = 0;
    REQUIRE(src.process(inCh, kInputFramesPerBlock, outCh, kOutputFramesPerBlock, written));
    totalOutputFrames += written;
  }

  std::vector<float> flush0(kOutputFramesPerBlock * 2);
  std::vector<float> flush1(kOutputFramesPerBlock * 2);
  float* flushCh[2] = {flush0.data(), flush1.data()};
  std::size_t flushed = 0;
  REQUIRE(src.flush(flushCh, flush0.size(), flushed));
  totalOutputFrames += flushed;

  const std::size_t expected =
      static_cast<std::size_t>(std::floor(static_cast<double>(totalInputFrames) * kRatio));
  REQUIRE(totalOutputFrames + 64 >= expected);
}

TEST_CASE("LibSamplerateSrc flush drains state after a full output block",
          "[lib_samplerate_src]") {
  apm44::LibSamplerateSrc src;
  REQUIRE(src.prepare(apm44::LibSamplerateSrc::Quality::Medium));

  constexpr std::size_t kInputFrames = 520;
  std::vector<float> in0(kInputFrames);
  std::vector<float> in1(kInputFrames);
  for (std::size_t i = 0; i < kInputFrames; ++i) {
    const double t = static_cast<double>(i) / 44100.0;
    const float sample = static_cast<float>(std::sin(2.0 * M_PI * 440.0 * t));
    in0[i] = sample;
    in1[i] = sample;
  }

  std::vector<float> out0(512);
  std::vector<float> out1(512);
  const float* inCh[2] = {in0.data(), in1.data()};
  float* outCh[2] = {out0.data(), out1.data()};
  std::size_t written = 0;
  REQUIRE(src.process(inCh, kInputFrames, outCh, out0.size(), written));
  REQUIRE(written == out0.size());

  std::vector<float> tail0(256);
  std::vector<float> tail1(256);
  float* tailCh[2] = {tail0.data(), tail1.data()};
  std::size_t tailWritten = 0;
  REQUIRE(src.flush(tailCh, tail0.size(), tailWritten));
  REQUIRE(tailWritten > 0);
}

TEST_CASE("LibSamplerateSrc reset starts a clean stream epoch", "[lib_samplerate_src][session]") {
  apm44::LibSamplerateSrc src;
  REQUIRE(src.prepare(apm44::LibSamplerateSrc::Quality::Medium));

  std::vector<float> stale0(520, 1.0f);
  std::vector<float> stale1(520, -1.0f);
  std::vector<float> output0(512);
  std::vector<float> output1(512);
  const float* staleChannels[2] = {stale0.data(), stale1.data()};
  float* outputChannels[2] = {output0.data(), output1.data()};
  std::size_t written = 0;
  REQUIRE(src.process(staleChannels, stale0.size(), outputChannels, output0.size(), written));
  REQUIRE(src.reset());

  std::vector<float> fresh0(147, 0.25f);
  std::vector<float> fresh1(147, -0.25f);
  const float* freshChannels[2] = {fresh0.data(), fresh1.data()};
  REQUIRE(src.process(freshChannels, fresh0.size(), outputChannels, output0.size(), written));
  REQUIRE(written > 0);
  for (std::size_t i = 0; i < written; ++i) {
    REQUIRE(output0[i] < 0.5f);
    REQUIRE(output1[i] > -0.5f);
  }
}
