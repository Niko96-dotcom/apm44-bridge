#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: deslop-verify.sh [--checks-json PATH] FINDING_ID

Run a read-only verifier through DESLOP_HARNESS, defaulting to codex, for one fixed_unverified finding.
EOF
}

CHECKS_JSON=""
FINDING_ID=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --checks-json)
      CHECKS_JSON="${2:-}"
      if [ -z "$CHECKS_JSON" ]; then
        printf 'deslop-verify: error: --checks-json requires a path\n' >&2
        exit 1
      fi
      shift 2
      ;;
    -*)
      printf 'deslop-verify: error: unknown option: %s\n' "$1" >&2
      exit 1
      ;;
    *)
      if [ -n "$FINDING_ID" ]; then
        printf 'deslop-verify: error: expected one finding id\n' >&2
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
  python3 - "$1" "$2" "$3" <<'PY'
import json
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])
expected_finding_id = sys.argv[3]
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

required = {"finding_id", "verdict", "confidence", "evidence", "concerns", "required_follow_up"}
obj = next((item for item in reversed(valid) if required.issubset(item)), None)
if obj is None:
    if valid:
        seen = set()
        for item in valid:
            seen.update(item.keys())
        missing = ", ".join(sorted(required - seen))
        print(f"could not extract verify JSON object from {source}; missing required keys: {missing}", file=sys.stderr)
    else:
        print(f"could not extract JSON object from {source}", file=sys.stderr)
    raise SystemExit(1)
obj["finding_id"] = expected_finding_id
for key in ("evidence", "concerns", "required_follow_up"):
    value = obj.get(key)
    if value is None:
        obj[key] = []
    elif isinstance(value, list):
        obj[key] = [str(item) for item in value if str(item).strip()]
    elif str(value).strip().lower() in {"none", "n/a", "[]"}:
        obj[key] = []
    else:
        obj[key] = [str(value)]
confidence = obj.get("confidence")
if isinstance(confidence, str):
    labels = {"high": 0.95, "medium": 0.80, "low": 0.50}
    normalized = confidence.strip().lower()
    if normalized in labels:
        obj["confidence"] = labels[normalized]
target.write_text(json.dumps(obj, indent=2, sort_keys=True) + "\n")
PY
}

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" || {
  printf 'deslop-verify: error: could not resolve git root; run from inside a git repository\n' >&2
  exit 1
}

if [ -z "$CHECKS_JSON" ]; then
  CHECKS_JSON="$(python3 - "$ROOT" "$FINDING_ID" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
finding_id = sys.argv[2]
matches = sorted((root / ".deslop" / "runs").glob(f"*-checks-{finding_id}/checks.json"), key=lambda p: p.as_posix(), reverse=True)
print(matches[0] if matches else "")
PY
)"
fi
if [ -z "$CHECKS_JSON" ] || [ ! -f "$CHECKS_JSON" ]; then
  printf 'deslop-verify: error: checks.json not found; run deslop-run-checks.sh first or pass --checks-json.\n' >&2
  exit 1
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
run_dir="$ROOT/.deslop/runs/${timestamp}-verify-${FINDING_ID}"
mkdir -p "$run_dir"
finding_json="$run_dir/finding.json"
python3 - "$ROOT" "$FINDING_ID" "$finding_json" <<'PY'
import json
import sys
from pathlib import Path
root = Path(sys.argv[1])
finding_id = sys.argv[2]
target = Path(sys.argv[3])
items = [json.loads(line) for line in (root / ".deslop" / "findings.jsonl").read_text().splitlines() if line.strip()]
finding = next((item for item in items if item.get("id") == finding_id), None)
if finding is None:
    print(f"finding not found: {finding_id}", file=sys.stderr)
    raise SystemExit(1)
target.write_text(json.dumps(finding, indent=2, sort_keys=True) + "\n")
PY

fix_context="$run_dir/fix-attempt-context.txt"
python3 - "$finding_json" "$fix_context" <<'PY'
import json
import sys
from pathlib import Path

finding = json.loads(Path(sys.argv[1]).read_text())
target = Path(sys.argv[2])
snapshots = ((finding.get("last_fix") or {}).get("snapshot_paths") or {})

def read_limited(path_value, *, max_chars=80000):
    if not path_value:
        return "[missing]\n"
    path = Path(str(path_value))
    if not path.exists():
        return f"[missing: {path}]\n"
    text = path.read_text(errors="ignore")
    if len(text) > max_chars:
        return text[:max_chars] + f"\n[truncated at {max_chars} chars]\n"
    return text

if not snapshots:
    target.write_text(
        "No per-finding fix snapshot is recorded for this finding. "
        "Use the current git diff, but treat unrelated pre-existing changes cautiously.\n"
    )
else:
    sections = [
        ("Git status before this fix attempt", read_limited(snapshots.get("status_before"), max_chars=20000)),
        ("Git status after this fix attempt", read_limited(snapshots.get("status_after"), max_chars=20000)),
        (
            "Patch-of-patches for changes introduced during this fix attempt",
            read_limited(snapshots.get("attempt_delta")),
        ),
        ("Full git diff before this fix attempt", read_limited(snapshots.get("diff_before"))),
        ("Full git diff after this fix attempt", read_limited(snapshots.get("diff_after"))),
    ]
    rendered = []
    for title, text in sections:
        body = text or "[empty]\n"
        rendered.append(f"## {title}\n{body}")
    target.write_text("\n\n".join(rendered) + "\n")
PY

prompt="$run_dir/prompt.txt"
raw="$run_dir/raw-verify-output.txt"
verify_json="$run_dir/verify.json"
last_message="$run_dir/last-message.txt"
runner_json="$run_dir/runner.json"
schema="$SCRIPT_DIR/../references/verify.schema.json"

