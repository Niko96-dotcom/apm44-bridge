#!/usr/bin/env bash
# Proves the real daemon binary exits 43 through main() when the singleton
# lock is held. No audio hardware required.
#
# The proof holds the real per-user lock, so it runs only where no helper of
# the owner's can be affected: hosted CI (CI set) or an explicit opt-in with
# APM44_RUN_SINGLETON_PROOF=1. Elsewhere it reports NOT RUN and never opens
# the lock (T020).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DAEMON="${APM44_DAEMON_PATH:-$ROOT/build/BridgeDaemon/apm44-bridge}"

fail() {
  printf 'test_daemon_exit_codes: %s\n' "$*" >&2
  exit 1
}

if [[ -z "${CI:-}" && "${APM44_RUN_SINGLETON_PROOF:-0}" != "1" ]]; then
  echo "test_daemon_exit_codes: NOT RUN (real singleton lock; runs in hosted CI, or set APM44_RUN_SINGLETON_PROOF=1 with no bridge running)"
  exit 0
fi

[[ -x "$DAEMON" ]] || fail "daemon binary not executable at $DAEMON (set APM44_DAEMON_PATH)"

python3 - "$DAEMON" <<'PY'
import fcntl
import os
import subprocess
import sys

daemon = sys.argv[1]


def skip(reason):
    # Only CI or an explicit opt-in get here, so a skip means the proof never ran.
    print(f"test_daemon_exit_codes: NOT RUN: {reason}", file=sys.stderr)
    sys.exit(1)


lock_path = f"/tmp/apm44-bridge.{os.getuid()}.lock"
try:
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
except OSError as exc:
    skip(f"cannot open singleton lock {lock_path}: {exc}")
try:
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        skip("a running apm44-bridge helper holds the singleton lock")
    except OSError as exc:
        skip(f"cannot lock singleton lock {lock_path}: {exc}")
    try:
        proc = subprocess.run(
            [daemon, "--output-device", "none"],
            capture_output=True,
            text=True,
            timeout=10,
            stdin=subprocess.DEVNULL,
        )
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
    if proc.returncode != 43 or "already owns the singleton lock" not in proc.stderr:
        print(f"test_daemon_exit_codes: expected exit 43 with singleton-lock stderr, got {proc.returncode}: {proc.stderr!r}", file=sys.stderr)
        sys.exit(1)
finally:
    os.close(fd)

print("test_daemon_exit_codes: OK")
PY
