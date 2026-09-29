#include <catch2/catch_test_macros.hpp>

#include "CliOptions.h"

#include <initializer_list>
#include <string>
#include <vector>

namespace {

apm44::CliOptions Parse(std::initializer_list<std::string> args) {
  std::vector<std::string> storage{"apm44-bridge"};
  storage.insert(storage.end(), args.begin(), args.end());
  std::vector<char*> argv;
  for (auto& arg : storage) {
    argv.push_back(arg.data());
  }
  return apm44::ParseCliOptions(static_cast<int>(argv.size()), argv.data());
}

}  // namespace

TEST_CASE("Target fill accepts only complete finite values in range", "[cli]") {
  CHECK(Parse({"--target-fill-ms", "6"}).targetFillMs == 6.0);
  CHECK(Parse({"--target-fill-ms", "120"}).targetFillMs == 120.0);
  CHECK(Parse({"--target-fill-ms", "15.5"}).targetFillMs == 15.5);
  CHECK_FALSE(Parse({"--target-fill-ms", "120"}).usageError);

  for (const std::string bad : {"nan", "NaN", "+nan", "inf", "-inf", "15junk", "1e400", "",
                                "   ", "5", "121"}) {
    INFO("value='" << bad << "'");
    CHECK(Parse({"--target-fill-ms", bad}).usageError);
  }
  CHECK(Parse({"--target-fill-ms"}).usageError);
}

TEST_CASE("Device UIDs must be present and non-blank", "[cli]") {
  const auto ok = Parse({"--output-device", " AppleUSBAudioEngine:1 "});
  CHECK_FALSE(ok.usageError);
  REQUIRE(ok.outputDeviceUid);
  CHECK(*ok.outputDeviceUid == "AppleUSBAudioEngine:1");

  CHECK(Parse({"--output-device"}).usageError);
  CHECK(Parse({"--output-device", ""}).usageError);
  CHECK(Parse({"--output-device", "   "}).usageError);
  CHECK(Parse({"--output-device", "--metrics-json"}).usageError);
  CHECK(Parse({"--input-device", "\t"}).usageError);
}

TEST_CASE("Unknown options are usage errors, explicit help is not", "[cli]") {
  const auto unknown = Parse({"--bogus"});
  CHECK(unknown.usageError);

  const auto help = Parse({"--help"});
  CHECK(help.showHelp);
  CHECK_FALSE(help.usageError);

  CHECK(Parse({"--help", "--bogus"}).usageError);
  CHECK(Parse({"--src-quality", "ultra"}).usageError);
  CHECK(Parse({"--src-quality", "best"}).srcQuality == apm44::LibSamplerateSrc::Quality::Best);
}
