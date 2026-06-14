#include "ShmIoHandler.h"
#include "DriverFormat.h"

#include <apm44/MmapShmRing.h>

#include <aspl/Device.hpp>

#include <catch2/catch_approx.hpp>
#include <catch2/catch_test_macros.hpp>

#include <sys/mman.h>
#include <unistd.h>

#include <memory>
#include <string>
#include <vector>

namespace {

std::string TestRingName(char suffix) {
  return "/apm44h" + std::to_string(static_cast<long long>(getpid())) + suffix;
}

}  // namespace

TEST_CASE("ShmIoHandler pushes canonical Float32 stereo mix without scaling",
          "[shm_io_handler]") {
  const std::string ringName = TestRingName('f');
  apm44::ShmIoHandler handler(ringName);
  REQUIRE(handler.OnStartIO() == kAudioHardwareNoError);

  apm44::MmapShmRing consumer(ringName);
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));

  std::vector<float> frames{
      -1.0f, 1.0f,
      -0.5f, 0.5f,
      0.125f, -0.125f,
      0.75f, -0.75f,
  };

  handler.OnProcessMixedOutput(nullptr, 0.0, 0.0, frames.data(), 4, 2);

  std::vector<float> out(frames.size());
  REQUIRE(consumer.popInterleaved(out.data(), 4) == 4);
  for (std::size_t i = 0; i < frames.size(); ++i) {
    REQUIRE(out[i] == Catch::Approx(frames[i]).margin(1e-7f));
  }

  handler.OnStopIO();
  consumer.close();
  shm_unlink(ringName.c_str());
}

TEST_CASE("ShmIoHandler combines Float32 mono lanes into stereo shm frames",
          "[shm_io_handler]") {
  const std::string ringName = TestRingName('m');
  apm44::ShmIoHandler handler(ringName);
  REQUIRE(handler.OnStartIO() == kAudioHardwareNoError);

  apm44::MmapShmRing consumer(ringName);
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));

  auto context = std::make_shared<aspl::Context>();
  aspl::DeviceParameters deviceParams;
  deviceParams.SampleRate = apm44::kApm44DriverSampleRate;
  deviceParams.ChannelCount = apm44::kApm44DriverChannelCount;
  auto device = std::make_shared<aspl::Device>(context, deviceParams);
  auto left = std::make_shared<apm44::Apm44OutputStream>(context, device, 1);
  auto right = std::make_shared<apm44::Apm44OutputStream>(context, device, 2);

  std::vector<float> leftFrames{0.25f, 0.5f, 0.75f};
  std::vector<float> rightFrames{-0.25f, -0.5f, -0.75f};

  handler.OnProcessMixedOutput(left, 0.0, 512.0, leftFrames.data(), 3, 1);

  std::vector<float> out(6);
  REQUIRE(consumer.popInterleaved(out.data(), 3) == 0);

  handler.OnProcessMixedOutput(right, 0.0, 512.0, rightFrames.data(), 3, 1);

  REQUIRE(consumer.popInterleaved(out.data(), 3) == 3);
  for (std::size_t frame = 0; frame < 3; ++frame) {
    REQUIRE(out[frame * 2 + 0] == Catch::Approx(leftFrames[frame]).margin(1e-7f));
    REQUIRE(out[frame * 2 + 1] == Catch::Approx(rightFrames[frame]).margin(1e-7f));
  }

  handler.OnStopIO();
  consumer.close();
  shm_unlink(ringName.c_str());
}

TEST_CASE("ShmIoHandler serialized left-right mono-lane callbacks form stereo frames",
          "[shm_io_handler][MONO-02]") {
  const std::string ringName = TestRingName('z');
  apm44::ShmIoHandler handler(ringName);
  REQUIRE(handler.OnStartIO() == kAudioHardwareNoError);

  apm44::MmapShmRing consumer(ringName);
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));

  auto context = std::make_shared<aspl::Context>();
  aspl::DeviceParameters deviceParams;
  deviceParams.SampleRate = apm44::kApm44DriverSampleRate;
  deviceParams.ChannelCount = apm44::kApm44DriverChannelCount;
  auto device = std::make_shared<aspl::Device>(context, deviceParams);
  auto left = std::make_shared<apm44::Apm44OutputStream>(context, device, 1);
  auto right = std::make_shared<apm44::Apm44OutputStream>(context, device, 2);

  std::vector<float> leftA{0.10f, 0.20f};
  std::vector<float> rightA{-0.10f, -0.20f};
  std::vector<float> leftB{0.30f, 0.40f};
  std::vector<float> rightB{-0.30f, -0.40f};

  handler.OnProcessMixedOutput(left, 0.0, 1024.0, leftA.data(), 2, 1);
  handler.OnProcessMixedOutput(right, 0.0, 1024.0, rightA.data(), 2, 1);
  handler.OnProcessMixedOutput(left, 0.0, 1026.0, leftB.data(), 2, 1);
  handler.OnProcessMixedOutput(right, 0.0, 1026.0, rightB.data(), 2, 1);

  std::vector<float> out(8);
  REQUIRE(consumer.popInterleaved(out.data(), 4) == 4);
  REQUIRE(out[0] == Catch::Approx(leftA[0]).margin(1e-7f));
  REQUIRE(out[1] == Catch::Approx(rightA[0]).margin(1e-7f));
  REQUIRE(out[2] == Catch::Approx(leftA[1]).margin(1e-7f));
  REQUIRE(out[3] == Catch::Approx(rightA[1]).margin(1e-7f));
  REQUIRE(out[4] == Catch::Approx(leftB[0]).margin(1e-7f));
  REQUIRE(out[5] == Catch::Approx(rightB[0]).margin(1e-7f));
  REQUIRE(out[6] == Catch::Approx(leftB[1]).margin(1e-7f));
  REQUIRE(out[7] == Catch::Approx(rightB[1]).margin(1e-7f));

  handler.OnStopIO();
  consumer.close();
  shm_unlink(ringName.c_str());
}

