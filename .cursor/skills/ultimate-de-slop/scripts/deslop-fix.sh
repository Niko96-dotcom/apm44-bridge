#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: deslop-fix.sh [--allow-dirty] FINDING_ID

Run a workspace-write fixer through DESLOP_HARNESS, defaulting to codex, for exactly one accepted finding.
EOF
}

ALLOW_DIRTY=0
FINDING_ID=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --allow-dirty)
      ALLOW_DIRTY=1
      shift
      ;;
    -*)
      printf 'deslop-fix: error: unknown option: %s\n' "$1" >&2
      exit 1
      ;;
    *)
      if [ -n "$FINDING_ID" ]; then
        printf 'deslop-fix: error: expected one finding id\n' >&2
        exit 1
      fi
      FINDING_ID="$1"
      shift
      ;;
  esac
done

if [ -z "$FINDING_ID" ]; then
  usage >&2
  exit 1
fi

extract_json() {
  python3 - "$1" "$2" <<'PY'
import json
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])
text = source.read_text(errors="ignore")

def scan_balanced(s):
    for start, ch in enumerate(s):
        if ch != "{":
            continue
        depth = 0
        in_str = False
        escape = False
        for idx in range(start, len(s)):
            c = s[idx]
            if in_str:
                if escape:
                    escape = False
                elif c == "\\":
                    escape = True
                elif c == '"':
                    in_str = False
                continue
            if c == '"':
                in_str = True
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    yield s[start:idx + 1]
                    break

valid = []
try:
    parsed = json.loads(text, strict=False)
    if isinstance(parsed, dict):
        valid.append(parsed)
except json.JSONDecodeError:
    pass
for candidate in scan_balanced(text):
    try:
        parsed = json.loads(candidate, strict=False)
    except json.JSONDecodeError:
        continue
    if isinstance(parsed, dict):
        valid.append(parsed)

required = {"finding_id", "summary", "changed_files", "checks_run", "risks", "status"}
obj = next((item for item in reversed(valid) if required.issubset(item)), None)
if obj is None:
    if valid:
        seen = set()
        for item in valid:
            seen.update(item.keys())
        missing = ", ".join(sorted(required - seen))
        print(f"could not extract fix JSON object from {source}; missing required keys: {missing}", file=sys.stderr)
    else:
        print(f"could not extract JSON object from {source}", file=sys.stderr)
    raise SystemExit(1)
target.write_text(json.dumps(obj, indent=2, sort_keys=True) + "\n")
PY
}

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" || {
  printf 'deslop-fix: error: could not resolve git root; run from inside a git repository\n' >&2
  exit 1
}

