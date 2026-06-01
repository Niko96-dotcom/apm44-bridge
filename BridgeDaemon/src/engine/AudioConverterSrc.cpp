#include "engine/AudioConverterSrc.h"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace apm44 {

namespace {

struct ConverterUserData {
  const float* channel0 = nullptr;
  const float* channel1 = nullptr;
  std::size_t framesAvailable = 0;
  std::size_t framesConsumed = 0;
};

OSStatus InputDataProc(AudioConverterRef,
                       UInt32* ioNumberDataPackets,
                       AudioBufferList* ioData,
                       AudioStreamPacketDescription**,
                       void* inUserData) {
  auto* user = static_cast<ConverterUserData*>(inUserData);
  const std::size_t requested = *ioNumberDataPackets;
  const std::size_t available = user->framesAvailable - user->framesConsumed;
  const std::size_t toProvide = std::min(requested, available);

  if (toProvide == 0) {
    *ioNumberDataPackets = 0;
    ioData->mBuffers[0].mData = nullptr;
    ioData->mBuffers[0].mDataByteSize = 0;
    return noErr;
  }

  float* dest = static_cast<float*>(ioData->mBuffers[0].mData);
  for (std::size_t i = 0; i < toProvide; ++i) {
    dest[i * 2 + 0] = user->channel0[user->framesConsumed + i];
    dest[i * 2 + 1] = user->channel1[user->framesConsumed + i];
  }
  user->framesConsumed += toProvide;
  *ioNumberDataPackets = static_cast<UInt32>(toProvide);
  ioData->mBuffers[0].mDataByteSize = static_cast<UInt32>(toProvide * 2 * sizeof(float));
  return noErr;
}

}  // namespace

AudioConverterSrc::~AudioConverterSrc() {
  if (converter_ != nullptr) {
    AudioConverterDispose(converter_);
    converter_ = nullptr;
  }
}

namespace {

AudioStreamBasicDescription MakeInterleavedFromNonInterleaved(
    const AudioStreamBasicDescription& nonInterleaved) {
  AudioStreamBasicDescription interleaved = nonInterleaved;
  interleaved.mFormatFlags =
      (interleaved.mFormatFlags & ~kAudioFormatFlagIsNonInterleaved) | kAudioFormatFlagIsPacked;
  interleaved.mBytesPerPacket = sizeof(float) * interleaved.mChannelsPerFrame;
  interleaved.mFramesPerPacket = 1;
  interleaved.mBytesPerFrame = interleaved.mBytesPerPacket;
  return interleaved;
}

}  // namespace

bool AudioConverterSrc::prepare(const AudioStreamBasicDescription& inputAsbd,
                                const AudioStreamBasicDescription& outputAsbd) {
  if (converter_ != nullptr) {
    AudioConverterDispose(converter_);
    converter_ = nullptr;
  }

  const auto inInterleaved = MakeInterleavedFromNonInterleaved(inputAsbd);
  const auto outInterleaved = MakeInterleavedFromNonInterleaved(outputAsbd);
  OSStatus status = AudioConverterNew(&inInterleaved, &outInterleaved, &converter_);
  if (status != noErr) {
    return false;
  }

  UInt32 primeMethod = kConverterPrimeMethod_None;
  AudioConverterSetProperty(converter_, kAudioConverterPrimeMethod, sizeof(primeMethod),
                            &primeMethod);

  nominalRatio_ = outputAsbd.mSampleRate / inputAsbd.mSampleRate;
  const std::size_t maxFrames = 4096;
  inputInterleaved_.resize(maxFrames * 2);
  outputInterleaved_.resize(static_cast<std::size_t>(std::ceil(maxFrames * nominalRatio_)) * 2);
  return true;
}

bool AudioConverterSrc::convert(const float* const inputChannels[2], std::size_t inputFrames,
                              float* const outputChannels[2], std::size_t outputCapacity,
                              std::size_t& outputFramesWritten) {
  outputFramesWritten = 0;
  if (converter_ == nullptr || inputFrames == 0) {
    return false;
  }

  ConverterUserData user{inputChannels[0], inputChannels[1], inputFrames, 0};

  const std::size_t expectedOut =
      static_cast<std::size_t>(std::lround(static_cast<double>(inputFrames) * nominalRatio_));
  const std::size_t maxOut =
      std::min(outputCapacity, std::max(expectedOut, static_cast<std::size_t>(1)));
  if (outputInterleaved_.size() < maxOut * 2) {
    outputInterleaved_.resize(maxOut * 2);
  }

  UInt32 outputPackets = static_cast<UInt32>(maxOut);
  AudioBufferList outputList{};
  outputList.mNumberBuffers = 1;
  outputList.mBuffers[0].mNumberChannels = 2;
  outputList.mBuffers[0].mData = outputInterleaved_.data();
  outputList.mBuffers[0].mDataByteSize = static_cast<UInt32>(maxOut * 2 * sizeof(float));

  const OSStatus status = AudioConverterFillComplexBuffer(
      converter_, InputDataProc, &user, &outputPackets, &outputList, nullptr);
  if (status != noErr && status != kAudioConverterErr_InvalidInputSize) {
    return false;
  }

  outputFramesWritten = outputPackets;
  for (std::size_t i = 0; i < outputFramesWritten; ++i) {
    outputChannels[0][i] = outputInterleaved_[i * 2 + 0];
    outputChannels[1][i] = outputInterleaved_[i * 2 + 1];
  }
  return true;
}

}  // namespace apm44
