#pragma once

#include <optional>
#include <string>

namespace apm44 {

struct CliOptions {
  bool showHelp = false;
  bool showVersion = false;
  bool listDevices = false;
  bool preflight = false;
  bool printConfig = false;
  std::optional<std::string> inputDeviceUid;
  std::optional<std::string> outputDeviceUid;
};

CliOptions ParseCliOptions(int argc, char* argv[]);

void PrintUsage(const char* programName);

}  // namespace apm44
