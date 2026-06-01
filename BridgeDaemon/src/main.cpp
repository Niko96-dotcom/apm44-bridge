#include "CliOptions.h"
#include "engine/BridgeEngine.h"
#include "engine/BridgeMetrics.h"
#include "hal/DeviceEnumerator.h"
#include "hal/FormatNegotiator.h"

#include <apm44/AudioFormats.h>

#include <iostream>
#include <optional>

namespace {

constexpr const char* kVersion = "0.1.0";

std::optional<apm44::BridgeDevicePair> ResolveDevices(const apm44::CliOptions& options,
                                                      bool requirePresent) {
  apm44::DeviceEnumerator enumerator;
  auto input = enumerator.resolveInput(options.inputDeviceUid);
  if (!input) {
    if (requirePresent) {
      std::cerr << "error: input device not found. Install BlackHole 2ch or pass --input-device UID\n";
    }
    return std::nullopt;
  }
  auto output = enumerator.resolveOutput(options.outputDeviceUid);
  if (!output) {
    if (requirePresent) {
      std::cerr << "error: output device not found. Connect AirPods Max USB-C or pass --output-device UID\n";
    }
    return std::nullopt;
  }

  apm44::BridgeDevicePair pair;
  pair.input = *input;
  pair.output = *output;
  return pair;
}

int RunPreflight(const apm44::CliOptions& options) {
  auto pair = ResolveDevices(options, true);
  if (!pair) {
    return 1;
  }

  apm44::FormatNegotiator negotiator;
  if (const auto err = negotiator.negotiate(*pair)) {
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
  if (const auto err = negotiator.negotiate(*pair)) {
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

}  // namespace

int main(int argc, char* argv[]) {
  const apm44::CliOptions options = apm44::ParseCliOptions(argc, argv);

  if (options.showVersion) {
    std::cout << "apm44-bridge " << kVersion << "\n";
    return 0;
  }
  if (options.showHelp) {
    apm44::PrintUsage(argv[0]);
    return 0;
  }
  if (options.listDevices) {
    return RunListDevices();
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
  if (const auto err = negotiator.negotiate(*pair)) {
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

  if (options.metricsJson) {
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
  return 0;
}
