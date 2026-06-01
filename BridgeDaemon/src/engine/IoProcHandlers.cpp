#include "engine/IoProcHandlers.h"

#include "engine/BridgeEngine.h"

#include <apm44/AudioFormats.h>

#include <cstring>

namespace apm44 {

namespace {

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
    const std::size_t frames =
        inputData->mBuffers[0].mDataByteSize / (sizeof(float) * asbd.mChannelsPerFrame);
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
  const std::size_t frames = inputData->mBuffers[0].mDataByteSize / sizeof(float);
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
    float* interleaved = static_cast<float*>(outputData->mBuffers[0].mData);
    if (interleaved == nullptr) {
      return noErr;
    }
    const std::size_t frames =
        outputData->mBuffers[0].mDataByteSize / (sizeof(float) * asbd.mChannelsPerFrame);
    float* scratch[2] = {engine->outputScratch0(), engine->outputScratch1()};
    engine->onOutput(scratch, frames);
    for (std::size_t i = 0; i < frames; ++i) {
      interleaved[i * 2 + 0] = scratch[0][i];
      interleaved[i * 2 + 1] = scratch[1][i];
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
  const std::size_t frames = outputData->mBuffers[0].mDataByteSize / sizeof(float);
  float* channels[2] = {b0, b1};
  engine->onOutput(channels, frames);
  return noErr;
}

}  // namespace apm44
