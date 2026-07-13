#include "engine/IoProcHandlers.h"

#include "engine/BridgeControlLoop.h"
#include "engine/BridgeEngine.h"

#include <apm44/AudioFormats.h>

#include <algorithm>
#include <cstring>

namespace apm44 {

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
    const std::size_t frames =
        inputData->mBuffers[0].mDataByteSize / (sizeof(float) * asbd.mChannelsPerFrame);
    float* scratch[2] = {engine->inputScratch0(), engine->inputScratch1()};
    for (std::size_t offset = 0; offset < frames; offset += kMaxCallbackFrames) {
      const std::size_t chunk = std::min(kMaxCallbackFrames, frames - offset);
      for (std::size_t i = 0; i < chunk; ++i) {
        scratch[0][i] = interleaved[(offset + i) * 2 + 0];
        scratch[1][i] = interleaved[(offset + i) * 2 + 1];
      }
      const float* channels[2] = {scratch[0], scratch[1]};
      engine->onInput(channels, chunk);
    }
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
  const std::size_t b0Frames = inputData->mBuffers[0].mDataByteSize / sizeof(float);
  const std::size_t b1Frames = inputData->mBuffers[1].mDataByteSize / sizeof(float);
  const std::size_t frames = std::min(b0Frames, b1Frames);
  for (std::size_t offset = 0; offset < frames; offset += kMaxCallbackFrames) {
    const std::size_t chunk = std::min(kMaxCallbackFrames, frames - offset);
    const float* channels[2] = {b0 + offset, b1 + offset};
    engine->onInput(channels, chunk);
  }
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
    // Core Audio owns mDataByteSize; render every requested frame in
    // bounded, allocation-free chunks through the preallocated scratch.
    float* interleaved = static_cast<float*>(outputData->mBuffers[0].mData);
    if (interleaved == nullptr) {
      return noErr;
    }
    const std::size_t requestedFrames =
        outputData->mBuffers[0].mDataByteSize / (sizeof(float) * asbd.mChannelsPerFrame);
    float* scratch[2] = {engine->outputScratch0(), engine->outputScratch1()};
    for (std::size_t offset = 0; offset < requestedFrames; offset += kMaxCallbackFrames) {
      const std::size_t chunk = std::min(kMaxCallbackFrames, requestedFrames - offset);
      engine->onOutput(scratch, chunk);
      for (std::size_t i = 0; i < chunk; ++i) {
        interleaved[(offset + i) * 2 + 0] = scratch[0][i];
        interleaved[(offset + i) * 2 + 1] = scratch[1][i];
      }
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
  const std::size_t b0Frames = outputData->mBuffers[0].mDataByteSize / sizeof(float);
  const std::size_t b1Frames = outputData->mBuffers[1].mDataByteSize / sizeof(float);
  const std::size_t requestedFrames = std::min(b0Frames, b1Frames);
  for (std::size_t offset = 0; offset < requestedFrames; offset += kMaxCallbackFrames) {
    const std::size_t chunk = std::min(kMaxCallbackFrames, requestedFrames - offset);
    float* channels[2] = {b0 + offset, b1 + offset};
    engine->onOutput(channels, chunk);
  }
  for (std::size_t i = requestedFrames; i < b0Frames; ++i) {
    b0[i] = 0.0f;
  }
  for (std::size_t i = requestedFrames; i < b1Frames; ++i) {
    b1[i] = 0.0f;
  }
  return noErr;
}

}  // namespace apm44
