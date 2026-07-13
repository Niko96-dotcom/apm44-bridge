#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$ROOT/VERSION"

[[ -f "$VERSION_FILE" ]] || { echo "error: missing VERSION" >&2; exit 1; }
VERSION="$(tr -d '[:space:]' <"$VERSION_FILE")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "error: VERSION must contain one semantic version" >&2
  exit 1
}
printf '%s\n' "$VERSION"
