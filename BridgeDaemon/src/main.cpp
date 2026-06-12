#include "CliOptions.h"
#include "engine/BridgeEngine.h"
#include "engine/BridgeMetrics.h"
#include "hal/DeviceEnumerator.h"
#include "hal/FormatNegotiator.h"

#include <apm44/AudioFormats.h>
#include <apm44/MmapShmRing.h>

#include <apm44/ShmObjectIdentity.h>

#include <cerrno>
#include <iostream>
#include <optional>

namespace {

constexpr int kExitStaleShmRing = 42;

std::optional<apm44::BridgeDevicePair> ResolveDevices(const apm44::CliOptions& options,
                                                      bool requirePresent) {
  apm44::DeviceEnumerator enumerator;
  std::optional<apm44::AudioDeviceInfo> input;
  if (!options.virtualDevice) {
    input = enumerator.resolveInput(options.inputDeviceUid);
    if (!input) {
      if (requirePresent) {
        std::cerr
            << "error: input device not found. Install BlackHole 2ch or pass --input-device UID\n";
      }
      return std::nullopt;
    }
  }
  auto output = enumerator.resolveOutput(options.outputDeviceUid);
  if (!output) {
    if (requirePresent) {
      if (options.outputDeviceUid) {
        std::cerr << "error: output device UID not found: \"" << *options.outputDeviceUid
                  << "\"\nRun --list-devices and copy the UID column only (no tabs or device name).\n";
      } else {
        std::cerr << "error: output device not found. Connect AirPods Max USB-C or pass --output-device UID\n";
      }
      std::cerr << "Output devices currently visible:\n";
      for (const auto& device : enumerator.listAll()) {
        if (device.hasOutput) {
          std::cerr << "  " << device.uid << "  (" << device.name << " @ "
                    << static_cast<int>(device.nominalRate) << " Hz)\n";
        }
      }
    }
    return std::nullopt;
  }

  apm44::BridgeDevicePair pair;
  if (input) {
    pair.input = *input;
  }
  pair.output = *output;
  return pair;
}

std::optional<apm44::FormatNegotiationError> NegotiatePair(apm44::FormatNegotiator& negotiator,
                                                             apm44::BridgeDevicePair& pair,
                                                             bool virtualDevice) {
  if (virtualDevice) {
    return negotiator.negotiateVirtualOutput(pair);
  }
  return negotiator.negotiate(pair);
}

int RunPreflight(const apm44::CliOptions& options) {
  auto pair = ResolveDevices(options, true);
  if (!pair) {
    return 1;
  }

  apm44::FormatNegotiator negotiator;
  if (const auto err = NegotiatePair(negotiator, *pair, options.virtualDevice)) {
    std::cerr << "error: " << err->message << "\n";
    return 1;
  }

  std::cerr << "preflight OK: input='" << pair->input.name << "' (" << pair->input.uid
            << ") @ " << pair->input.nominalRate << " Hz\n";
  std::cerr << "preflight OK: output='" << pair->output.name << "' (" << pair->output.uid
            << ") @ " << pair->output.nominalRate << " Hz\n";
  return 0;
}

int RunPrintConfig(const apm44::CliOptions& options) {
  auto pair = ResolveDevices(options, true);
  if (!pair) {
    return 1;
  }
  apm44::FormatNegotiator negotiator;
  if (const auto err = NegotiatePair(negotiator, *pair, options.virtualDevice)) {
    std::cerr << "error: " << err->message << "\n";
    return 1;
  }

  const apm44::BridgeEngineOptions engineOptions = apm44::ToEngineOptions(options);

  apm44::BridgeEngine engine;
  if (!engine.prepare(*pair, engineOptions)) {
    std::cerr << "error: engine prepare failed\n";
    return 1;
  }

  std::cout << "input_uid=" << pair->input.uid << "\n";
  std::cout << "input_name=" << pair->input.name << "\n";
  std::cout << "input_rate=" << pair->input.nominalRate << "\n";
  std::cout << "output_uid=" << pair->output.uid << "\n";
  std::cout << "output_name=" << pair->output.name << "\n";
  std::cout << "output_rate=" << pair->output.nominalRate << "\n";
  std::cout << "ring_capacity=" << engine.ringCapacity() << "\n";
  std::cout << "converter_ratio=" << engine.converterRatio() << "\n";
  return 0;
}

int RunListDevices() {
  apm44::DeviceEnumerator enumerator;
  std::cout << "UID\tNAME\tRATE\tI/O\n";
  for (const auto& device : enumerator.listAll()) {
    std::string io;
    if (device.hasInput) {
      io += 'I';
    }
    if (device.hasOutput) {
      io += 'O';
    }
    std::cout << device.uid << '\t' << device.name << '\t' << device.nominalRate << '\t' << io
              << '\n';
  }
  return 0;
}

const char* ShmErrorCodeName(apm44::ShmRingErrorCode code) {
  switch (code) {
    case apm44::ShmRingErrorCode::None:
      return "none";
    case apm44::ShmRingErrorCode::OpenFailed:
      return "open_failed";
    case apm44::ShmRingErrorCode::CreateFailed:
      return "create_failed";
    case apm44::ShmRingErrorCode::PermissionFailed:
      return "permission_failed";
    case apm44::ShmRingErrorCode::TruncateFailed:
      return "truncate_failed";
    case apm44::ShmRingErrorCode::StatFailed:
      return "stat_failed";
    case apm44::ShmRingErrorCode::EmptyObject:
      return "empty_object";
    case apm44::ShmRingErrorCode::MapFailed:
      return "map_failed";
    case apm44::ShmRingErrorCode::InvalidHeader:
      return "invalid_header";
    case apm44::ShmRingErrorCode::HeaderTruncated:
      return "header_truncated";
    case apm44::ShmRingErrorCode::CapacityExceedsObject:
      return "capacity_exceeds_object";
  }
  return "unknown";
}

int RunShmStatus() {
  apm44::MmapShmRing ring;
  if (!ring.open(apm44::ShmRingRole::Consumer)) {
    const auto code = ring.lastErrorCode();
    std::cerr << "shm_status=failed\n";
    std::cerr << "shm_name=" << apm44::kShmRingName << "\n";
    std::cerr << "helper_build_id=" << apm44::kBuildId << "\n";
    std::cerr << "error_code=" << ShmErrorCodeName(code) << "\n";
    std::cerr << "error=" << ring.lastError() << "\n";
    if (code == apm44::ShmRingErrorCode::OpenFailed && ring.lastErrno() == ENOENT) {
      return 2;
    }
    return 3;
  }

  const auto* header = ring.header();
  apm44::ShmObjectIdentity identity;
  const bool hasIdentity = apm44::StatNamedShmObject(apm44::kShmRingName, identity);
  std::cout << "shm_status=ok\n";
  std::cout << "shm_name=" << apm44::kShmRingName << "\n";
  std::cout << "helper_build_id=" << apm44::kBuildId << "\n";
  std::cout << "driver_build_id=" << header->producer_build_id << "\n";
  std::cout << "version=" << header->version << "\n";
  std::cout << "capacity_frames=" << header->capacity_frames << "\n";
  std::cout << "sample_rate=" << header->sample_rate << "\n";
  std::cout << "channels=" << header->channels << "\n";
  std::cout << "driver_generation="
            << header->driver_generation.load(std::memory_order_relaxed) << "\n";
  std::cout << "daemon_ready=" << header->daemon_ready.load(std::memory_order_relaxed) << "\n";
  if (hasIdentity && identity.valid) {
    std::cout << "shm_dev=" << identity.st_dev << "\n";
    std::cout << "shm_ino=" << identity.st_ino << "\n";
  }
  ring.close();
  return 0;
}

}  // namespace

