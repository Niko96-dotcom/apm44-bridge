#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"

cmake -S "$ROOT" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD_DIR"
ctest --test-dir "$BUILD_DIR" -R soak --output-on-failure
"$BUILD_DIR/BridgeDaemon/apm44-soak" --duration-sec 60
