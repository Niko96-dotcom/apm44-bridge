#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== App build =="
bash scripts/verify-app-build.sh

echo "== Daemon tests =="
if [[ -d build ]]; then
  cmake --build build
  ctest --test-dir build -R 'bridge_metrics|test_bridge_metrics' --output-on-failure
else
  echo "warn: no build/ — run cmake -B build first" >&2
fi

echo "== Static invariants =="
if rg -n "zero latency|0 ms monitoring" App/ 2>/dev/null; then
  echo "error: prohibited latency copy in App/" >&2
  exit 1
fi
rg -n "metrics-json" App/APM44Bridge/BridgeProcessManager.swift >/dev/null
rg -n "return 8" App/APM44Bridge/LatencyPreset.swift >/dev/null
rg -n "return 15" App/APM44Bridge/LatencyPreset.swift >/dev/null
rg -n "return 30" App/APM44Bridge/LatencyPreset.swift >/dev/null

echo "== Swift unit tests =="
bash scripts/run-xcodebuild.sh -project App/APM44Bridge.xcodeproj \
  -scheme APM44Bridge \
  -destination 'platform=macOS' \
  -derivedDataPath build/app \
  test -only-testing:APM44BridgeTests \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= 2>&1 | tail -20

echo "verify-menu-bar: OK"
