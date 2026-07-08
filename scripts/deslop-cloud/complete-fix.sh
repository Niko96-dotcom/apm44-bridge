#!/usr/bin/env bash
# Complete an awaiting Ultimate De-Slop fix run after the parent Cloud Agent
# applied the working-tree edit and wrote .deslop/cloud/response.json.
#
# Why this exists: deslop-fix.sh always captures a fresh before-snapshot.
# Re-running it after edits makes changed_during_attempt=false. This helper
# finishes the latest awaiting fix run using its original before-snapshot.
set -euo pipefail

ROOT="$(git -C "$PWD" rev-parse --show-toplevel)"
CLOUD_DIR="$ROOT/.deslop/cloud"
FINDING_ID="${1:-}"

if [ -z "$FINDING_ID" ]; then
  printf 'usage: %s FINDING_ID\n' "$0" >&2
  exit 2
fi

if [ ! -f "$CLOUD_DIR/response.json" ]; then
  printf 'deslop-cloud: missing %s/response.json\n' "$CLOUD_DIR" >&2
  exit 1
fi

run_dir="$(python3 - "$ROOT" "$FINDING_ID" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
finding_id = sys.argv[2]
matches = sorted(
    (root / ".deslop" / "runs").glob(f"*-fix-{finding_id}"),
    key=lambda p: p.name,
    reverse=True,
)
for path in matches:
    if (path / "git-status-before.txt").exists() and not (path / "fix.json").exists():
        print(path)
        break
else:
    raise SystemExit(f"no awaiting fix run found for {finding_id}")
PY
)"

fix_json="$run_dir/fix.json"
last_message="$run_dir/last-message.txt"
raw="$run_dir/raw-fix-output.txt"
status_before="$run_dir/git-status-before.txt"
diff_before="$run_dir/git-diff-before.patch"
status_after="$run_dir/git-status-after.txt"
diff_after="$run_dir/git-diff-after.patch"
attempt_delta="$run_dir/git-diff-attempt.patch"

cp "$CLOUD_DIR/response.json" "$last_message"
cp "$CLOUD_DIR/response.json" "$raw"
mv "$CLOUD_DIR/response.json" "$CLOUD_DIR/response.last.json"
cp "$last_message" "$fix_json"

python3 - "$fix_json" <<'PY'
import json, sys
from pathlib import Path
obj = json.loads(Path(sys.argv[1]).read_text())
required = {"finding_id", "summary", "changed_files", "checks_run", "risks", "status"}
missing = required - set(obj)
if missing:
    raise SystemExit(f"fix JSON missing keys: {', '.join(sorted(missing))}")
if obj.get("status") not in {"fixed", "blocked"}:
    raise SystemExit(f"invalid fix status: {obj.get('status')!r}")
PY

# Intent-to-add new files so they appear in git diff.
git -C "$ROOT" add -N -- . ':!.deslop' >/dev/null 2>&1 || true
git -C "$ROOT" status --porcelain=v1 -uall -- . ':!.deslop/runs' ':!.deslop/tmp' > "$status_after"
git -C "$ROOT" diff --binary -- . ':!.deslop/runs' ':!.deslop/tmp' > "$diff_after"

python3 - "$diff_before" "$diff_after" "$attempt_delta" <<'PY'
import sys
from pathlib import Path

before = Path(sys.argv[1])
after = Path(sys.argv[2])
target = Path(sys.argv[3])
before_text = before.read_text(errors="ignore") if before.exists() else ""
after_text = after.read_text(errors="ignore") if after.exists() else ""
# When the before snapshot is empty, the product git diff *is* the attempt delta.
# Meta-diffing empty vs the after patch would inflate line counts (every patch
# header/hunk line counted) and falsely trip the change budget.
if not before_text.strip():
    target.write_text(after_text)
else:
    import difflib
    delta = difflib.unified_diff(
        before_text.splitlines(keepends=True),
        after_text.splitlines(keepends=True),
        fromfile="git-diff-before-fix.patch",
        tofile="git-diff-after-fix.patch",
    )
    target.write_text("".join(delta))
PY

python3 - "$ROOT" "$FINDING_ID" "$fix_json" "$status_before" "$diff_before" "$status_after" "$diff_after" "$attempt_delta" "$run_dir" <<'PY'
import json
import subprocess
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

root = Path(sys.argv[1])
finding_id = sys.argv[2]
fix = json.loads(Path(sys.argv[3]).read_text())
status_before = Path(sys.argv[4])
diff_before = Path(sys.argv[5])
status_after = Path(sys.argv[6])
diff_after = Path(sys.argv[7])
attempt_delta = Path(sys.argv[8])
run_dir = Path(sys.argv[9])
path = root / ".deslop" / "findings.jsonl"
items = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
target = next((item for item in items if item.get("id") == finding_id), None)
if target is None:
    print(f"finding not found: {finding_id}", file=sys.stderr)
    raise SystemExit(1)
