#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${APM44_BUILD_CONFIG:-Release}"
VERSION="$($ROOT/scripts/read-version.sh)"
DAEMON="${APM44_DAEMON_PATH:-$ROOT/build/BridgeDaemon/apm44-bridge}"
APP="${APM44_APP_PATH:-$ROOT/build/$CONFIG/APM44 Bridge.app}"
DRIVER="${APM44_DRIVER_PATH:-$ROOT/build/Driver/APM44Bridge.driver}"
HELPER="${APM44_HELPER_PATH:-$APP/Contents/MacOS/apm44-bridge}"

fail() { echo "error: $*" >&2; exit 1; }
plist_value() { /usr/libexec/PlistBuddy -c "Print:$2" "$1" 2>/dev/null; }

grep -Fq 'MARKETING_VERSION: "${APM44_VERSION}"' "$ROOT/App/project.yml" ||
  fail "App/project.yml does not derive MARKETING_VERSION from APM44_VERSION"
grep -Fq 'set(DRIVER_VERSION "${CMAKE_PROJECT_VERSION}")' "$ROOT/Driver/CMakeLists.txt" ||
  fail "driver version is not derived from the root CMake project"

[[ -x "$DAEMON" ]] || fail "daemon missing at $DAEMON"
daemon_out="$("$DAEMON" --version)"
[[ "$daemon_out" == "apm44-bridge $VERSION "* ]] ||
  fail "daemon version mismatch: $daemon_out"

[[ -x "$HELPER" ]] || fail "embedded helper missing at $HELPER"
helper_out="$("$HELPER" --version)"
[[ "$helper_out" == "apm44-bridge $VERSION "* ]] ||
  fail "embedded helper version mismatch: $helper_out"

app_plist="$APP/Contents/Info.plist"
driver_plist="$DRIVER/Contents/Info.plist"
[[ -f "$app_plist" ]] || fail "app Info.plist missing at $app_plist"
[[ -f "$driver_plist" ]] || fail "driver Info.plist missing at $driver_plist"

app_short="$(plist_value "$app_plist" CFBundleShortVersionString)"
app_build="$(plist_value "$app_plist" CFBundleVersion)"
driver_short="$(plist_value "$driver_plist" CFBundleShortVersionString)"
driver_build="$(plist_value "$driver_plist" CFBundleVersion)"
app_identity="$(plist_value "$app_plist" APM44BuildID)"
driver_identity="$(plist_value "$driver_plist" APM44BuildID)"

[[ "$app_short" == "$VERSION" ]] || fail "app short version $app_short != $VERSION"
[[ "$app_build" == "$VERSION" ]] || fail "app build version $app_build != $VERSION"
[[ "$driver_short" == "$VERSION" ]] || fail "driver short version $driver_short != $VERSION"
[[ "$driver_build" == "$VERSION" ]] || fail "driver build version $driver_build != $VERSION"

daemon_identity="${daemon_out##*build=}"
helper_identity="${helper_out##*build=}"
[[ "$app_identity" == "$daemon_identity" ]] || fail "app build ID $app_identity != daemon $daemon_identity"
[[ "$driver_identity" == "$daemon_identity" ]] || fail "driver build ID $driver_identity != daemon $daemon_identity"
[[ "$helper_identity" == "$daemon_identity" ]] || fail "helper build ID $helper_identity != daemon $daemon_identity"

echo "version identity: $VERSION"
echo "build identity: $daemon_identity"
echo "verify-version-identity: OK"
