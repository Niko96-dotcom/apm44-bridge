#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$($ROOT/scripts/read-version.sh)"

# Keep the menu-bar app's embedded build fingerprint identical to the native
# daemon/driver fingerprint. CMake appends -dirty while the worktree has
# uncommitted source changes, so compute the same value before XcodeGen runs.
GIT_SHA="$(git -C "$ROOT" rev-list -n 1 HEAD -- . ':(exclude)docs/appcast.xml' 2>/dev/null || true)"
GIT_SHA="${GIT_SHA:0:12}"
[[ -n "$GIT_SHA" ]] || GIT_SHA="nogit"
if ! git -C "$ROOT" diff --quiet --ignore-submodules HEAD 2>/dev/null; then
  GIT_SHA="${GIT_SHA}-dirty"
fi
BUILD_ID="${VERSION}+${GIT_SHA}"

if [[ -n "${APM44_VERSION:-}" && "$APM44_VERSION" != "$VERSION" ]]; then
  echo "error: APM44_VERSION=$APM44_VERSION disagrees with VERSION=$VERSION" >&2
  exit 1
fi

echo "Generating app project for APM44 Bridge $VERSION (build=$BUILD_ID)" >&2
(cd "$ROOT/App" && APM44_VERSION="$VERSION" APM44_BUILD_ID="$BUILD_ID" xcodegen generate)
