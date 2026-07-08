#!/usr/bin/env bash
# Run one Ultimate De-Slop stage through the Cursor Cloud shim.
#
# Usage:
#   scripts/deslop-cloud/run-stage.sh review
#   scripts/deslop-cloud/run-stage.sh fix DSL-000001
#   scripts/deslop-cloud/run-stage.sh verify DSL-000001
#   scripts/deslop-cloud/run-stage.sh loop --max-iterations 1 --priority P0,P1
set -euo pipefail

ROOT="$(git -C "$PWD" rev-parse --show-toplevel)"
SKILL_DIR="${DESLOP_SKILL_DIR:-$ROOT/.cursor/skills/ultimate-de-slop}"
SHIM_DIR="$ROOT/scripts/deslop-cloud"
CLOUD_DIR="$ROOT/.deslop/cloud"

if [ ! -x "$SKILL_DIR/scripts/deslop-init.sh" ]; then
  printf 'deslop-cloud: missing skill at %s\n' "$SKILL_DIR" >&2
  printf 'Install with:\n  git clone https://github.com/Niko96-dotcom/ultimate-de-slop /tmp/ultimate-de-slop\n  /tmp/ultimate-de-slop/scripts/install/install-cursor.sh --scope local --project-dir %s\n' "$ROOT" >&2
  exit 1
fi

if [ ! -x "$SHIM_DIR/cursor-agent" ]; then
  printf 'deslop-cloud: missing shim executable at %s/cursor-agent\n' "$SHIM_DIR" >&2
  exit 1
fi

export PATH="$SHIM_DIR:$PATH"
export DESLOP_HARNESS=cursor

stage="${1:-}"
shift || true

mkdir -p "$CLOUD_DIR"
"$SKILL_DIR/scripts/deslop-init.sh" >/dev/null
# Merge tracked cloud seed ignored_paths into local .deslop/config.json
python3 - "$ROOT/scripts/deslop-cloud/config.seed.json" "$ROOT/.deslop/config.json" <<'PY'
import json
import sys
from pathlib import Path

seed, cfg_path = map(Path, sys.argv[1:])
seed_data = json.loads(seed.read_text())
cfg = json.loads(cfg_path.read_text()) if cfg_path.exists() else {}
ignored = list(
    dict.fromkeys([*(cfg.get("ignored_paths") or []), *(seed_data.get("ignored_paths") or [])])
)
cfg["ignored_paths"] = ignored
cfg_path.write_text(json.dumps(cfg, indent=2) + "\n")
PY

case "$stage" in
  review)
    set +e
    "$SKILL_DIR/scripts/deslop-review.sh"
    code=$?
    set -e
    ;;
  fix)
    finding_id="${1:-}"
    if [ -z "$finding_id" ]; then
      printf 'usage: %s fix FINDING_ID\n' "$0" >&2
      exit 2
    fi
    shift || true
    set +e
    "$SKILL_DIR/scripts/deslop-fix.sh" --allow-dirty "$finding_id" "$@"
    code=$?
    set -e
    ;;
  verify)
    finding_id="${1:-}"
    if [ -z "$finding_id" ]; then
      printf 'usage: %s verify FINDING_ID [--checks-json PATH]\n' "$0" >&2
      exit 2
    fi
    shift || true
    set +e
    "$SKILL_DIR/scripts/deslop-verify.sh" "$finding_id" "$@"
    code=$?
    set -e
    ;;
  checks)
    finding_id="${1:-}"
    if [ -z "$finding_id" ]; then
      printf 'usage: %s checks FINDING_ID\n' "$0" >&2
      exit 2
    fi
    "$SKILL_DIR/scripts/deslop-run-checks.sh" --no-fail "$finding_id"
    exit 0
    ;;
  status)
    "$SKILL_DIR/scripts/deslop-status.py"
    exit 0
    ;;
  next)
    "$SKILL_DIR/scripts/deslop-next.py" --priority "${1:-P0,P1,P2}"
    exit 0
    ;;
  loop)
    set +e
    "$SKILL_DIR/scripts/deslop-loop.sh" --allow-dirty "$@"
    code=$?
    set -e
    ;;
  doctor)
    "$SKILL_DIR/scripts/deslop-doctor.py" --harness cursor
    exit 0
    ;;
  ""|-h|--help|help)
    cat <<EOF
Usage: scripts/deslop-cloud/run-stage.sh <review|fix|verify|checks|status|next|loop|doctor> [args]

Puts scripts/deslop-cloud ahead of PATH so DESLOP_HARNESS=cursor uses the
cloud shim instead of the authenticated cursor-agent CLI.

Typical Cloud Agent loop:
  1. scripts/deslop-cloud/run-stage.sh review
  2. If exit 42: read .deslop/cloud/prompt.txt, write JSON to .deslop/cloud/response.json
  3. Re-run the same stage command
  4. scripts/deslop-cloud/run-stage.sh fix <id>
  5. scripts/deslop-cloud/run-stage.sh checks <id>
  6. scripts/deslop-cloud/run-stage.sh verify <id>
EOF
    exit 0
    ;;
  *)
    printf 'deslop-cloud: unknown stage %s\n' "$stage" >&2
    exit 2
    ;;
esac

if [ "${code:-0}" -eq 42 ]; then
  printf '\n[deslop-cloud] awaiting parent-agent JSON at %s/response.json\n' "$CLOUD_DIR" >&2
  printf '[deslop-cloud] prompt copy: %s/prompt.txt\n' "$CLOUD_DIR" >&2
  exit 42
fi
exit "${code:-0}"
