#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ ! -d App/APM44Bridge.xcodeproj ]]; then
  echo "Generating Xcode project…" >&2
  (cd App && xcodegen generate)
fi
xcodebuild -project App/APM44Bridge.xcodeproj -scheme APM44Bridge -configuration Debug build CODE_SIGNING_ALLOWED=NO
