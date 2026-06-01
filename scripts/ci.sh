#!/usr/bin/env bash
# Full local/CI verification that does not require AirPods, HAL install, or Apple credentials.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
CONFIG="${APM44_BUILD_CONFIG:-Release}"

cd "$ROOT"

echo "== Secret scan =="
bash scripts/check-secrets.sh

echo "== Configure CMake ($CONFIG) =="
cmake -S "$ROOT" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE="$CONFIG"

echo "== Build native targets =="
cmake --build "$BUILD_DIR" --parallel

echo "== Native tests =="
ctest --test-dir "$BUILD_DIR" --output-on-failure

if [[ "${APM44_RUN_SOAK:-0}" == "1" ]]; then
  echo "== Offline soak =="
  "$BUILD_DIR/BridgeDaemon/apm44-soak" --duration-sec "${APM44_SOAK_SECONDS:-60}"
fi

if [[ "${APM44_SKIP_APP:-0}" != "1" ]]; then
  if command -v xcodegen >/dev/null 2>&1; then
    echo "== Swift app build =="
    bash scripts/verify-app-build.sh

    echo "== Swift unit tests =="
    xcodebuild -project App/APM44Bridge.xcodeproj \
      -scheme APM44Bridge \
      -destination 'platform=macOS' \
      test -only-testing:APM44BridgeTests \
      CODE_SIGNING_ALLOWED=NO
  else
    echo "warn: xcodegen not found; skipping Swift app verification" >&2
  fi
fi

echo "ci: OK"
