#include <apm44/MmapShmRing.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
#include <sys/mman.h>
#include <unistd.h>

namespace {

// Separate mappings exercise the HAL producer / daemon consumer copy path.
// The private name never opens or replaces the installed driver's ring.
struct Fixture {
  std::string name = "/apm44bench" + std::to_string(getpid());
  apm44::MmapShmRing producer{name};
  apm44::MmapShmRing consumer{name};
  ~Fixture() { shm_unlink(name.c_str()); }
};

void Check(bool condition) {
  if (!condition) throw std::runtime_error("ring transfer or sample check failed");
}

void Run(std::size_t frames, uint32_t capacity, bool planar) {
  Fixture f;
  Check(f.producer.create(capacity));
  Check(f.consumer.open(apm44::ShmRingRole::Consumer));
  std::vector<float> input(frames * 2), output(frames * 2);
  float* channels[2] = {output.data(), output.data() + frames};
  for (std::size_t i = 0; i < frames; ++i) {
    input[2 * i] = static_cast<float>(i + 1) / frames;
    input[2 * i + 1] = -input[2 * i];
  }
  auto transfer = [&] {
    Check(f.producer.pushInterleaved(input.data(), frames) == frames);
    Check((planar ? f.consumer.popToPlanar(channels, frames)
                  : f.consumer.popInterleaved(output.data(), frames)) == frames);
  };
  for (int i = 0; i < 2000; ++i) transfer();
  constexpr int repeats = 7;
  const std::size_t iterations = std::max(std::size_t{10000}, 16000000 / frames);
  std::vector<double> times;
  for (int repeat = 0; repeat < repeats; ++repeat) {
    const auto start = std::chrono::steady_clock::now();
    for (std::size_t i = 0; i < iterations; ++i) transfer();
    const double ns = std::chrono::duration<double, std::nano>(
        std::chrono::steady_clock::now() - start).count() / iterations;
    times.push_back(ns);
    // Keep complete sample/channel checks outside the timed region.
    for (std::size_t i = 0; i < frames; ++i) {
      Check(output[planar ? i : 2 * i] == input[2 * i]);
      Check(output[planar ? frames + i : 2 * i + 1] == input[2 * i + 1]);
    }
  }
  std::sort(times.begin(), times.end());
  std::cout << (planar ? "planar" : "interleaved") << ',' << capacity << ','
            << frames << ',' << iterations << ',' << times[repeats / 2] << ','
            << times.front() << ',' << times.back() << '\n';
}

}  // namespace

int main() {
  try {
    std::cerr << "build=" << apm44::kBuildId
              << " repeats=7 warmup=2000; ns per stereo push+pop pair\n";
    std::cout << std::fixed << std::setprecision(2)
              << "layout,capacity,frames,iterations,median_ns,min_ns,max_ns\n";
    // Include a non-power-of-two capacity and non-divisor block for wraparound.
    for (uint32_t capacity : {8192u, 8191u}) {
      for (std::size_t frames : {64u, 256u, 512u, 1023u, 4096u}) {
        Run(frames, capacity, false);
        Run(frames, capacity, true);
      }
    }
  } catch (const std::exception& error) {
    std::cerr << "error: " << error.what() << '\n';
    return EXIT_FAILURE;
  }
}
