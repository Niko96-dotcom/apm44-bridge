#!/usr/bin/env bash
# Local, offline ring transfer measurements; never opens the installed HAL ring.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${APM44_BENCH_BUILD_DIR:-$ROOT/build/perf}"
ARCH="${APM44_BENCH_ARCH:-$(uname -m)}"
cd "$ROOT"
bash scripts/prepare-submodules.sh >&2
cmake -S "$ROOT" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES="$ARCH" -DAPM44_SANITIZER=none >&2
cmake --build "$BUILD_DIR" --target apm44-ring-bench --parallel >&2
echo "architecture=$ARCH; $(sw_vers -productVersion); $(sysctl -n machdep.cpu.brand_string)" >&2
"$BUILD_DIR/BridgeDaemon/apm44-ring-bench"
