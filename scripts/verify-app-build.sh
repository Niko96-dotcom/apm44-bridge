#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="${APM44_APP_DERIVED_DATA:-$ROOT/build/app}"
CONFIG="${APM44_BUILD_CONFIG:-Debug}"
APP_OUTPUT_DIR="${APM44_APP_OUTPUT_DIR:-}"
if [[ -n "$APP_OUTPUT_DIR" ]]; then
  APP="$APP_OUTPUT_DIR/APM44 Bridge.app"
else
  APP="$DERIVED_DATA_PATH/Build/Products/$CONFIG/APM44 Bridge.app"
fi
EXECUTABLE="$APP/Contents/MacOS/APM44 Bridge"
XCODEBUILD_ARGS=(
  -project App/APM44Bridge.xcodeproj
  -scheme APM44Bridge
  -configuration "$CONFIG"
  -derivedDataPath "$DERIVED_DATA_PATH"
  build
  CODE_SIGNING_ALLOWED=YES
  CODE_SIGN_IDENTITY=-
  CODE_SIGN_STYLE=Manual
  DEVELOPMENT_TEAM=
)
if [[ -n "$APP_OUTPUT_DIR" ]]; then
  XCODEBUILD_ARGS+=("CONFIGURATION_BUILD_DIR=$APP_OUTPUT_DIR")
fi

cd "$ROOT"
echo "Generating Xcode project..." >&2
(cd App && xcodegen generate)
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Source HEAD: $(git rev-parse --short HEAD)"
fi
echo "DerivedData: $DERIVED_DATA_PATH"
if [[ -n "$APP_OUTPUT_DIR" ]]; then
  echo "App output: $APP_OUTPUT_DIR"
fi
rm -rf "$APP" "$APP.dSYM"
xcodebuild "${XCODEBUILD_ARGS[@]}"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "error: built app executable missing at $EXECUTABLE" >&2
  exit 1
fi

echo "Built app: $APP"
echo "Executable: $EXECUTABLE"
codesign --verify --deep --strict "$APP"
stat -f "Executable mtime: %Sm" "$EXECUTABLE"
