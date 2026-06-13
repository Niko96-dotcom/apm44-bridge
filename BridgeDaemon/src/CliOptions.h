#pragma once

#include "engine/BridgeEngine.h"
#include "engine/LibSamplerateSrc.h"

#include <optional>
#include <string>

namespace apm44 {

struct CliOptions {
  bool showHelp = false;
  bool showVersion = false;
  bool listDevices = false;
  bool preflight = false;
  bool printConfig = false;
  bool shmStatus = false;
  std::optional<std::string> inputDeviceUid;
  std::optional<std::string> outputDeviceUid;

  double targetFillMs = 15.0;
  LibSamplerateSrc::Quality srcQuality = LibSamplerateSrc::Quality::Medium;
  bool metricsJson = false;
  bool virtualDevice = false;
};

CliOptions ParseCliOptions(int argc, char* argv[]);

void PrintUsage(const char* programName);

BridgeEngineOptions ToEngineOptions(const CliOptions& cli);

const char* SrcQualityCliString(LibSamplerateSrc::Quality quality);

}  // namespace apm44
