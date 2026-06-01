#include "engine/IoProcHandlers.h"

#include "engine/BridgeEngine.h"

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
  if (inputData == nullptr || inputData->mNumberBuffers < 2) {
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
  if (outputData == nullptr || outputData->mNumberBuffers < 2) {
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
