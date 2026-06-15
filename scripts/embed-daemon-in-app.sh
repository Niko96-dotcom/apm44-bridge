#!/usr/bin/env bash
# Copy built apm44-bridge into APM44 Bridge.app for release (POL-01).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${APM44_BUILD_CONFIG:-Release}"
DAEMON="${APM44_DAEMON_PATH:-$ROOT/build/BridgeDaemon/apm44-bridge}"
APP="${APM44_APP_PATH:-$ROOT/build/$CONFIG/APM44 Bridge.app}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
Usage: embed-daemon-in-app.sh [--help]

Copies apm44-bridge into Contents/MacOS/ of the menu bar app bundle.

Environment:
  APM44_DAEMON_PATH   source binary (default build/BridgeDaemon/apm44-bridge)
  APM44_APP_PATH      destination .app (default build/Release/APM44 Bridge.app)
  APM44_BUILD_CONFIG  Release or Debug
  APM44_SKIP_LOCAL_APP_RESIGN=1
                      skip local ad-hoc re-sign after embedding
EOF
  exit 0
fi

if [[ ! -x "$DAEMON" ]]; then
  echo "error: build daemon first: cmake --build build --target apm44-bridge" >&2
  exit 1
fi

if [[ ! -d "$APP" ]]; then
  echo "error: app bundle missing at $APP — run xcodebuild Release or verify-app-build.sh" >&2
  exit 1
fi

DEST="$APP/Contents/MacOS/apm44-bridge"
cp "$DAEMON" "$DEST"
chmod +x "$DEST"
echo "Embedded: $DEST"

if [[ "${APM44_SKIP_LOCAL_APP_RESIGN:-0}" != "1" ]]; then
  codesign --force --sign - --timestamp=none "$DEST"
  codesign --force --sign - --timestamp=none \
    --entitlements "$ROOT/App/APM44Bridge/APM44Bridge.entitlements" "$APP"
  codesign --verify --deep --strict "$APP"
  echo "Local ad-hoc signature refreshed after embedding helper."
fi

echo "BridgeBinaryLocator resolves bundled apm44-bridge without APM44_BRIDGE_PATH."
