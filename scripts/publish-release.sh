#!/usr/bin/env bash
# Publish an already-gated, signed release and its Sparkle appcast.
#
# This script intentionally does not create or move tags. The maintainer must
# push a new signed tag first; refusing to overwrite an existing release keeps
# an appcast enclosure and GitHub asset immutable once clients can see it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$($ROOT/scripts/read-version.sh)"
TAG="v${VERSION}"
REPO="${APM44_GITHUB_REPO:-Niko96-dotcom/apm44-bridge}"
RELEASE_ROOT="${APM44_RELEASE_ROOT:-$ROOT/build/signing}"
DMG="${APM44_DMG_PATH:-$RELEASE_ROOT/APM44Bridge-${VERSION}.dmg}"
PKG="${APM44_PKG_PATH:-$RELEASE_ROOT/APM44Bridge-${VERSION}.pkg}"
DMG_SHA="${DMG}.sha256"
PKG_SHA="${PKG}.sha256"
APPCAST="${APM44_APPCAST_PATH:-$ROOT/docs/appcast.xml}"

fail() { echo "error: $*" >&2; exit 1; }

# shellcheck source=lib/publish-preflight.sh
source "$ROOT/scripts/lib/publish-preflight.sh"

publish_preflight

SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-$($ROOT/scripts/ensure-sparkle-tools.sh)}"
# --pkg ties the enclosure to the exact PKG being uploaded: a PKG rebuilt or
# re-stapled after generate-appcast.sh would fail every client's EdDSA check.
SPARKLE_SIGN_UPDATE="$SIGN_UPDATE" \
  bash "$ROOT/scripts/validate-appcast.sh" --pkg "$PKG" --expect-version "$VERSION"

gh auth status >/dev/null 2>&1 || fail "GitHub CLI authentication is unavailable"

grep -Fq "https://github.com/${REPO}/releases/download/${TAG}/APM44Bridge-${VERSION}.pkg" "$APPCAST" || \
  fail "appcast enclosure URL does not point at the immutable $TAG PKG asset"

NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
python3 - "$APPCAST" >"$NOTES" <<'PYNOTES'
import sys
import xml.etree.ElementTree as ET

notes = ET.parse(sys.argv[1]).findtext("./channel/item/description", "").strip()
if not notes:
    raise SystemExit("error: signed appcast release notes are empty")
print(notes)
PYNOTES

echo "Uploading signed DMG, PKG, and checksums to a draft release..."
gh release create "$TAG" \
  --repo "$REPO" \
  --verify-tag \
  --draft \
  --title "APM44 Bridge $VERSION" \
  --notes-file "$NOTES" \
  "$DMG" "$PKG" "$DMG_SHA" "$PKG_SHA"

# A failed upload must leave a draft, never a public release with missing assets.
gh release edit "$TAG" --repo "$REPO" --draft=false --latest

RELEASE_URL="$(gh release view "$TAG" --repo "$REPO" --json url --jq '.url')"
echo "Release URL: $RELEASE_URL"
echo "Appcast URL: https://niko96-dotcom.github.io/apm44-bridge/appcast.xml"
echo "Published commit: $HEAD_SHA"
