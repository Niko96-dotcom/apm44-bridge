#include <catch2/catch_test_macros.hpp>

#include "engine/LibSamplerateSrc.h"

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

TEST_CASE("LibSamplerateSrc ratio drift simulation", "[lib_samplerate_src]") {
  std::vector<float> in0(147);
  std::vector<float> in1(147);
  std::vector<float> out0(512);
  std::vector<float> out1(512);

  const double nominal = 48000.0 / 44100.0;
  for (int block = 0; block < 100; ++block) {
    apm44::LibSamplerateSrc src;
    REQUIRE(src.prepare(apm44::LibSamplerateSrc::Quality::Medium));

    const double ppm = (block < 50) ? 100.0 : -100.0;
    src.setRatio(nominal * (1.0 + ppm / 1'000'000.0));

    for (std::size_t i = 0; i < in0.size(); ++i) {
      const float s = static_cast<float>(std::sin(2.0 * M_PI * 440.0 * static_cast<double>(i) / 44100.0));
      in0[i] = s;
      in1[i] = s;
    }

    const float* inCh[2] = {in0.data(), in1.data()};
    float* outCh[2] = {out0.data(), out1.data()};
    std::size_t written = 0;
    REQUIRE(src.process(inCh, in0.size(), outCh, out0.size(), written));
    REQUIRE(written > 0);
    for (std::size_t i = 0; i < written; ++i) {
      REQUIRE(std::isfinite(out0[i]));
      REQUIRE(std::isfinite(out1[i]));
    }
  }
}

TEST_CASE("LibSamplerateSrc quality enum maps to SRC_SINC constants", "[lib_samplerate_src]") {
  apm44::LibSamplerateSrc medium;
  apm44::LibSamplerateSrc high;
  apm44::LibSamplerateSrc best;
  REQUIRE(medium.prepare(apm44::LibSamplerateSrc::Quality::Medium));
  REQUIRE(high.prepare(apm44::LibSamplerateSrc::Quality::High));
  REQUIRE(best.prepare(apm44::LibSamplerateSrc::Quality::Best));
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
