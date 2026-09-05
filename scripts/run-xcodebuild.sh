#!/usr/bin/env bash
# Shared opt-in toolchain workaround for local builds and XCTest.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${APM44_BUFFER_COMPILER_PROBE:-0}" == '1' ]]; then
  exec xcodebuild "$@" "CC=$ROOT/scripts/xcode-clang-probe.sh"
fi
exec xcodebuild "$@"