cat > "$prompt" <<EOF
You are running as the selected Ultimate De-Slop verifier role. Do not delegate to another verifier, load skill files recursively, or run nested de-slop harness commands. Consider these two perspectives internally:
1. acceptance verifier: did the fix satisfy the finding?
2. regression/slop verifier: did it introduce regressions, over-abstraction, or move complexity?

Do not edit files. Verify the original finding against the check output and the per-finding fix attempt context. Base the finding-specific verdict on the delta introduced during this fix attempt. The current git diff may include earlier verified but uncommitted findings; use it only for interaction/regression context and do not fail solely because unrelated baseline changes are present. Judge whether the fix truly satisfies acceptance criteria, whether behavior stayed intact, and whether the patch created new slop. Return PASS, FAIL, NEEDS_HUMAN, or FALSE_POSITIVE.

Every verdict requires non-empty evidence. NEEDS_HUMAN requires non-empty concerns or required_follow_up explaining what a human must decide. FALSE_POSITIVE evidence must explain why the original finding was invalid.
If acceptance criteria or expected checks imply behavioral coverage (unittest/pytest/assert/test), a PASS should only stand when the fix also added or updated a focused test; otherwise return NEEDS_HUMAN explaining the test gap.

Return exactly one JSON object, no markdown fences and no prose, with these keys:
finding_id, verdict, confidence, evidence, concerns, required_follow_up.

Finding:
$(cat "$finding_json")

Check results:
$(cat "$CHECKS_JSON")

Per-finding fix attempt context:
$(cat "$fix_context")

Current full git diff for interaction/regression context:
$(git -C "$ROOT" diff -- . ':!.deslop/runs' ':!.deslop/tmp')
EOF

set +e
"$SCRIPT_DIR/deslop-agent-runner.py" --root "$ROOT" --prompt "$prompt" --raw-output "$raw" --last-message "$last_message" --runner-json "$runner_json" --schema "$schema" --sandbox read-only --kind verify
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf 'deslop-verify: error: %s verifier failed with exit code %s. Raw output: %s Runner: %s\n' "${DESLOP_HARNESS:-codex}" "$code" "$raw" "$runner_json" >&2
  exit "$code"
fi
if ! extract_json "$last_message" "$verify_json" "$FINDING_ID" && ! extract_json "$raw" "$verify_json" "$FINDING_ID"; then
  printf 'deslop-verify: error: JSON extraction failed. Raw output: %s\n' "$raw" >&2
  exit 1
fi

python3 - "$verify_json" "$finding_json" <<'PY'
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
finding = json.loads(Path(sys.argv[2]).read_text())
data = json.loads(path.read_text())
verdict = str(data.get("verdict", "")).upper()
evidence = [str(item).strip() for item in (data.get("evidence") or []) if str(item).strip()]
concerns = [str(item).strip() for item in (data.get("concerns") or []) if str(item).strip()]
follow_up = [str(item).strip() for item in (data.get("required_follow_up") or []) if str(item).strip()]

def looks_like_test_path(value: str) -> bool:
    lowered = value.replace("\\", "/").lower()
    name = Path(lowered).name
    return (
        "/tests/" in f"/{lowered}"
        or "/test/" in f"/{lowered}"
        or name.startswith("test_")
        or name.endswith("_test.py")
        or name.endswith("_test.go")
        or name.endswith(".test.ts")
        or name.endswith(".test.js")
        or name.endswith(".spec.ts")
        or name.endswith(".spec.js")
        or "spec." in name
    )

def expects_behavioral_coverage(item: dict) -> bool:
    checks = [str(check).lower() for check in (item.get("expected_checks") or [])]
    if any(token in check for check in checks for token in ("unittest", "pytest", "npm test", "pnpm test", "yarn test", "go test", "cargo test")):
        return True
    criteria = [str(entry) for entry in (item.get("acceptance_criteria") or [])]
    pattern = re.compile(
        r"\b(unit\s*tests?|tests?|asserts?|unittest|pytest|specs?)\b|"
        r"\b(add|update|write|cover|include).{0,40}\b(test|assert|spec)s?\b|"
        r"\bregression\b",
        re.IGNORECASE,
    )
    return any(pattern.search(entry) for entry in criteria)

errors = []
if not evidence:
    errors.append("evidence must be a non-empty list explaining the verdict")
if verdict == "NEEDS_HUMAN" and not concerns and not follow_up:
    errors.append("NEEDS_HUMAN requires non-empty concerns or required_follow_up")
if verdict == "PASS" and expects_behavioral_coverage(finding):
    changed = []
    last_fix = finding.get("last_fix") if isinstance(finding.get("last_fix"), dict) else {}
    raw_changed = last_fix.get("changed_files") or []
    if isinstance(raw_changed, list):
        changed = [str(entry) for entry in raw_changed]
    if not any(looks_like_test_path(entry) for entry in changed):
        errors.append(
            "PASS rejected: acceptance criteria or expected checks imply behavioral coverage, "
            "but last_fix.changed_files includes no test/spec file. Add a focused test or return NEEDS_HUMAN."
        )
if errors:
    print(f"deslop-verify: error: thin verifier verdict rejected for {verdict or 'UNKNOWN'}:", file=sys.stderr)
    for item in errors:
        print(f"  - {item}", file=sys.stderr)
    raise SystemExit(1)

print(f"Verifier verdict: {data.get('verdict', 'UNKNOWN')}")
PY
printf 'Verify JSON: %s\n' "$verify_json"
