#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

for harness in codex claude opencode cursor pi commandcode hermes openclaw agents; do
  python3 "$SCRIPT_DIR/install-skill.py" --harness "$harness" "$@"
done
