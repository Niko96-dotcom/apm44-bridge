#!/usr/bin/env bash
# Exercise the workaround against the real toolchain, including failure status.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
probe_dir="$(mktemp -d)"
trap 'rm -rf "$probe_dir"' EXIT
compiler="$(xcrun --find clang)"
sdk="$(xcrun --sdk macosx --show-sdk-path)"

compare() {
  local expected_status="$1"
  shift
  local direct_status=0 wrapped_status=0
  "$compiler" "$@" >"$probe_dir/direct-out" 2>"$probe_dir/direct-err" || direct_status=$?
  bash "$ROOT/scripts/xcode-clang-probe.sh" "$@" \
    >"$probe_dir/wrapped-out" 2>"$probe_dir/wrapped-err" || wrapped_status=$?
  [[ "$direct_status" == "$expected_status" && "$direct_status" == "$wrapped_status" ]]
  cmp "$probe_dir/direct-out" "$probe_dir/wrapped-out"
  cmp "$probe_dir/direct-err" "$probe_dir/wrapped-err"
}

compare 0 -v -E -dM -isysroot "$sdk" -x c -c /dev/null
compare 1 -v -E -dM -apm44-invalid-option
compare 0 --version
echo "compiler probe tests: OK (stdout, stderr, success/failure status, passthrough)"
