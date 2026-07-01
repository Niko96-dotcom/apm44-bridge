#!/usr/bin/env bash
# Remove APM44 Bridge app, HAL driver, and package receipt when explicitly approved.
set -euo pipefail

YES=0
DRY_RUN=1

usage() {
  cat <<EOF
Usage: uninstall-apm44.sh [--dry-run] [--yes]

Default: dry-run only.
  --yes      Remove installed app, HAL driver, and package receipt.
  --dry-run  Print actions without changing the system.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      YES=1
      DRY_RUN=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

APP="/Applications/APM44 Bridge.app"
DRIVER="/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver"
PKG_ID="com.niko.apm44.pkg"

if [[ "$DRY_RUN" == "1" ]]; then
  echo "dry-run: would remove $APP"
  echo "dry-run: would remove $DRIVER"
  echo "dry-run: would forget package receipt $PKG_ID when present"
  echo "dry-run: would reload Core Audio"
  exit 0
fi

if [[ "$YES" != "1" ]]; then
  echo "error: destructive uninstall requires --yes" >&2
  exit 2
fi

if ! sudo -n true 2>/dev/null; then
  echo "error: sudo is required for uninstall; run interactively once or configure sudo, then retry" >&2
  exit 1
fi

sudo rm -rf "$APP"
sudo rm -rf "$DRIVER"
if pkgutil --pkg-info "$PKG_ID" >/dev/null 2>&1; then
  sudo pkgutil --forget "$PKG_ID"
fi
sudo killall coreaudiod 2>/dev/null || true

echo "uninstall-apm44: OK"
