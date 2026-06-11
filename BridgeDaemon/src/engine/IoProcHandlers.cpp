#include "engine/IoProcHandlers.h"

#include "engine/BridgeControlLoop.h"
#include "engine/BridgeEngine.h"

#include <apm44/AudioFormats.h>

#include <algorithm>
#include <cstring>

namespace apm44 {

namespace {

std::size_t ClampCallbackFrames(std::size_t frames) {
  return std::min(frames, kMaxCallbackFrames);
}

void WriteSilence(AudioBufferList* bufferList, std::size_t frames) {
  if (bufferList == nullptr) {
    return;
  }
  for (UInt32 i = 0; i < bufferList->mNumberBuffers; ++i) {
    if (bufferList->mBuffers[i].mData != nullptr) {
      std::memset(bufferList->mBuffers[i].mData, 0, frames * sizeof(float));
    }
  }
}

}  // namespace

OSStatus InputIoProc(AudioDeviceID,
                     const AudioTimeStamp*,
                     const AudioBufferList* inputData,
                     const AudioTimeStamp*,
                     AudioBufferList*,
                     const AudioTimeStamp*,
                     void* clientData) {
  auto* engine = static_cast<BridgeEngine*>(clientData);
  if (inputData == nullptr || inputData->mNumberBuffers < 1) {
    return noErr;
  }
  const auto& asbd = engine->devices().inputAsbd;
  if (!AsbdIsNonInterleaved(asbd)) {
    const float* interleaved = static_cast<const float*>(inputData->mBuffers[0].mData);
    if (interleaved == nullptr) {
      return noErr;
    }
    std::size_t frames =
        inputData->mBuffers[0].mDataByteSize / (sizeof(float) * asbd.mChannelsPerFrame);
    frames = ClampCallbackFrames(frames);
    float* scratch[2] = {engine->inputScratch0(), engine->inputScratch1()};
    for (std::size_t i = 0; i < frames; ++i) {
      scratch[0][i] = interleaved[i * 2 + 0];
      scratch[1][i] = interleaved[i * 2 + 1];
    }
    const float* channels[2] = {scratch[0], scratch[1]};
    engine->onInput(channels, frames);
    return noErr;
  }
  if (inputData->mNumberBuffers < 2) {
    return noErr;
  }
  const float* b0 = static_cast<const float*>(inputData->mBuffers[0].mData);
  const float* b1 = static_cast<const float*>(inputData->mBuffers[1].mData);
  if (b0 == nullptr || b1 == nullptr) {
    return noErr;
  }
  std::size_t frames = inputData->mBuffers[0].mDataByteSize / sizeof(float);
  frames = ClampCallbackFrames(frames);
  const float* channels[2] = {b0, b1};
  engine->onInput(channels, frames);
  return noErr;
}

OSStatus OutputIoProc(AudioDeviceID,
                      const AudioTimeStamp*,
                      const AudioBufferList*,
                      const AudioTimeStamp*,
                      AudioBufferList* outputData,
                      const AudioTimeStamp*,
                      void* clientData) {
  auto* engine = static_cast<BridgeEngine*>(clientData);
  if (outputData == nullptr || outputData->mNumberBuffers < 1) {
    return noErr;
  }
  const auto& asbd = engine->devices().outputAsbd;
  if (!AsbdIsNonInterleaved(asbd)) {
    // RT-03 / RT-04: Core Audio owns mDataByteSize; we must write or
    // explicitly silence every frame it asked for. The internal scratch
    // (`kMaxCallbackFrames`) is smaller than the Core Audio request on
    // some devices — `ClampCallbackFrames` caps what the engine renders.
    // Silence the interleaved tail that the engine did not fill so the
    // audio thread never leaves stale samples for Core Audio to play.
    float* interleaved = static_cast<float*>(outputData->mBuffers[0].mData);
    if (interleaved == nullptr) {
      return noErr;
    }
    const std::size_t requestedFrames =
        outputData->mBuffers[0].mDataByteSize / (sizeof(float) * asbd.mChannelsPerFrame);
    const std::size_t framesToRender = ClampCallbackFrames(requestedFrames);
    float* scratch[2] = {engine->outputScratch0(), engine->outputScratch1()};
    engine->onOutput(scratch, framesToRender);
    for (std::size_t i = 0; i < framesToRender; ++i) {
      interleaved[i * 2 + 0] = scratch[0][i];
      interleaved[i * 2 + 1] = scratch[1][i];
    }
    // Silence the interleaved tail [framesToRender, requestedFrames).
    for (std::size_t i = framesToRender; i < requestedFrames; ++i) {
      interleaved[i * 2 + 0] = 0.0f;
      interleaved[i * 2 + 1] = 0.0f;
    }
    return noErr;
  }
  if (outputData->mNumberBuffers < 2) {
    return noErr;
  }
  float* b0 = static_cast<float*>(outputData->mBuffers[0].mData);
  float* b1 = static_cast<float*>(outputData->mBuffers[1].mData);
  if (b0 == nullptr || b1 == nullptr) {
    return noErr;
  }
  // RT-03 / RT-04: mirror the interleaved path. The engine renders up
  // to `kMaxCallbackFrames` into the supplied Core Audio buffers; the
  // tail beyond that is explicitly zeroed so no stale frames leak.
  const std::size_t b0Frames = outputData->mBuffers[0].mDataByteSize / sizeof(float);
  const std::size_t b1Frames = outputData->mBuffers[1].mDataByteSize / sizeof(float);
  const std::size_t requestedFrames = std::min(b0Frames, b1Frames);
  const std::size_t framesToRender = ClampCallbackFrames(requestedFrames);
  float* channels[2] = {b0, b1};
  engine->onOutput(channels, framesToRender);
  for (std::size_t i = framesToRender; i < b0Frames; ++i) {
    b0[i] = 0.0f;
  }
  for (std::size_t i = framesToRender; i < b1Frames; ++i) {
    b1[i] = 0.0f;
  }
  return noErr;
}

}  // namespace apm44
