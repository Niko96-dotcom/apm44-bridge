#include "CliOptions.h"

#include <algorithm>
#include <cctype>
#include <cerrno>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <string_view>

namespace apm44 {

namespace {

bool IsFlag(std::string_view arg) { return !arg.empty() && arg[0] == '-'; }

std::string TrimCopy(std::string_view value) {
  while (!value.empty() && std::isspace(static_cast<unsigned char>(value.front()))) {
    value.remove_prefix(1);
  }
  while (!value.empty() && std::isspace(static_cast<unsigned char>(value.back()))) {
    value.remove_suffix(1);
  }
  return std::string{value};
}

std::optional<std::string> ValueAfter(int argc, char* argv[], int& index) {
  if (index + 1 >= argc) {
    return std::nullopt;
  }
  const std::string_view next{argv[index + 1]};
  if (IsFlag(next)) {
    return std::nullopt;
  }
  ++index;
  return TrimCopy(argv[index]);
}

// Accepts only a complete, finite decimal token: "15junk" and "nan" are
// rejected rather than read as 15 and NaN.
std::optional<double> ParseFiniteNumber(const std::string& value) {
  if (value.empty()) {
    return std::nullopt;
  }
  errno = 0;
  char* end = nullptr;
  const double parsed = std::strtod(value.c_str(), &end);
  if (end != value.c_str() + value.size() || errno == ERANGE || !std::isfinite(parsed)) {
    return std::nullopt;
  }
  return parsed;
}

std::optional<LibSamplerateSrc::Quality> ParseSrcQuality(std::string_view value) {
  if (value == "medium") {
    return LibSamplerateSrc::Quality::Medium;
  }
  if (value == "high") {
    return LibSamplerateSrc::Quality::High;
  }
  if (value == "best") {
    return LibSamplerateSrc::Quality::Best;
  }
  return std::nullopt;
}

}  // namespace

void PrintUsage(const char* programName) {
  std::cout << "APM44 Bridge — BlackHole @ 44.1 kHz → AirPods @ 48 kHz\n\n"
            << "Usage: " << programName << " [options]\n\n"
            << "Options:\n"
            << "  --help              Show this help\n"
            << "  --version           Show version\n"
            << "  --list-devices      List Core Audio devices and endpoint properties\n"
            << "  --preflight         Validate devices/rates without starting audio\n"
            << "  --print-config      Print resolved device/config (no audio)\n"
            << "  --shm-status        Check APM44Bridge.driver shared-memory ring once\n"
            << "  --input-device UID  Input device UID (default: BlackHole 2ch)\n"
            << "  --output-device UID Output device UID (default: AirPods Max)\n"
            << "  --target-fill-ms N  Ring target fill 6–120 ms (default 15)\n"
            << "  --src-quality Q     SRC quality: medium|high|best (default medium)\n"
            << "  --metrics-json      Emit JSON metrics on stdout every 500 ms while running\n"
            << "  --virtual-device    Read input from APM44Bridge.driver shm (no BlackHole)\n\n"
            << "  --parent-watch-stdin Stop if the launching app's stdin pipe closes\n\n"
            << "Prerequisite: BlackHole 2ch v0.6.1+ (user-installed, GPL-3.0).\n"
            << "  https://github.com/ExistentialAudio/BlackHole/releases\n"
            << "  Do not bundle or vendor BlackHole in this project.\n";
}

CliOptions ParseCliOptions(int argc, char* argv[]) {
  CliOptions options;
  const auto usageError = [&options](std::string_view message) {
    std::cerr << "error: " << message << "\n";
    options.usageError = true;
    return options;
  };
  for (int i = 1; i < argc; ++i) {
    const std::string_view arg{argv[i]};
    if (arg == "--help" || arg == "-h") {
      options.showHelp = true;
    } else if (arg == "--version") {
      options.showVersion = true;
    } else if (arg == "--list-devices") {
      options.listDevices = true;
    } else if (arg == "--preflight") {
      options.preflight = true;
    } else if (arg == "--print-config") {
      options.printConfig = true;
    } else if (arg == "--shm-status") {
      options.shmStatus = true;
    } else if (arg == "--metrics-json") {
      options.metricsJson = true;
    } else if (arg == "--virtual-device") {
      options.virtualDevice = true;
    } else if (arg == "--parent-watch-stdin") {
      options.parentWatchStdin = true;
    } else if (arg == "--input-device") {
      options.inputDeviceUid = ValueAfter(argc, argv, i);
      if (!options.inputDeviceUid || options.inputDeviceUid->empty()) {
        return usageError("--input-device requires a UID");
      }
    } else if (arg == "--output-device") {
      options.outputDeviceUid = ValueAfter(argc, argv, i);
      if (!options.outputDeviceUid || options.outputDeviceUid->empty()) {
        return usageError("--output-device requires a UID");
      }
    } else if (arg == "--target-fill-ms") {
      const auto value = ValueAfter(argc, argv, i);
      if (!value) {
        return usageError("--target-fill-ms requires a value");
      }
      const auto parsed = ParseFiniteNumber(*value);
      if (!parsed) {
        return usageError("invalid --target-fill-ms value");
      }
      if (*parsed < 6.0 || *parsed > 120.0) {
        return usageError("--target-fill-ms must be between 6 and 120");
      }
      options.targetFillMs = *parsed;
    } else if (arg == "--src-quality") {
      const auto value = ValueAfter(argc, argv, i);
      if (!value) {
        return usageError("--src-quality requires medium|high|best");
      }
      const auto quality = ParseSrcQuality(*value);
      if (!quality) {
        return usageError("unknown --src-quality (use medium|high|best)");
      }
      options.srcQuality = *quality;
    } else {
      return usageError("unknown option " + std::string{arg});
    }
  }
  return options;
}

const char* SrcQualityCliString(LibSamplerateSrc::Quality quality) {
  switch (quality) {
    case LibSamplerateSrc::Quality::High:
      return "high";
    case LibSamplerateSrc::Quality::Best:
      return "best";
    case LibSamplerateSrc::Quality::Medium:
    default:
      return "medium";
  }
}

BridgeEngineOptions ToEngineOptions(const CliOptions& cli) {
  BridgeEngineOptions engine;
  engine.targetFillMs = cli.targetFillMs;
  engine.srcQuality = cli.srcQuality;
  engine.virtualDevice = cli.virtualDevice;
  return engine;
}

}  // namespace apm44
