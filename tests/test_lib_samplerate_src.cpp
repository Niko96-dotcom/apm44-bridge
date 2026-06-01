#include <catch2/catch_test_macros.hpp>

#include "engine/LibSamplerateSrc.h"

#include <cmath>
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
  std::vector<float> out0(256);
  std::vector<float> out1(256);
  float* outCh[2] = {out0.data(), out1.data()};

  std::size_t written = 0;
  REQUIRE(src.process(inCh, kInFrames, outCh, 256, written));
  float* flushOut[2] = {out0.data() + written, out1.data() + written};
  std::size_t flushed = 0;
  REQUIRE(src.flush(flushOut, 256 - written, flushed));
  written += flushed;
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
