#include "engine/BridgeEngine.h"
#include "engine/IoProcHandlers.h"

#include <apm44/AudioFormats.h>

#include <catch2/catch_test_macros.hpp>

#include <cmath>
#include <cstddef>
#include <limits>
#include <vector>

namespace {

constexpr std::size_t kLargeCallbackFrames = 4096;

AudioStreamBasicDescription MakeInterleavedStereo(double sampleRate) {
  AudioStreamBasicDescription asbd{};
  asbd.mSampleRate = sampleRate;
  asbd.mFormatID = kAudioFormatLinearPCM;
  asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
  asbd.mBytesPerPacket = sizeof(float) * 2;
  asbd.mFramesPerPacket = 1;
  asbd.mBytesPerFrame = sizeof(float) * 2;
  asbd.mChannelsPerFrame = 2;
  asbd.mBitsPerChannel = 32;
  return asbd;
}

void PrepareEngine(apm44::BridgeEngine& engine, bool nonInterleaved) {
  apm44::BridgeDevicePair devices;
  devices.inputAsbd = nonInterleaved
                          ? apm44::MakeFloat32StereoNonInterleaved(apm44::kInputSampleRate)
                          : MakeInterleavedStereo(apm44::kInputSampleRate);
  devices.outputAsbd = nonInterleaved
                           ? apm44::MakeFloat32StereoNonInterleaved(apm44::kOutputSampleRate)
                           : MakeInterleavedStereo(apm44::kOutputSampleRate);
  REQUIRE(engine.prepare(devices));
}

struct TwoBufferList {
  UInt32 mNumberBuffers = 2;
  AudioBuffer mBuffers[2]{};
};

}  // namespace

TEST_CASE("testOutputCallbackRendersAll4096RequestedFrames",
          "[io_proc][rt][large_callback]") {
  apm44::BridgeEngine engine;
  PrepareEngine(engine, false);
  const float sentinel = std::numeric_limits<float>::quiet_NaN();
  std::vector<float> output(kLargeCallbackFrames * 2, sentinel);
  AudioBufferList buffers{};
  buffers.mNumberBuffers = 1;
  buffers.mBuffers[0].mNumberChannels = 2;
  buffers.mBuffers[0].mDataByteSize =
      static_cast<UInt32>(output.size() * sizeof(float));
  buffers.mBuffers[0].mData = output.data();

  const uint64_t before = engine.outputFramesProcessed();
  REQUIRE(apm44::OutputIoProc(0, nullptr, nullptr, nullptr, &buffers, nullptr, &engine) == noErr);

  REQUIRE(engine.outputFramesProcessed() - before == kLargeCallbackFrames);
  for (float sample : output) {
    REQUIRE(std::isfinite(sample));
  }
}

TEST_CASE("production planar output callback renders every large buffer frame",
          "[io_proc][rt][large_callback]") {
  apm44::BridgeEngine engine;
  PrepareEngine(engine, true);
  const float sentinel = std::numeric_limits<float>::quiet_NaN();
  std::vector<float> left(kLargeCallbackFrames, sentinel);
  std::vector<float> right(kLargeCallbackFrames, sentinel);
  TwoBufferList storage;
  storage.mBuffers[0] = AudioBuffer{
      1, static_cast<UInt32>(left.size() * sizeof(float)), left.data()};
  storage.mBuffers[1] = AudioBuffer{
      1, static_cast<UInt32>(right.size() * sizeof(float)), right.data()};

  const uint64_t before = engine.outputFramesProcessed();
  auto* buffers = reinterpret_cast<AudioBufferList*>(&storage);
  REQUIRE(apm44::OutputIoProc(0, nullptr, nullptr, nullptr, buffers, nullptr, &engine) == noErr);

  REQUIRE(engine.outputFramesProcessed() - before == kLargeCallbackFrames);
  for (std::size_t i = 0; i < kLargeCallbackFrames; ++i) {
    REQUIRE(std::isfinite(left[i]));
    REQUIRE(std::isfinite(right[i]));
  }
}

