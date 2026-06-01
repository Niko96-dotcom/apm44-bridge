#pragma once

#include <CoreAudio/CoreAudio.h>

namespace apm44 {

class BridgeEngine;

OSStatus InputIoProc(AudioDeviceID,
                     const AudioTimeStamp*,
                     const AudioBufferList* inputData,
                     const AudioTimeStamp*,
                     AudioBufferList*,
                     const AudioTimeStamp*,
                     void* clientData);

OSStatus OutputIoProc(AudioDeviceID,
                      const AudioTimeStamp*,
                      const AudioBufferList*,
                      const AudioTimeStamp*,
                      AudioBufferList* outputData,
                      const AudioTimeStamp*,
                      void* clientData);

}  // namespace apm44
