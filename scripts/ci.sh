#!/usr/bin/env bash
# Full local/CI verification that does not require AirPods, HAL install, or Apple credentials.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
CONFIG="${APM44_BUILD_CONFIG:-Release}"

cd "$ROOT"

echo "== Secret scan =="
bash scripts/check-secrets.sh

echo "== Prepare submodules =="
bash scripts/prepare-submodules.sh

echo "== Configure CMake ($CONFIG) =="
cmake -S "$ROOT" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE="$CONFIG"

echo "== Build native targets =="
cmake --build "$BUILD_DIR" --parallel

echo "== Native tests =="
ctest --test-dir "$BUILD_DIR" --output-on-failure

echo "== Release script tests =="
bash tests/test_release_scripts.sh

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
      -derivedDataPath build/app \
      test -only-testing:APM44BridgeTests \
      CODE_SIGNING_ALLOWED=NO
  else
    echo "warn: xcodegen not found; skipping Swift app verification" >&2
  fi
fi

# QA-01: non-hardware dry-run check of build-ID sync between the
# repo daemon and the embedded app helper. The dry-run path is
# non-fatal — the script exits 0 with a WARN if the embedded
# helper is missing, which is the expected state until
# scripts/embed-daemon-in-app.sh has been run.
if [[ -d "$BUILD_DIR/$CONFIG/APM44 Bridge.app" ]]; then
  echo "== Embed daemon in app bundle =="
  APM44_BUILD_CONFIG="$CONFIG" bash scripts/embed-daemon-in-app.sh
fi

echo "== Installed-sync dry-run =="
APM44_BUILD_CONFIG="$CONFIG" bash scripts/verify-installed-sync.sh --dry-run

echo "ci: OK"