TEST_CASE("production interleaved input callback accounts for all 4096 frames",
          "[io_proc][rt][large_callback]") {
  apm44::BridgeEngine engine;
  PrepareEngine(engine, false);
  std::vector<float> input(kLargeCallbackFrames * 2, 0.25f);
  AudioBufferList buffers{};
  buffers.mNumberBuffers = 1;
  buffers.mBuffers[0].mNumberChannels = 2;
  buffers.mBuffers[0].mDataByteSize =
      static_cast<UInt32>(input.size() * sizeof(float));
  buffers.mBuffers[0].mData = input.data();

  const uint64_t before = engine.inputFramesProcessed();
  REQUIRE(apm44::InputIoProc(0, nullptr, &buffers, nullptr, nullptr, nullptr, &engine) == noErr);
  REQUIRE(engine.inputFramesProcessed() - before == kLargeCallbackFrames);
}

TEST_CASE("production planar input uses the shortest channel without truncating it",
          "[io_proc][rt][large_callback]") {
  apm44::BridgeEngine engine;
  PrepareEngine(engine, true);
  std::vector<float> left(2048, 0.25f);
  std::vector<float> right(4096, -0.25f);
  TwoBufferList storage;
  storage.mBuffers[0] = AudioBuffer{
      1, static_cast<UInt32>(left.size() * sizeof(float)), left.data()};
  storage.mBuffers[1] = AudioBuffer{
      1, static_cast<UInt32>(right.size() * sizeof(float)), right.data()};

  const uint64_t before = engine.inputFramesProcessed();
  const auto* buffers = reinterpret_cast<const AudioBufferList*>(&storage);
  REQUIRE(apm44::InputIoProc(0, nullptr, buffers, nullptr, nullptr, nullptr, &engine) == noErr);
  REQUIRE(engine.inputFramesProcessed() - before == left.size());
}

TEST_CASE("testUnderrunDoesNotReplayStaleSrcHistory",
          "[io_proc][underrun][F-06]") {
  apm44::BridgeEngine engine;
  apm44::BridgeDevicePair devices;
  devices.inputAsbd = apm44::MakeFloat32StereoNonInterleaved(apm44::kInputSampleRate);
  devices.outputAsbd = apm44::MakeFloat32StereoNonInterleaved(apm44::kOutputSampleRate);
  apm44::BridgeEngineOptions options;
  options.targetFillMs = 0.0;
  REQUIRE(engine.prepare(devices, options));

  constexpr std::size_t kFrames = 512;
  std::vector<float> old0(kFrames, 0.8f);
  std::vector<float> old1(kFrames, 0.8f);
  const float* oldChannels[2] = {old0.data(), old1.data()};
  engine.onInput(oldChannels, kFrames);

  std::vector<float> output0(kFrames);
  std::vector<float> output1(kFrames);
  float* outputChannels[2] = {output0.data(), output1.data()};
  engine.onOutput(outputChannels, kFrames);
  engine.onOutput(outputChannels, kFrames);
  engine.onOutput(outputChannels, kFrames);
  REQUIRE(output0.back() == 0.0f);
  REQUIRE(output1.back() == 0.0f);

  std::vector<float> fresh0(kFrames, -0.8f);
  std::vector<float> fresh1(kFrames, -0.8f);
  const float* freshChannels[2] = {fresh0.data(), fresh1.data()};
  engine.onInput(freshChannels, kFrames);
  engine.onOutput(outputChannels, kFrames);

  bool observedFreshSignal = false;
  for (std::size_t i = 0; i < kFrames; ++i) {
    REQUIRE(std::isfinite(output0[i]));
    REQUIRE(std::isfinite(output1[i]));
    REQUIRE(output0[i] < 0.05f);
    REQUIRE(output1[i] < 0.05f);
    if (i > 0) {
      REQUIRE(std::abs(output0[i] - output0[i - 1]) < 0.2f);
      REQUIRE(std::abs(output1[i] - output1[i - 1]) < 0.2f);
    }
    observedFreshSignal = observedFreshSignal || output0[i] < -0.1f;
  }
  REQUIRE(observedFreshSignal);
  REQUIRE(engine.metricsSnapshot().outputStarvationFrames > 0);
}
