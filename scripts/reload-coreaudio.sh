#!/usr/bin/env bash
# Reload Core Audio after HAL install. macOS 14.4+ blocks launchctl kickstart for coreaudiod (SIP).
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: macOS only" >&2
  exit 1
fi

echo "Restarting coreaudiod (launchd will respawn it)..."
if sudo killall coreaudiod 2>/dev/null; then
  sleep 1
  if pgrep -x coreaudiod >/dev/null; then
    echo "OK: coreaudiod is running again."
    exit 0
  fi
  echo "warn: coreaudiod not seen yet — wait a few seconds or reboot once." >&2
  exit 0
fi

echo "killall failed; try a full reboot to load new HAL plug-ins." >&2
exit 1