int main(int argc, char* argv[]) {
  const apm44::CliOptions options = apm44::ParseCliOptions(argc, argv);

  if (options.showVersion) {
    std::cout << "apm44-bridge " << apm44::kVersionString
              << " build=" << apm44::kBuildId << "\n";
    return 0;
  }
  if (options.showHelp) {
    apm44::PrintUsage(argv[0]);
    return 0;
  }
  if (options.listDevices) {
    return RunListDevices();
  }
  if (options.shmStatus) {
    return RunShmStatus();
  }
  if (options.preflight) {
    return RunPreflight(options);
  }
  if (options.printConfig) {
    return RunPrintConfig(options);
  }

  auto pair = ResolveDevices(options, true);
  if (!pair) {
    return 1;
  }

  apm44::FormatNegotiator negotiator;
  if (const auto err = NegotiatePair(negotiator, *pair, options.virtualDevice)) {
    std::cerr << "error: " << err->message << "\n";
    return 1;
  }

  const apm44::BridgeEngineOptions engineOptions = apm44::ToEngineOptions(options);

  apm44::BridgeEngine engine;
  if (!engine.prepare(*pair, engineOptions)) {
    std::cerr << "error: engine prepare failed\n";
    return 1;
  }
  if (!engine.start()) {
    std::cerr << "error: failed to start IOProcs\n";
    return 1;
  }

  int exitCode = 0;
  if (options.virtualDevice) {
    engine.runUntilSignal([&engine, &options, &exitCode](const apm44::BridgeEngine& snapshot) {
      switch (engine.pollVirtualFeedStaleRing()) {
        case apm44::BridgeEngine::VirtualFeedStaleAction::StopForRemap:
          std::cerr << "apm44-bridge: remapped stale shm ring\n";
          break;
        case apm44::BridgeEngine::VirtualFeedStaleAction::StopForExit: {
          const std::string& detail = engine.virtualFeedLastOpenError();
          if (!detail.empty()) {
            std::cerr << "stale shm ring: " << detail << "\n";
          } else {
            std::cerr << "stale shm ring: could not remap shared-memory ring\n";
          }
          apm44::BridgeEngine::requestStop();
          exitCode = kExitStaleShmRing;
          break;
        }
        case apm44::BridgeEngine::VirtualFeedStaleAction::None:
          break;
      }
      if (options.metricsJson) {
        const auto metrics = apm44::MakeBridgeMetrics(
            snapshot.lastFillMs(), snapshot.lastSmoothedRatio(), snapshot.lastPpm(),
            snapshot.underrunCount(), snapshot.overrunCount(), snapshot.xrunCount(),
            options.targetFillMs, apm44::SrcQualityCliString(options.srcQuality));
        std::cout << apm44::ToJsonLine(metrics) << '\n' << std::flush;
      }
    });
  } else if (options.metricsJson) {
    engine.runUntilSignal([&options](const apm44::BridgeEngine& snapshot) {
      const auto metrics = apm44::MakeBridgeMetrics(
          snapshot.lastFillMs(), snapshot.lastSmoothedRatio(), snapshot.lastPpm(),
          snapshot.underrunCount(), snapshot.overrunCount(), snapshot.xrunCount(),
          options.targetFillMs, apm44::SrcQualityCliString(options.srcQuality));
      std::cout << apm44::ToJsonLine(metrics) << '\n' << std::flush;
    });
  } else {
    engine.runUntilSignal();
  }
  return exitCode;
}
