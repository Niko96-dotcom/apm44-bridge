#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="${APM44_APP_DERIVED_DATA:-$ROOT/build/app}"
CONFIG="${APM44_BUILD_CONFIG:-Debug}"
APP="$DERIVED_DATA_PATH/Build/Products/$CONFIG/APM44 Bridge.app"
EXECUTABLE="$APP/Contents/MacOS/APM44 Bridge"

cd "$ROOT"
echo "Generating Xcode project..." >&2
(cd App && xcodegen generate)
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Source HEAD: $(git rev-parse --short HEAD)"
fi
echo "DerivedData: $DERIVED_DATA_PATH"
xcodebuild \
  -project App/APM44Bridge.xcodeproj \
  -scheme APM44Bridge \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build \
  CODE_SIGNING_ALLOWED=NO

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "error: built app executable missing at $EXECUTABLE" >&2
  exit 1
fi

echo "Built app: $APP"
echo "Executable: $EXECUTABLE"
stat -f "Executable mtime: %Sm" "$EXECUTABLE"
