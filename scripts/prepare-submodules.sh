#!/usr/bin/env bash
# Make submodule checkouts usable for CMake on fresh CI clones.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

git submodule update --init --recursive

if [[ -d third_party/libASPL ]]; then
  if ! git -C third_party/libASPL describe --tags --abbrev=0 >/dev/null 2>&1; then
    echo "Fetching libASPL tags for CMake version detection..."
    git -C third_party/libASPL fetch --tags --force --quiet
  fi
fi