if [ "$ALLOW_DIRTY" -eq 0 ] && [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
  printf 'deslop-fix: error: git tree is dirty. Commit/stash changes or pass --allow-dirty intentionally.\n' >&2
  git -C "$ROOT" status --short >&2
  exit 1
fi

if [ ! -f "$ROOT/.deslop/config.json" ]; then
  "$SCRIPT_DIR/deslop-init.sh"
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
run_dir="$ROOT/.deslop/runs/${timestamp}-fix-${FINDING_ID}"
mkdir -p "$run_dir"

python3 - "$ROOT" "$FINDING_ID" "$run_dir/finding.json" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

root = Path(sys.argv[1])
finding_id = sys.argv[2]
snapshot = Path(sys.argv[3])
path = root / ".deslop" / "findings.jsonl"
items = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
target = None
for item in items:
    if item.get("id") == finding_id:
        target = item
        break
if target is None:
    print(f"finding not found: {finding_id}", file=sys.stderr)
    raise SystemExit(1)
if target.get("status") not in {"accepted", "fixed_unverified"}:
    print(f"finding {finding_id} is not accepted; current status is {target.get('status')}", file=sys.stderr)
    raise SystemExit(1)
now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
target["status"] = "fixing"
target["updated_at"] = now
snapshot.write_text(json.dumps(target, indent=2, sort_keys=True) + "\n")
path.write_text("".join(json.dumps(item, sort_keys=True) + "\n" for item in items))
PY

prompt="$run_dir/prompt.txt"
raw="$run_dir/raw-fix-output.txt"
fix_json="$run_dir/fix.json"
last_message="$run_dir/last-message.txt"
runner_json="$run_dir/runner.json"
schema="$SCRIPT_DIR/../references/fix.schema.json"
status_before="$run_dir/git-status-before.txt"
diff_before="$run_dir/git-diff-before.patch"
status_after="$run_dir/git-status-after.txt"
diff_after="$run_dir/git-diff-after.patch"
attempt_delta="$run_dir/git-diff-attempt.patch"

git -C "$ROOT" status --porcelain=v1 -uall -- . ':!.deslop/runs' ':!.deslop/tmp' > "$status_before"
git -C "$ROOT" diff --binary -- . ':!.deslop/runs' ':!.deslop/tmp' > "$diff_before"

write_attempt_snapshots() {
  git -C "$ROOT" status --porcelain=v1 -uall -- . ':!.deslop/runs' ':!.deslop/tmp' > "$status_after"
  git -C "$ROOT" diff --binary -- . ':!.deslop/runs' ':!.deslop/tmp' > "$diff_after"
  python3 - "$diff_before" "$diff_after" "$attempt_delta" <<'PY'
import difflib
import sys
from pathlib import Path

before = Path(sys.argv[1])
after = Path(sys.argv[2])
target = Path(sys.argv[3])
before_lines = before.read_text(errors="ignore").splitlines(keepends=True) if before.exists() else []
after_lines = after.read_text(errors="ignore").splitlines(keepends=True) if after.exists() else []
delta = difflib.unified_diff(
    before_lines,
    after_lines,
    fromfile="git-diff-before-fix.patch",
    tofile="git-diff-after-fix.patch",
)
target.write_text("".join(delta))
PY
}

cat > "$prompt" <<EOF
You are running as the selected Ultimate De-Slop fixer role. Do not delegate to another fixer, load skill files recursively, or run deslop-loop.sh, deslop-fix.sh, or any nested de-slop harness command from inside this fixer session.

Fix exactly one finding. Do not fix unrelated issues. Do not clean up while you are here. Preserve behavior unless explicitly required. Prefer deleting/moving complexity to adding abstraction. Add or update a focused test when acceptance criteria or expected checks imply behavioral coverage (unittest/pytest/assert/test). Run the expected checks when practical.
Perform the edit in the working tree before reporting success. Do not merely describe the fix. Before returning, inspect git status or git diff and make sure the files you list in changed_files actually changed.
Hard budgets from \`.deslop/config.json\` are enforced after your edit: stay within max_changed_files_per_fix and max_changed_lines_per_fix for this attempt delta.

Return exactly one JSON object, no markdown fences and no prose, with these keys:
finding_id, summary, changed_files, checks_run, risks, status.
Valid status values are only "fixed" and "blocked". Do not return "fixing", "in_progress", or any other status. If you cannot make the edit, return status "blocked" and leave changed_files empty.

Read AGENTS.md files that apply, if any. Read \`.deslop/index.md\`.

Finding:
$(cat "$run_dir/finding.json")
EOF

mark_fix_failure() {
  reason="$1"
  exit_code="${2:-1}"
  write_attempt_snapshots
  python3 - "$ROOT" "$FINDING_ID" "$reason" "$exit_code" "$runner_json" "$raw" "$status_before" "$diff_before" <<'PY'
import json
import subprocess
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

root = Path(sys.argv[1])
finding_id = sys.argv[2]
reason = sys.argv[3]
exit_code = int(sys.argv[4])
runner_json = Path(sys.argv[5])
raw = Path(sys.argv[6])
status_before = Path(sys.argv[7])
diff_before = Path(sys.argv[8])

def now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

def git_output(args: list[str]) -> str:
    return subprocess.run(["git", *args], cwd=root, text=True, stdout=subprocess.PIPE, check=False).stdout

def load_json(path: Path, fallback):
    if not path.exists():
        return fallback
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError:
        return fallback

def summarize(findings):
    non_open = {"verified", "rejected", "false_positive"}
    return {
        "total": len(findings),
        "by_status": dict(sorted(Counter(str(item.get("status", "unknown")) for item in findings).items())),
        "open_by_severity": dict(sorted(Counter(str(item.get("severity", "unknown")).upper() for item in findings if str(item.get("status", "")) not in non_open).items())),
    }

findings_path = root / ".deslop" / "findings.jsonl"
items = [json.loads(line) for line in findings_path.read_text().splitlines() if line.strip()]
target = next((item for item in items if item.get("id") == finding_id), None)
if target is None:
    print(f"finding not found: {finding_id}", file=sys.stderr)
    raise SystemExit(1)

before_status = status_before.read_text() if status_before.exists() else ""
before_diff = diff_before.read_text(errors="ignore") if diff_before.exists() else ""
after_status = git_output(["status", "--porcelain=v1", "-uall", "--", ".", ":!.deslop/runs", ":!.deslop/tmp"])
after_diff = git_output(["diff", "--binary", "--", ".", ":!.deslop/runs", ":!.deslop/tmp"])
changed_during_attempt = before_status != after_status or before_diff != after_diff

config = load_json(root / ".deslop" / "config.json", {})
attempts = int(target.get("attempts", 0) or 0) + 1
max_attempts = int(config.get("max_fix_attempts", 3) or 3)
timestamp = now()
target["attempts"] = attempts
target["updated_at"] = timestamp
target["last_failure"] = {
    "at": timestamp,
    "changed_during_attempt": changed_during_attempt,
    "exit_code": exit_code,
    "raw_output": str(raw),
    "reason": reason,
    "runner_json": str(runner_json),
}
if changed_during_attempt:
    target["status"] = "needs_human"
    target["block_reason"] = f"{reason}; fixer changed the worktree but did not complete the fix contract"
elif attempts >= max_attempts:
    target["status"] = "blocked"
    target["block_reason"] = f"{reason}; max fix attempts reached"
else:
    target["status"] = "accepted"
    target["block_reason"] = reason

findings_path.write_text("".join(json.dumps(item, sort_keys=True) + "\n" for item in items))

state_path = root / ".deslop" / "state.json"
state = load_json(state_path, {})
if not isinstance(state, dict):
    state = {}
state.setdefault("version", 1)
state.setdefault("created_at", timestamp)
state.setdefault("current_iteration", 0)
state["updated_at"] = timestamp
state["repo_root"] = str(root)
state["config"] = config if isinstance(config, dict) else {}
state["counters"] = summarize(items)
state["open_findings_summary"] = state["counters"].get("open_by_severity", {})
state["stop"] = {
    "requested": (root / ".deslop" / "stop").exists(),
    "reason": "stop file exists" if (root / ".deslop" / "stop").exists() else None,
    "path": ".deslop/stop",
}
state["last_run"] = {
    "at": timestamp,
    "exit_code": exit_code,
    "finding_id": finding_id,
    "kind": "fix",
    "reason": reason,
    "status": target.get("status"),
}
state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
print(f"Finding {finding_id}: {target.get('status')} ({reason})")
PY
}

set +e
runner_args=("$SCRIPT_DIR/deslop-agent-runner.py" --root "$ROOT" --prompt "$prompt" --raw-output "$raw" --last-message "$last_message" --runner-json "$runner_json" --schema "$schema" --sandbox workspace-write --kind fix)
for writable_dir in "$ROOT/.agents" "$ROOT/.codex" "$ROOT/.deslop"; do
  if [ -d "$writable_dir" ]; then
    runner_args+=(--add-dir "$writable_dir")
  fi
done
"${runner_args[@]}"
code=$?
set -e
if [ "$code" -ne 0 ]; then
  mark_fix_failure "${DESLOP_HARNESS:-codex} fixer failed or timed out" "$code"
  printf 'deslop-fix: error: %s fixer failed with exit code %s. Raw output: %s Runner: %s\n' "${DESLOP_HARNESS:-codex}" "$code" "$raw" "$runner_json" >&2
  exit "$code"
fi

if ! extract_json "$last_message" "$fix_json" && ! extract_json "$raw" "$fix_json"; then
  mark_fix_failure "fix JSON extraction failed" 1
  printf 'deslop-fix: error: JSON extraction failed. Raw output: %s\n' "$raw" >&2
  exit 1
fi

write_attempt_snapshots

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
after_status = subprocess.run(
    ["git", "status", "--porcelain=v1", "-uall", "--", ".", ":!.deslop/runs", ":!.deslop/tmp"],
    cwd=root,
    text=True,
    stdout=subprocess.PIPE,
    check=False,
).stdout
after_diff = subprocess.run(
    ["git", "diff", "--binary", "--", ".", ":!.deslop/runs", ":!.deslop/tmp"],
    cwd=root,
    text=True,
    stdout=subprocess.PIPE,
    check=False,
).stdout
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
target["last_fix"] = fix
target["updated_at"] = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
path.write_text("".join(json.dumps(item, sort_keys=True) + "\n" for item in items))

state_path = root / ".deslop" / "state.json"
now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
state = json.loads(state_path.read_text()) if state_path.exists() else {
    "version": 1,
    "repo_root": str(root),
    "created_at": now,
    "updated_at": now,
    "config": config,
    "counters": {},
    "current_iteration": 0,
    "stop": {"requested": False, "reason": None, "path": ".deslop/stop"},
    "last_run": None,
    "open_findings_summary": {},
}
non_open = {"verified", "rejected", "false_positive"}
state["updated_at"] = now
state["repo_root"] = str(root)
state["config"] = config
state["counters"] = {
    "total": len(items),
    "by_status": dict(sorted(Counter(str(item.get("status", "unknown")) for item in items).items())),
    "open_by_severity": dict(sorted(Counter(str(item.get("severity", "unknown")).upper() for item in items if str(item.get("status", "")) not in non_open).items())),
}
state["open_findings_summary"] = state["counters"]["open_by_severity"]
state["last_run"] = {"kind": "fix", "finding_id": finding_id, "at": now, "status": target["status"]}
state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
if budget_breach:
    print(f"Finding {finding_id}: needs_human ({budget_breach})", file=sys.stderr)
    raise SystemExit(1)
if target["status"] != "fixed_unverified":
    print(f"Finding {finding_id}: {target['status']}", file=sys.stderr)
    raise SystemExit(1)
PY

cat <<EOF
Fix attempt complete.
Run directory: $run_dir
Fix JSON: $fix_json

Next commands:
  $SCRIPT_DIR/deslop-run-checks.sh $FINDING_ID
  $SCRIPT_DIR/deslop-verify.sh $FINDING_ID
EOF
