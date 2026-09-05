#!/usr/bin/env bash
# Opt-in workaround for the Xcode 26.6 compiler discovery pipe stall.
# Preserve compiler output and exit status; ordinary compilations exec Clang directly.
set -uo pipefail
compiler="$(xcrun --find clang)" || exit 1
if [[ "${1:-}" == '-v' && "${2:-}" == '-E' && "${3:-}" == '-dM' ]]; then
  probe_dir="$(mktemp -d)" || exit 1
  trap 'rm -rf "$probe_dir"' EXIT
  "$compiler" "$@" >"$probe_dir/stdout" 2>"$probe_dir/stderr"
  status=$?
  cat "$probe_dir/stdout" || exit 1
  # Let discovery observe stdout EOF before delivering stderr. On the affected
  # toolchain, simultaneous live pipes stall inside Clang's diagnostic write.
  exec 1>&-
  cat "$probe_dir/stderr" >&2 || exit 1
  exit "$status"
fi
exec "$compiler" "$@"
