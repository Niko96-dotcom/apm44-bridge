#include <catch2/catch_test_macros.hpp>

#include "engine/AudioConverterSrc.h"

#include <apm44/AudioFormats.h>

#include <cmath>
#include <vector>

TEST_CASE("AudioConverterSrc 147 to ~160 frames", "[audio_converter]") {
  apm44::AudioConverterSrc src;
  const auto inAsbd = apm44::MakeFloat32StereoNonInterleaved(44100.0);
  const auto outAsbd = apm44::MakeFloat32StereoNonInterleaved(48000.0);
  REQUIRE(src.prepare(inAsbd, outAsbd));

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
  REQUIRE(src.convert(inCh, kInFrames, outCh, 256, written));
  REQUIRE(written > 0);
  const double ratio = static_cast<double>(written) / static_cast<double>(kInFrames);
  REQUIRE(ratio > (160.0 / 147.0) * 0.95);
  REQUIRE(ratio < (160.0 / 147.0) * 1.05);
}
