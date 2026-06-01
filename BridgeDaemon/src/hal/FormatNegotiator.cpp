#include "hal/FormatNegotiator.h"

#include <CoreAudio/CoreAudio.h>

#include <cmath>

namespace apm44 {

namespace {

std::optional<AudioStreamBasicDescription> ReadStreamFormat(AudioDeviceID deviceId,
                                                            bool input) {
  const AudioObjectPropertyScope scope =
      input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput;
  AudioObjectPropertyAddress address{kAudioDevicePropertyStreamFormat, scope,
                                     kAudioObjectPropertyElementMain};
  AudioStreamBasicDescription asbd{};
  UInt32 size = sizeof(asbd);
  if (AudioObjectGetPropertyData(deviceId, &address, 0, nullptr, &size, &asbd) != noErr) {
    return std::nullopt;
  }
  return asbd;
}

}  // namespace

std::optional<FormatNegotiationError> FormatNegotiator::negotiate(BridgeDevicePair& pair) {
  const auto inputFormat = ReadStreamFormat(pair.input.deviceId, true);
  if (!inputFormat) {
    return FormatNegotiationError{
        "Could not read input stream format for " + pair.input.name +
        ". Set BlackHole 2ch to 44100 Hz in Audio MIDI Setup."};
  }
  pair.inputAsbd = *inputFormat;

  const auto outputFormat = ReadStreamFormat(pair.output.deviceId, false);
  if (!outputFormat) {
    return FormatNegotiationError{
        "Could not read output stream format for " + pair.output.name +
        ". Set AirPods to 48000 Hz in Audio MIDI Setup (do not force 44100 on AirPods)."};
  }
  pair.outputAsbd = *outputFormat;

  if (!AsbdMatchesFloat32StereoNonInterleaved(pair.inputAsbd, kInputSampleRate)) {
    return FormatNegotiationError{
        "Input device '" + pair.input.name + "' is not float32 stereo non-interleaved @ 44100 Hz. "
        "Open Audio MIDI Setup and set BlackHole 2ch nominal rate to 44100 Hz."};
  }

  if (!AsbdMatchesFloat32StereoNonInterleaved(pair.outputAsbd, kOutputSampleRate)) {
    return FormatNegotiationError{
        "Output device '" + pair.output.name +
        "' is not float32 stereo non-interleaved @ 48000 Hz. "
        "Open Audio MIDI Setup and set AirPods Max USB-C to 48000 Hz (do not force 44100)."};
  }

  if (std::fabs(pair.input.nominalRate - kInputSampleRate) > 1.0) {
    return FormatNegotiationError{
        "Input nominal rate is " + std::to_string(static_cast<int>(pair.input.nominalRate)) +
        " Hz; expected 44100 Hz on BlackHole."};
  }

  if (std::fabs(pair.output.nominalRate - kOutputSampleRate) > 1.0) {
    return FormatNegotiationError{
        "Output nominal rate is " + std::to_string(static_cast<int>(pair.output.nominalRate)) +
        " Hz; expected 48000 Hz on AirPods."};
  }

  return std::nullopt;
}

std::optional<FormatNegotiationError> FormatNegotiator::negotiateVirtualOutput(
    BridgeDevicePair& pair) {
  pair.input.name = "APM44 Bridge (shm)";
  pair.input.uid = "com.niko.apm44.bridge.device";
  pair.input.nominalRate = kInputSampleRate;
  pair.inputAsbd = MakeFloat32StereoNonInterleaved(kInputSampleRate);

  const auto outputFormat = ReadStreamFormat(pair.output.deviceId, false);
  if (!outputFormat) {
    return FormatNegotiationError{
        "Could not read output stream format for " + pair.output.name +
        ". Set AirPods to 48000 Hz in Audio MIDI Setup."};
  }
  pair.outputAsbd = *outputFormat;

  if (!AsbdMatchesFloat32StereoNonInterleaved(pair.outputAsbd, kOutputSampleRate)) {
    return FormatNegotiationError{
        "Output device '" + pair.output.name +
        "' is not float32 stereo non-interleaved @ 48000 Hz."};
  }

  if (std::fabs(pair.output.nominalRate - kOutputSampleRate) > 1.0) {
    return FormatNegotiationError{
        "Output nominal rate is " + std::to_string(static_cast<int>(pair.output.nominalRate)) +
        " Hz; expected 48000 Hz on AirPods."};
  }

  return std::nullopt;
}

}  // namespace apm44
