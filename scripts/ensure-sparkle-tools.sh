#!/usr/bin/env bash
# Resolve Sparkle's signing tools without placing private key material in the
# repository. The SPM package embeds Sparkle in the app, while these CLI tools
# are built from the matching Sparkle source tag only when a release needs
# them.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.4}"
TOOLS_ROOT="${APM44_SPARKLE_TOOLS_ROOT:-$ROOT/build/sparkle-tools/$SPARKLE_VERSION}"

if [[ -n "${SPARKLE_SIGN_UPDATE:-}" && -x "$SPARKLE_SIGN_UPDATE" ]]; then
  printf '%s\n' "$SPARKLE_SIGN_UPDATE"
  exit 0
fi

for candidate in \
  "$TOOLS_ROOT/bin/sign_update" \
  "$ROOT/build/sparkle-tools/bin/sign_update" \
  "$HOME/Library/Developer/Xcode/DerivedData/Sparkle"/*/Build/Products/Release/sign_update; do
  if [[ -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    exit 0
  fi
done

command -v xcodebuild >/dev/null 2>&1 || {
  echo "error: xcodebuild is required to build Sparkle signing tools" >&2
  exit 1
}

mkdir -p "$TOOLS_ROOT"
ARCHIVE="$TOOLS_ROOT/Sparkle-${SPARKLE_VERSION}.tar.gz"
SOURCE_PARENT="$TOOLS_ROOT/source"
SOURCE="$SOURCE_PARENT/Sparkle-${SPARKLE_VERSION}"

if [[ ! -d "$SOURCE/Sparkle.xcodeproj" ]]; then
  if [[ ! -f "$ARCHIVE" ]]; then
    curl --fail --location --silent --show-error \
      "https://github.com/sparkle-project/Sparkle/archive/refs/tags/${SPARKLE_VERSION}.tar.gz" \
      --output "$ARCHIVE"
  fi
  mkdir -p "$SOURCE_PARENT"
  tar -xzf "$ARCHIVE" -C "$SOURCE_PARENT"
fi

DERIVED_DATA="$TOOLS_ROOT/DerivedData"
xcodebuild -project "$SOURCE/Sparkle.xcodeproj" -scheme sign_update \
  -configuration Release -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO build >&2
xcodebuild -project "$SOURCE/Sparkle.xcodeproj" -scheme generate_appcast \
  -configuration Release -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO build >&2

mkdir -p "$TOOLS_ROOT/bin"
cp "$DERIVED_DATA/Build/Products/Release/sign_update" "$TOOLS_ROOT/bin/sign_update"
cp "$DERIVED_DATA/Build/Products/Release/generate_appcast" "$TOOLS_ROOT/bin/generate_appcast"
chmod 755 "$TOOLS_ROOT/bin/sign_update" "$TOOLS_ROOT/bin/generate_appcast"
printf '%s\n' "$TOOLS_ROOT/bin/sign_update"
