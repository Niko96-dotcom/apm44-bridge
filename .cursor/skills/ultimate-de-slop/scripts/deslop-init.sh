#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: deslop-init.sh [--help]

Initialize .deslop runtime files for ultimate-de-slop and build an inventory.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" || {
  printf 'deslop-init: error: could not resolve git root; run from inside a git repository\n' >&2
  exit 1
}

mkdir -p "$ROOT/.deslop/runs" "$ROOT/.deslop/tmp"

if [ ! -f "$ROOT/.deslop/config.json" ]; then
  cat > "$ROOT/.deslop/config.json" <<'EOF'
{
  "version": 1,
  "max_iterations": 5,
  "max_fix_attempts": 3,
  "max_findings_per_reviewer": 5,
  "max_active_findings": 10,
  "max_changed_files_per_fix": 8,
  "max_changed_lines_per_fix": 400,
  "agent_timeout_seconds": 5400,
  "agent_idle_timeout_seconds": 1200,
  "agent_terminate_grace_seconds": 10,
  "codex_timeout_seconds": 5400,
  "codex_idle_timeout_seconds": 1200,
  "codex_terminate_grace_seconds": 10,
  "confidence_thresholds": {"P0": 0.70, "P1": 0.75, "P2": 0.85},
  "ignored_paths": ["node_modules", ".git", "dist", "build", "coverage", "vendor", ".next", ".turbo", ".venv", "__pycache__"],
  "commit_by_default": false,
  "auto_revert_by_default": false
}
EOF
fi

if [ ! -f "$ROOT/.deslop/findings.jsonl" ]; then
  : > "$ROOT/.deslop/findings.jsonl"
fi

python3 - "$ROOT" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

root = Path(sys.argv[1])
deslop = root / ".deslop"
state_path = deslop / "state.json"
config = json.loads((deslop / "config.json").read_text())
if not state_path.exists():
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    state = {
        "version": 1,
        "repo_root": str(root),
        "created_at": now,
        "updated_at": now,
        "config": config,
        "counters": {"total": 0, "by_status": {}, "by_severity": {}, "open_by_severity": {}},
        "current_iteration": 0,
        "stop": {"requested": False, "reason": None, "path": ".deslop/stop"},
        "last_run": None,
        "open_findings_summary": {}
    }
    state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
PY

"$SCRIPT_DIR/deslop-inventory.py" --write

cat <<EOF
ultimate-de-slop initialized.

Created or verified:
  .deslop/config.json
  .deslop/state.json
  .deslop/findings.jsonl
  .deslop/inventory.json
  .deslop/index.md

Next commands:
  $SCRIPT_DIR/deslop-doctor.py
  $SCRIPT_DIR/deslop-status.py
  $SCRIPT_DIR/deslop-loop.sh --max-iterations 5 --priority P0,P1
EOF