changed_files = fix.get("changed_files") or []
if not isinstance(changed_files, list):
    changed_files = []
before_status = status_before.read_text() if status_before.exists() else ""
before_diff = diff_before.read_text(errors="ignore") if diff_before.exists() else ""
after_status = status_after.read_text() if status_after.exists() else ""
after_diff = diff_after.read_text(errors="ignore") if diff_after.exists() else ""
changed_during_attempt = before_status != after_status or before_diff != after_diff
status_text = str(fix.get("status", "")).lower()
config_path = root / ".deslop" / "config.json"
config = json.loads(config_path.read_text()) if config_path.exists() else {}
max_files = int(config.get("max_changed_files_per_fix", 8) or 8)
max_lines = int(config.get("max_changed_lines_per_fix", 400) or 400)

def count_attempt_delta(delta_path: Path) -> tuple[int, int]:
    if not delta_path.exists():
        return 0, 0
    text = delta_path.read_text(errors="ignore")
    files: set[str] = set()
    lines = 0
    for line in text.splitlines():
        if line.startswith("+++ ") or line.startswith("--- "):
            marker = line[4:].strip()
            if marker != "/dev/null":
                if marker.startswith("a/") or marker.startswith("b/"):
                    marker = marker[2:]
                files.add(marker)
        elif line.startswith("+") or line.startswith("-"):
            if not line.startswith("+++") and not line.startswith("---"):
                lines += 1
    return len(files), lines

attempt_files, attempt_lines = count_attempt_delta(attempt_delta)
fix["attempt_changed_files"] = attempt_files
fix["attempt_changed_lines"] = attempt_lines
budget_breach = None
if changed_during_attempt and (attempt_files > max_files or attempt_lines > max_lines):
    budget_breach = (
        f"fix exceeded change budget: files={attempt_files}/{max_files}, "
        f"lines={attempt_lines}/{max_lines}"
    )

if status_text in {"blocked", "cannot_fix", "failed"}:
    target["status"] = "blocked"
elif budget_breach:
    target["status"] = "needs_human"
    target["block_reason"] = budget_breach
elif changed_files and changed_during_attempt:
    target["status"] = "fixed_unverified"
elif changed_files:
    target["status"] = "blocked"
    target["block_reason"] = "fixer reported changed files, but git diff/status did not change during this attempt"
else:
    target["status"] = "blocked"
    target["block_reason"] = "fixer reported no changed files; pre-existing dirty worktree state was not counted as a fix"
fix["changed_during_attempt"] = changed_during_attempt
fix["run_dir"] = str(run_dir)
fix["snapshot_paths"] = {
    "status_before": str(status_before),
    "diff_before": str(diff_before),
    "status_after": str(status_after),
    "diff_after": str(diff_after),
    "attempt_delta": str(attempt_delta),
}
now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
target["updated_at"] = now
target["attempts"] = int(target.get("attempts") or 0)
target["last_fix"] = {
    "summary": fix.get("summary"),
    "changed_files": changed_files,
    "checks_run": fix.get("checks_run") or [],
    "risks": fix.get("risks") or [],
    "status": target["status"],
    "attempt_changed_files": attempt_files,
    "attempt_changed_lines": attempt_lines,
    "run_dir": str(run_dir),
}
Path(sys.argv[3]).write_text(json.dumps(fix, indent=2, sort_keys=True) + "\n")
path.write_text("".join(json.dumps(item, sort_keys=True) + "\n" for item in items))

def summarize(findings):
    non_open = {"verified", "rejected", "false_positive"}
    return {
        "total": len(findings),
        "by_status": dict(sorted(Counter(str(item.get("status", "unknown")) for item in findings).items())),
        "open_by_severity": dict(
            sorted(
                Counter(
                    str(item.get("severity", "unknown")).upper()
                    for item in findings
                    if str(item.get("status", "")) not in non_open
                ).items()
            )
        ),
    }

state_path = root / ".deslop" / "state.json"
state = json.loads(state_path.read_text()) if state_path.exists() else {}
state["updated_at"] = now
state["findings_summary"] = summarize(items)
state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
print(f"Finding {finding_id}: {target['status']} (files={attempt_files}, lines={attempt_lines})")
if budget_breach:
    print(budget_breach, file=sys.stderr)
    raise SystemExit(2)
if target["status"] != "fixed_unverified":
    print(target.get("block_reason", ""), file=sys.stderr)
    raise SystemExit(1)
PY

printf 'Completed fix run: %s\n' "$run_dir"
printf 'Next: scripts/deslop-cloud/run-stage.sh checks %s\n' "$FINDING_ID"
