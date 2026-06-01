#include <catch2/catch_test_macros.hpp>

#include <samplerate.h>

#include <cmath>
#include <vector>

// Nominal 44.1 kHz → 48 kHz streaming ratio (160/147).
TEST_CASE("libsamplerate smoke 147→~160 frames", "[libsamplerate_smoke]") {
  int error = 0;
  SRC_STATE* state = src_new(SRC_SINC_MEDIUM_QUALITY, 2, &error);
  REQUIRE(state != nullptr);
  REQUIRE(error == 0);

  constexpr std::size_t kInFrames = 147;
  std::vector<float> in(kInFrames * 2);
  for (std::size_t i = 0; i < kInFrames; ++i) {
    const double t = static_cast<double>(i) / 44100.0;
    const float s = static_cast<float>(std::sin(2.0 * M_PI * 440.0 * t));
    in[i * 2 + 0] = s;
    in[i * 2 + 1] = s;
  }

  std::vector<float> out(kInFrames * 2 + 64);
  SRC_DATA data{};
  data.src_ratio = 48000.0 / 44100.0;

  long inRemaining = static_cast<long>(kInFrames);
  long outTotal = 0;
  while (inRemaining > 0) {
    data.data_in = in.data() + static_cast<std::size_t>(kInFrames - inRemaining) * 2;
    data.data_out = out.data() + static_cast<std::size_t>(outTotal) * 2;
    data.input_frames = inRemaining;
    data.output_frames = static_cast<long>(out.size() / 2) - outTotal;
    data.end_of_input = 1;
    REQUIRE(src_process(state, &data) == 0);
    inRemaining -= data.input_frames_used;
    outTotal += data.output_frames_gen;
    if (data.input_frames_used == 0 && data.output_frames_gen == 0) {
      break;
    }
  }
  REQUIRE(outTotal > 0);

  const double ratio = static_cast<double>(outTotal) / static_cast<double>(kInFrames);
  REQUIRE(ratio > (160.0 / 147.0) * 0.95);
  REQUIRE(ratio < (160.0 / 147.0) * 1.05);

  src_delete(state);
}
