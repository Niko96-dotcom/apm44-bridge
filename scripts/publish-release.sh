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

[[ -z "${APM44_RELEASE_TAG:-}" || "$APM44_RELEASE_TAG" == "$TAG" ]] || \
  fail "APM44_RELEASE_TAG=$APM44_RELEASE_TAG does not match VERSION=$VERSION"

for command_name in gh git curl shasum; do
  command -v "$command_name" >/dev/null 2>&1 || fail "$command_name is required to publish v$VERSION"
done

for artifact in "$DMG" "$PKG" "$DMG_SHA" "$PKG_SHA" "$APPCAST"; do
  [[ -f "$artifact" ]] || fail "required gated release artifact is missing: $artifact"
done

[[ -z "$(git -C "$ROOT" status --porcelain=v1)" ]] || \
  fail "worktree must be clean before publication; commit docs/appcast.xml and release metadata first"

HEAD_SHA="$(git -C "$ROOT" rev-parse HEAD)"
TAG_SHA="$(git -C "$ROOT" rev-list -n 1 "$TAG" 2>/dev/null || true)"
[[ -n "$TAG_SHA" ]] || fail "signed tag $TAG is missing; create and push it before publishing"
[[ "$TAG_SHA" == "$HEAD_SHA" ]] || fail "tag $TAG does not point at HEAD ($HEAD_SHA)"
REMOTE_TAG_SHA="$(git -C "$ROOT" ls-remote --tags origin "refs/tags/$TAG" | awk 'NR == 1 { sub(/\^\{\}$/, "", $1); print $1 }')"
[[ "$REMOTE_TAG_SHA" == "$HEAD_SHA" ]] || \
  fail "origin tag $TAG is missing or points to $REMOTE_TAG_SHA instead of $HEAD_SHA"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  fail "GitHub release $TAG already exists; refusing to overwrite it"
fi

SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-$($ROOT/scripts/ensure-sparkle-tools.sh)}"
SPARKLE_SIGN_UPDATE="$SIGN_UPDATE" \
  bash "$ROOT/scripts/validate-appcast.sh"

gh auth status >/dev/null 2>&1 || fail "GitHub CLI authentication is unavailable"

grep -Fq "https://github.com/${REPO}/releases/download/${TAG}/APM44Bridge-${VERSION}.pkg" "$APPCAST" || \
  fail "appcast enclosure URL does not point at the immutable $TAG PKG asset"

echo "Creating immutable GitHub release $TAG..."
gh release create "$TAG" \
  --repo "$REPO" \
  --verify-tag \
  --title "APM44 Bridge $VERSION" \
  --notes-file "$ROOT/CHANGELOG.md"

echo "Uploading signed DMG, PKG, and checksums..."
gh release upload "$TAG" \
  --repo "$REPO" \
  "$DMG" "$PKG" "$DMG_SHA" "$PKG_SHA"

RELEASE_URL="$(gh release view "$TAG" --repo "$REPO" --json url --jq '.url')"
echo "Release URL: $RELEASE_URL"
echo "Appcast URL: https://niko96-dotcom.github.io/apm44-bridge/appcast.xml"
echo "Published commit: $HEAD_SHA"
