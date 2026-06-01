#!/usr/bin/env bash
# Sign all APM44 Bridge release artifacts with Developer ID Application + Hardened Runtime.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${APM44_BUILD_CONFIG:-Release}"

DAEMON="${APM44_DAEMON_PATH:-$ROOT/build/BridgeDaemon/apm44-bridge}"
APP="${APM44_APP_PATH:-$ROOT/build/$CONFIG/APM44 Bridge.app}"
DRIVER="${APM44_DRIVER_PATH:-$ROOT/build/Driver/APM44Bridge.driver}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
Usage: sign-release.sh [--help]

Sign apm44-bridge, APM44 Bridge.app, and APM44Bridge.driver for release.

Environment:
  SIGN_ID              codesign identity. If unset, the script auto-detects
                       a single Developer ID Application identity.
  APM44_DAEMON_PATH    path to apm44-bridge binary
  APM44_APP_PATH       path to .app bundle
  APM44_DRIVER_PATH    path to .driver bundle
  APM44_BUILD_CONFIG   Release or Debug (default Release)

Build first:
  cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build
  bash scripts/embed-daemon-in-app.sh
  bash scripts/verify-app-build.sh   # or xcodebuild Release
EOF
  exit 0
fi

resolve_sign_id() {
  if [[ -n "${SIGN_ID:-}" ]]; then
    printf '%s\n' "$SIGN_ID"
    return
  fi

  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: .*\)".*/\1/p' || true)"
  local count
  count="$(printf '%s\n' "$identities" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$count" == "1" ]]; then
    printf '%s\n' "$identities"
    return
  fi

  echo "error: set SIGN_ID to your Developer ID Application identity" >&2
  echo "hint: security find-identity -v -p codesigning" >&2
  exit 1
}

SIGN_ID="$(resolve_sign_id)"

sign_one() {
  local path="$1"
  local entitlements="${2:-}"
  if [[ ! -e "$path" ]]; then
    echo "error: missing artifact: $path" >&2
    exit 1
  fi
  echo "Signing: $path"
  if [[ -n "$entitlements" && -f "$entitlements" ]]; then
    codesign --force --sign "$SIGN_ID" --timestamp --options runtime \
      --entitlements "$entitlements" "$path"
  else
    codesign --force --sign "$SIGN_ID" --timestamp --options runtime "$path"
  fi
  codesign --verify --verbose "$path"
}

# Inner binaries before outer bundle (app may embed daemon).
if [[ -d "$APP" ]]; then
  AUX="$APP/Contents/MacOS/apm44-bridge"
  if [[ -f "$AUX" ]]; then
    sign_one "$AUX"
  fi
fi

sign_one "$DAEMON"
sign_one "$APP" "$ROOT/App/APM44Bridge/APM44Bridge.entitlements"
sign_one "$DRIVER" "$ROOT/Driver/APM44Bridge.entitlements"

echo ""
echo "All artifacts signed with: $SIGN_ID"
echo "Verify deep:"
echo "  codesign --verify --deep --strict \"$APP\""
echo "  codesign --verify --deep --strict \"$DRIVER\""
echo ""
echo "Next: bash scripts/notary-dry-run.sh  (or scripts/notarize-hal-driver.sh for driver only)"
