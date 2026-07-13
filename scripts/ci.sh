#!/usr/bin/env bash
# Full local/CI verification that does not require AirPods, HAL install, or Apple credentials.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
CONFIG="${APM44_BUILD_CONFIG:-Release}"
APP_PATH="$BUILD_DIR/$CONFIG/APM44 Bridge.app"
HELPER_PATH="$APP_PATH/Contents/MacOS/apm44-bridge"

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
    APM44_BUILD_CONFIG="$CONFIG" \
      APM44_APP_OUTPUT_DIR="$BUILD_DIR/$CONFIG" \
      bash scripts/verify-app-build.sh

    if [[ ! -d "$APP_PATH" ]]; then
      echo "error: expected app bundle missing at $APP_PATH" >&2
      exit 1
    fi

    echo "== Swift unit tests =="
    rm -rf \
      "$BUILD_DIR/app/Build/Products/Debug/APM44 Bridge.app" \
      "$BUILD_DIR/app/Build/Products/$CONFIG/APM44 Bridge.app" \
      "$BUILD_DIR/app/Build/Products/Debug/APM44 Bridge.app.dSYM" \
      "$BUILD_DIR/app/Build/Products/$CONFIG/APM44 Bridge.app.dSYM"
    xcodebuild -project App/APM44Bridge.xcodeproj \
      -scheme APM44Bridge \
      -destination 'platform=macOS' \
      -derivedDataPath build/app \
      test -only-testing:APM44BridgeTests \
      CODE_SIGNING_ALLOWED=YES \
      CODE_SIGN_IDENTITY=- \
      CODE_SIGN_STYLE=Manual \
      DEVELOPMENT_TEAM=

    echo "== Embed daemon in app bundle =="
    APM44_APP_PATH="$APP_PATH" \
      APM44_BUILD_CONFIG="$CONFIG" \
      bash scripts/embed-daemon-in-app.sh

    echo "== Version identity =="
    APM44_APP_PATH="$APP_PATH" APM44_BUILD_CONFIG="$CONFIG" \
      bash scripts/verify-version-identity.sh

    echo "== Universal architecture proof =="
    APM44_APP_PATH="$APP_PATH" APM44_BUILD_CONFIG="$CONFIG" \
      bash scripts/verify-release-architectures.sh

    if [[ ! -x "$HELPER_PATH" ]]; then
      echo "error: embedded helper missing at $HELPER_PATH" >&2
      exit 1
    fi

    echo "== Installed-sync dry-run =="
    APM44_APP_PATH="$APP_PATH" \
      APM44_BUILD_CONFIG="$CONFIG" \
      bash scripts/verify-installed-sync.sh --dry-run
  else
    echo "warn: xcodegen not found; skipping Swift app verification" >&2
  fi
else
  echo "warn: APM44_SKIP_APP=1; skipping app bundle embed and installed-sync verification" >&2
fi

echo "ci: OK"
