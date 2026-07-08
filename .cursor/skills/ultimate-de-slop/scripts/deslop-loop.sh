#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: deslop-loop.sh [options]

Run the explicit bounded ultimate-de-slop loop.

Options:
  --max-iterations N
  --priority P0,P1,P2
  --commit
  --auto-revert
  --allow-dirty
  --review-every N
  --help
EOF
}

MAX_ITERATIONS=5
PRIORITY="P0,P1,P2"
COMMIT=0
AUTO_REVERT=0
ALLOW_DIRTY=0
REVIEW_EVERY=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --max-iterations)
      MAX_ITERATIONS="${2:-}"
      shift 2
      ;;
    --priority)
      PRIORITY="${2:-}"
      shift 2
      ;;
    --commit)
      COMMIT=1
      shift
      ;;
    --auto-revert)
      AUTO_REVERT=1
      shift
      ;;
    --allow-dirty)
      ALLOW_DIRTY=1
      shift
      ;;
    --review-every)
      REVIEW_EVERY="${2:-}"
      shift 2
      ;;
    *)
      printf 'deslop-loop: error: unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

case "$MAX_ITERATIONS" in
  ''|*[!0-9]*) printf 'deslop-loop: error: --max-iterations must be a positive integer\n' >&2; exit 1 ;;
esac
case "$REVIEW_EVERY" in
  ''|*[!0-9]*) printf 'deslop-loop: error: --review-every must be a positive integer\n' >&2; exit 1 ;;
esac
if [ "$MAX_ITERATIONS" -le 0 ] || [ "$REVIEW_EVERY" -le 0 ]; then
  printf 'deslop-loop: error: numeric options must be positive\n' >&2
  exit 1
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" || {
  printf 'deslop-loop: error: could not resolve git root; run from inside a git repository\n' >&2
  exit 1
}

if [ "$ALLOW_DIRTY" -eq 0 ] && [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
  printf 'deslop-loop: error: git tree is dirty. Commit/stash changes or pass --allow-dirty intentionally.\n' >&2
  git -C "$ROOT" status --short >&2
  exit 1
fi

if [ "$COMMIT" -eq 1 ]; then
  branch="deslop/$(date -u +%Y%m%dT%H%M%SZ)"
  git -C "$ROOT" checkout -b "$branch"
  printf 'Created branch %s\n' "$branch"
fi

latest_json() {
  python3 - "$ROOT" "$1" "$2" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
kind = sys.argv[2]
finding_id = sys.argv[3]
matches = sorted((root / ".deslop" / "runs").glob(f"*-{kind}-{finding_id}/{kind}.json"), key=lambda p: p.as_posix(), reverse=True)
print(matches[0] if matches else "")
PY
}

"$SCRIPT_DIR/deslop-init.sh"

baseline_verified_ids="$(python3 - "$ROOT" <<'PY'
import json
import sys
from pathlib import Path
root = Path(sys.argv[1])
path = root / ".deslop" / "findings.jsonl"
ids = []
if path.exists():
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        item = json.loads(line)
        if item.get("status") == "verified" and item.get("id"):
            ids.append(str(item["id"]))
print(",".join(ids))
PY
)"

record_outcome() {
  stop_reason="$1"
  iterations_completed="$2"
  shift 2
  "$SCRIPT_DIR/deslop-record-outcome.py" \
    --stop-reason "$stop_reason" \
    --max-iterations "$MAX_ITERATIONS" \
    --priority "$PRIORITY" \
    --iterations-completed "$iterations_completed" \
    --baseline-verified-ids "$baseline_verified_ids" \
    "$@"
}

iteration=1
while [ "$iteration" -le "$MAX_ITERATIONS" ]; do
  if [ -f "$ROOT/.deslop/stop" ]; then
    printf 'Stop file found: .deslop/stop\n'
    record_outcome stop_file "$((iteration - 1))"
    "$SCRIPT_DIR/deslop-status.py"
    exit 0
  fi

  next_id="$("$SCRIPT_DIR/deslop-next.py" --priority "$PRIORITY")"
  review_due=0
  if [ "$iteration" -eq 1 ] || [ $(( (iteration - 1) % REVIEW_EVERY )) -eq 0 ]; then
    review_due=1
  fi

  if [ "$review_due" -eq 1 ] && [ "$next_id" = "NONE" ]; then
    "$SCRIPT_DIR/deslop-review.sh"
    next_id="$("$SCRIPT_DIR/deslop-next.py" --priority "$PRIORITY")"
  elif [ "$review_due" -eq 1 ]; then
    printf 'Accepted finding %s already queued; skipping review before fix.\n' "$next_id"
  fi

  if [ "$next_id" = "NONE" ]; then
    printf 'No eligible accepted finding remains.\n'
    record_outcome no_eligible_findings "$((iteration - 1))"
    "$SCRIPT_DIR/deslop-status.py"
    exit 0
  fi

  printf 'Iteration %s: fixing %s\n' "$iteration" "$next_id"
  "$SCRIPT_DIR/deslop-fix.sh" --allow-dirty "$next_id"
  "$SCRIPT_DIR/deslop-run-checks.sh" --no-fail "$next_id"
  checks_json="$(latest_json checks "$next_id")"
  "$SCRIPT_DIR/deslop-verify.sh" --checks-json "$checks_json" "$next_id"
  verify_json="$(latest_json verify "$next_id")"

  finalize_args=("$next_id" "--verify-json" "$verify_json" "--checks-json" "$checks_json")
  if [ "$COMMIT" -eq 1 ]; then
    finalize_args+=("--commit")
  fi
  if [ "$AUTO_REVERT" -eq 1 ]; then
    finalize_args+=("--auto-revert")
  fi
  if ! "$SCRIPT_DIR/deslop-finalize.py" "${finalize_args[@]}"; then
    printf 'Finalize stopped the loop for %s.\n' "$next_id" >&2
    halt_status="$(python3 - "$ROOT" "$next_id" <<'PY'
import json
import sys
from pathlib import Path
root = Path(sys.argv[1])
finding_id = sys.argv[2]
status = "unknown"
path = root / ".deslop" / "findings.jsonl"
if path.exists():
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        item = json.loads(line)
        if item.get("id") == finding_id:
            status = str(item.get("status") or "unknown")
            break
print(status)
PY
)"
    record_outcome finalize_halt "$iteration" --halt-finding-id "$next_id" --halt-status "$halt_status" || true
    "$SCRIPT_DIR/deslop-status.py" || true
    exit 1
  fi

  iteration="$((iteration + 1))"
done

record_outcome max_iterations_reached "$MAX_ITERATIONS"
"$SCRIPT_DIR/deslop-status.py"