TEST_CASE("ShmIoHandler pairs mono lanes across HAL timestamp period rollover",
          "[shm_io_handler]") {
  const std::string ringName = TestRingName('r');
  apm44::ShmIoHandler handler(ringName);
  REQUIRE(handler.OnStartIO() == kAudioHardwareNoError);

  apm44::MmapShmRing consumer(ringName);
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));

  auto context = std::make_shared<aspl::Context>();
  aspl::DeviceParameters deviceParams;
  deviceParams.SampleRate = apm44::kApm44DriverSampleRate;
  deviceParams.ChannelCount = apm44::kApm44DriverChannelCount;
  auto device = std::make_shared<aspl::Device>(context, deviceParams);
  auto left = std::make_shared<apm44::Apm44OutputStream>(context, device, 1);
  auto right = std::make_shared<apm44::Apm44OutputStream>(context, device, 2);

  std::vector<float> leftFrames{0.10f, 0.20f, 0.30f};
  std::vector<float> rightFrames{-0.10f, -0.20f, -0.30f};

  handler.OnProcessMixedOutput(left, 0.0, 44032.0, leftFrames.data(), 3, 1);
  handler.OnProcessMixedOutput(right, 44100.0, 0.0, rightFrames.data(), 3, 1);

  std::vector<float> out(6);
  REQUIRE(consumer.popInterleaved(out.data(), 3) == 3);
  for (std::size_t frame = 0; frame < 3; ++frame) {
    REQUIRE(out[frame * 2 + 0] == Catch::Approx(leftFrames[frame]).margin(1e-7f));
    REQUIRE(out[frame * 2 + 1] == Catch::Approx(rightFrames[frame]).margin(1e-7f));
  }

  handler.OnStopIO();
  consumer.close();
  shm_unlink(ringName.c_str());
}

TEST_CASE("ShmIoHandler rejects unrelated mono lane timestamp mismatches",
          "[shm_io_handler]") {
  const std::string ringName = TestRingName('x');
  apm44::ShmIoHandler handler(ringName);
  REQUIRE(handler.OnStartIO() == kAudioHardwareNoError);

  apm44::MmapShmRing consumer(ringName);
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));

  auto context = std::make_shared<aspl::Context>();
  aspl::DeviceParameters deviceParams;
  deviceParams.SampleRate = apm44::kApm44DriverSampleRate;
  deviceParams.ChannelCount = apm44::kApm44DriverChannelCount;
  auto device = std::make_shared<aspl::Device>(context, deviceParams);
  auto left = std::make_shared<apm44::Apm44OutputStream>(context, device, 1);
  auto right = std::make_shared<apm44::Apm44OutputStream>(context, device, 2);

  std::vector<float> leftFrames{0.10f, 0.20f, 0.30f};
  std::vector<float> rightFrames{-0.10f, -0.20f, -0.30f};

  handler.OnProcessMixedOutput(left, 0.0, 100.0, leftFrames.data(), 3, 1);
  handler.OnProcessMixedOutput(right, 0.0, 400.0, rightFrames.data(), 3, 1);

  std::vector<float> out(6);
  REQUIRE(consumer.popInterleaved(out.data(), 3) == 0);

  handler.OnStopIO();
  consumer.close();
  shm_unlink(ringName.c_str());
}

TEST_CASE("ShmIoHandler ignores mixed output after IO stops", "[shm_io_handler]") {
  const std::string ringName = TestRingName('s');
  apm44::ShmIoHandler handler(ringName);
  REQUIRE(handler.OnStartIO() == kAudioHardwareNoError);

  apm44::MmapShmRing consumer(ringName);
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));

  handler.OnStopIO();

  std::vector<float> frames{
      -1.0f, 1.0f,
      -0.5f, 0.5f,
      0.125f, -0.125f,
  };
  handler.OnProcessMixedOutput(nullptr, 0.0, 0.0, frames.data(), 3, 2);

  std::vector<float> out(frames.size());
  REQUIRE(consumer.popInterleaved(out.data(), 3) == 0);

  consumer.close();
  shm_unlink(ringName.c_str());
}

