#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$($ROOT/scripts/read-version.sh)"

if [[ -n "${APM44_VERSION:-}" && "$APM44_VERSION" != "$VERSION" ]]; then
  echo "error: APM44_VERSION=$APM44_VERSION disagrees with VERSION=$VERSION" >&2
  exit 1
fi

echo "Generating app project for APM44 Bridge $VERSION" >&2
(cd "$ROOT/App" && APM44_VERSION="$VERSION" xcodegen generate)
