#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
echo "Generating Xcode project..." >&2
(cd App && xcodegen generate)
xcodebuild -project App/APM44Bridge.xcodeproj -scheme APM44Bridge -configuration Debug build CODE_SIGNING_ALLOWED=NO