TEST_CASE("ShmIoHandler drops incomplete mono lane when same channel repeats",
          "[shm_io_handler]") {
  const std::string ringName = TestRingName('d');
  apm44::ShmIoHandler handler(ringName);
  REQUIRE(handler.OnStartIO() == kAudioHardwareNoError);

  apm44::MmapShmRing consumer(ringName);
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));

  auto context = std::make_shared<aspl::Context>();
  aspl::DeviceParameters deviceParams;
  deviceParams.SampleRate = apm44::kApm44DriverSampleRate;
  deviceParams.ChannelCount = apm44::kApm44DriverChannelCount;
  auto device = std::make_shared<aspl::Device>(context, deviceParams);
  auto left = std::make_shared<apm44::Apm44OutputStream>(context, device, 1);
  auto right = std::make_shared<apm44::Apm44OutputStream>(context, device, 2);

  std::vector<float> staleLeft{0.10f, 0.20f, 0.30f};
  std::vector<float> currentLeft{0.40f, 0.50f, 0.60f};
  std::vector<float> currentRight{-0.40f, -0.50f, -0.60f};

  handler.OnProcessMixedOutput(left, 0.0, 100.0, staleLeft.data(), 3, 1);
  handler.OnProcessMixedOutput(left, 0.0, 200.0, currentLeft.data(), 3, 1);
  handler.OnProcessMixedOutput(right, 0.0, 200.0, currentRight.data(), 3, 1);

  std::vector<float> out(6);
  REQUIRE(consumer.popInterleaved(out.data(), 3) == 3);
  for (std::size_t frame = 0; frame < 3; ++frame) {
    REQUIRE(out[frame * 2 + 0] == Catch::Approx(currentLeft[frame]).margin(1e-7f));
    REQUIRE(out[frame * 2 + 1] == Catch::Approx(currentRight[frame]).margin(1e-7f));
  }

  handler.OnStopIO();
  consumer.close();
  shm_unlink(ringName.c_str());
}

TEST_CASE("ShmIoHandler queues repeated mono lanes until matching channel arrives",
          "[shm_io_handler]") {
  const std::string ringName = TestRingName('q');
  apm44::ShmIoHandler handler(ringName);
  REQUIRE(handler.OnStartIO() == kAudioHardwareNoError);

  apm44::MmapShmRing consumer(ringName);
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));

  auto context = std::make_shared<aspl::Context>();
  aspl::DeviceParameters deviceParams;
  deviceParams.SampleRate = apm44::kApm44DriverSampleRate;
  deviceParams.ChannelCount = apm44::kApm44DriverChannelCount;
  auto device = std::make_shared<aspl::Device>(context, deviceParams);
  auto left = std::make_shared<apm44::Apm44OutputStream>(context, device, 1);
  auto right = std::make_shared<apm44::Apm44OutputStream>(context, device, 2);

  std::vector<float> leftA{0.10f, 0.20f, 0.30f};
  std::vector<float> leftB{0.40f, 0.50f, 0.60f};
  std::vector<float> rightA{-0.10f, -0.20f, -0.30f};
  std::vector<float> rightB{-0.40f, -0.50f, -0.60f};

  handler.OnProcessMixedOutput(left, 0.0, 100.0, leftA.data(), 3, 1);
  handler.OnProcessMixedOutput(left, 0.0, 200.0, leftB.data(), 3, 1);
  handler.OnProcessMixedOutput(right, 0.0, 100.0, rightA.data(), 3, 1);
  handler.OnProcessMixedOutput(right, 0.0, 200.0, rightB.data(), 3, 1);

  std::vector<float> out(12);
  REQUIRE(consumer.popInterleaved(out.data(), 6) == 6);
  for (std::size_t frame = 0; frame < 3; ++frame) {
    REQUIRE(out[frame * 2 + 0] == Catch::Approx(leftA[frame]).margin(1e-7f));
    REQUIRE(out[frame * 2 + 1] == Catch::Approx(rightA[frame]).margin(1e-7f));
  }
  for (std::size_t frame = 0; frame < 3; ++frame) {
    const std::size_t outFrame = frame + 3;
    REQUIRE(out[outFrame * 2 + 0] == Catch::Approx(leftB[frame]).margin(1e-7f));
    REQUIRE(out[outFrame * 2 + 1] == Catch::Approx(rightB[frame]).margin(1e-7f));
  }

  handler.OnStopIO();
  consumer.close();
  shm_unlink(ringName.c_str());
}

TEST_CASE("ShmIoHandler ignores mono buffers without a stream lane", "[shm_io_handler]") {
  const std::string ringName = TestRingName('n');
  apm44::ShmIoHandler handler(ringName);
  REQUIRE(handler.OnStartIO() == kAudioHardwareNoError);

  apm44::MmapShmRing consumer(ringName);
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));

  std::vector<float> mono{0.25f, 0.5f, 0.75f};
  handler.OnProcessMixedOutput(nullptr, 0.0, 0.0, mono.data(), 3, 1);

  std::vector<float> out(6);
  REQUIRE(consumer.popInterleaved(out.data(), 3) == 0);

  handler.OnStopIO();
  consumer.close();
  shm_unlink(ringName.c_str());
}
