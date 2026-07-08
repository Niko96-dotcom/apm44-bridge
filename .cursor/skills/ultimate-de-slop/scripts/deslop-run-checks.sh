#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: deslop-run-checks.sh [--no-fail] FINDING_ID

Run expected checks for a finding, or detected default checks if none are listed.
EOF
}

NO_FAIL=0
FINDING_ID=""
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --no-fail)
      NO_FAIL=1
      shift
      ;;
    -*)
      printf 'deslop-run-checks: error: unknown option: %s\n' "$1" >&2
      exit 1
      ;;
    *)
      if [ -n "$FINDING_ID" ]; then
        printf 'deslop-run-checks: error: expected one finding id\n' >&2
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

ROOT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" || {
  printf 'deslop-run-checks: error: could not resolve git root; run from inside a git repository\n' >&2
  exit 1
}

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
run_dir="$ROOT/.deslop/runs/${timestamp}-checks-${FINDING_ID}"
mkdir -p "$run_dir"
commands_json="$run_dir/commands.json"
allowed_commands_json="$run_dir/allowed_commands.json"
results_jsonl="$run_dir/results.jsonl"
checks_jsonl="$run_dir/checks.jsonl"
checks_json="$run_dir/checks.json"

python3 - "$ROOT" "$FINDING_ID" "$commands_json" <<'PY'
import json
import shlex
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
finding_id = sys.argv[2]
target = Path(sys.argv[3])
findings_path = root / ".deslop" / "findings.jsonl"
if not findings_path.exists():
    print("findings.jsonl not found; run deslop-init.sh first", file=sys.stderr)
    raise SystemExit(1)
findings = [json.loads(line) for line in findings_path.read_text().splitlines() if line.strip()]
finding = next((item for item in findings if item.get("id") == finding_id), None)
if finding is None:
    print(f"finding not found: {finding_id}", file=sys.stderr)
    raise SystemExit(1)
commands = [str(item) for item in (finding.get("expected_checks") or []) if str(item).strip()]
inventory_path = root / ".deslop" / "inventory.json"
inventory_commands = []
if inventory_path.exists():
    inventory = json.loads(inventory_path.read_text())
    inventory_commands = [str(item.get("command")) for item in inventory.get("detected_commands", []) if item.get("command")]
if not commands:
    commands = inventory_commands

def is_pytest_command(command: str) -> bool:
    try:
        tokens = shlex.split(command)
    except ValueError:
        return False
    return tuple(tokens[:3]) in {("python", "-m", "pytest"), ("python3", "-m", "pytest")} or tuple(tokens[:1]) == ("pytest",)

def pytest_command_available(command: str) -> bool:
    try:
        tokens = shlex.split(command)
    except ValueError:
        return False
    if tuple(tokens[:3]) in {("python", "-m", "pytest"), ("python3", "-m", "pytest")}:
        probe = tokens[:3] + ["--version"]
    elif tuple(tokens[:1]) == ("pytest",):
        probe = ["pytest", "--version"]
    else:
        return True
    try:
        result = subprocess.run(
            ["bash", "-lc", shlex.join(probe)],
            cwd=root,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except FileNotFoundError:
        return False
    return result.returncode == 0

py_compile_fallback = next((command for command in inventory_commands if " -m py_compile " in f" {command} "), None)
if commands and py_compile_fallback:
    commands = [
        py_compile_fallback if is_pytest_command(command) and not pytest_command_available(command) else command
        for command in commands
    ]
target.write_text(json.dumps(commands, indent=2, sort_keys=True) + "\n")
PY

python3 - "$ROOT" "$allowed_commands_json" "$commands_json" "$SCRIPT_DIR/deslop-run-checks.sh" <<'PY'
import json
import shlex
import sys
from pathlib import Path

root = Path(sys.argv[1])
target = Path(sys.argv[2])
commands_path = Path(sys.argv[3])
run_checks_path = Path(sys.argv[4])
inventory_path = root / ".deslop" / "inventory.json"
allowlist = []

SAFE_PREFIXES = (
    ("python", "-m", "pytest"),
    ("python3", "-m", "pytest"),
    ("python", "-m", "unittest"),
    ("python3", "-m", "unittest"),
    ("python", "-m", "py_compile"),
    ("python3", "-m", "py_compile"),
    ("pytest",),
    ("ruff", "check"),
    ("mypy",),
    ("lint-imports",),
    ("import-linter",),
    ("uv", "run", "pytest"),
    ("uv", "run", "ruff"),
    ("uv", "run", "mypy"),
    ("uv", "run", "lint-imports"),
    ("uv", "run", "import-linter"),
    ("poetry", "run", "pytest"),
    ("poetry", "run", "ruff"),
    ("poetry", "run", "mypy"),
    ("pipenv", "run", "pytest"),
    ("npm", "--prefix"),
    ("npm", "test"),
    ("npm", "run"),
    ("pnpm", "test"),
    ("pnpm", "run"),
    ("yarn", "test"),
    ("yarn", "run"),
    ("bun", "test"),
    ("cargo", "test"),
    ("go", "test"),
    ("swift", "test"),
    ("git", "diff", "--check"),
    ("git", "status"),
    ("test", "-d"),
    ("test", "-f"),
)
SAFE_ENV = {"CI", "NODE_ENV", "PYTHONPATH", "UV_CACHE_DIR"}

def has_unsafe_shell_syntax(command_text: str) -> bool:
    if "\n" in command_text or "\r" in command_text:
        return True
    for pattern in ("$(", "${", "`"):
        if pattern in command_text:
            return True
    try:
        tokens = shlex.split(command_text)
    except ValueError:
        return True
    for token in tokens:
        if token in {";", "|", "||", "&", "&&", ">", ">>", "<", "<<", "|&"}:
            return True
    return False

def strip_env(tokens: list[str]) -> list[str]:
    rest = list(tokens)
    while rest:
        head = rest[0]
        if "=" not in head or head.startswith("-"):
            break
        name, _value = head.split("=", 1)
        if not name.replace("_", "").isalnum() or name not in SAFE_ENV:
            break
        rest.pop(0)
    return rest

def is_safe_check_command(command_text: str) -> bool:
    value = command_text.strip()
    if not value or has_unsafe_shell_syntax(value):
        return False
    tokens = strip_env(shlex.split(value))
    if not tokens:
        return False
    if tokens[:2] in (["npm", "test"], ["pnpm", "test"], ["yarn", "test"]):
        return len(tokens) == 2
    if tokens[:2] in (["npm", "run"], ["pnpm", "run"], ["yarn", "run"]):
        return len(tokens) == 3 and bool(tokens[2].strip())
    if tokens[:2] in (["npm", "--prefix"], ["pnpm", "--dir"]):
        return len(tokens) == 5 and tokens[3] == "run" and bool(tokens[2].strip()) and bool(tokens[4].strip())
    for prefix in SAFE_PREFIXES:
        if tuple(tokens[: len(prefix)]) == prefix:
            return True
    return False

if inventory_path.exists():
  inventory = json.loads(inventory_path.read_text())
  for item in inventory.get("detected_commands", []):
    if isinstance(item, str) and item.strip():
      allowlist.append(item.strip())
    elif isinstance(item, dict):
      command = item.get("command")
      if isinstance(command, str) and command.strip():
        allowlist.append(command.strip())

# Baseline allowlist entries for existing de-slop checks.
allowlist.extend([
    f"grep -Fq 'bash -lc \"$command_text\"' {run_checks_path}",
])

if commands_path.exists():
  for command in json.loads(commands_path.read_text()):
    value = str(command).strip()
    if is_safe_check_command(value):
      allowlist.append(value)

normalized = []
for item in allowlist:
    value = str(item).strip()
    if value and value not in normalized:
        normalized.append(value)
target.write_text(json.dumps(normalized, indent=2, sort_keys=True) + "\n")
PY

count="$(python3 - "$commands_json" <<'PY'
import json, sys
print(len(json.loads(open(sys.argv[1]).read())))
PY
)"

if [ "$count" -eq 0 ]; then
  python3 - "$checks_json" "$FINDING_ID" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "finding_id": sys.argv[2],
    "status": "skipped",
    "reason": "no expected or detected checks",
    "created_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "results": []
}, indent=2, sort_keys=True) + "\n")
PY
  printf 'No checks found. Wrote %s\n' "$checks_json"
  exit 0
fi

: > "$results_jsonl"
: > "$checks_jsonl"
failures=0
index=0
while [ "$index" -lt "$count" ]; do
  command_text="$(python3 - "$commands_json" "$index" <<'PY'
import json, sys
commands = json.loads(open(sys.argv[1]).read())
print(commands[int(sys.argv[2])])
PY
)"
  output="$run_dir/check-$((index + 1)).log"
  start="$(date +%s)"
  set +e
  validation="$(python3 - "$command_text" "$allowed_commands_json" "$output" <<'PY'
import json
import shlex
import sys
from pathlib import Path

command_text = str(sys.argv[1]).strip()
allowed_commands = set(json.loads(Path(sys.argv[2]).read_text()))
output_path = Path(sys.argv[3])

if command_text not in allowed_commands:
    output_path.write_text("blocked: command is not allowlisted\n")
    print("command_not_allowlisted")
    raise SystemExit(2)

if "\n" in command_text or "\r" in command_text:
    output_path.write_text("blocked: command contains newline control characters\n")
    print("command_contains_control_characters")
    raise SystemExit(2)

try:
    tokens = shlex.split(command_text)
except ValueError as exc:
    output_path.write_text(f"blocked: command parsing failed: {exc}\n")
    print("invalid_shell_syntax")
    raise SystemExit(2)

for token in tokens:
    if token in {";", "|", "||", "&", "&&", ">", ">>", "<", "<<", "|&"}:
        output_path.write_text(f"blocked: command contains shell operator {token}\n")
        print("shell_operator_not_allowed")
        raise SystemExit(2)

for pattern in (
    "".join(("$", "(")),
    "".join(("$", "{")),
    chr(96),
):
    if pattern in command_text:
        output_path.write_text(f"blocked: command contains unsafe expansion pattern {pattern}\n")
        print("unsafe_expansion_pattern")
        raise SystemExit(2)

print("allowed")
PY
)"
  validation_code=$?
  if [ "$validation_code" -eq 0 ]; then
    (
      cd "$ROOT"
      printf '$ %s\n\n' "$command_text"
      bash -lc "$command_text"
    ) > "$output" 2>&1
    code=$?
  else
    code=2
    printf 'blocked: %s\n' "$validation" >> "$output"
  fi
  end="$(date +%s)"
  duration="$((end - start))"
  status="failed"
  if [ "$code" -ne 0 ]; then
    failures="$((failures + 1))"
    if [ "$validation_code" -ne 0 ]; then
      status="blocked"
    fi
  else
    status="passed"
  fi
  python3 - "$results_jsonl" "$checks_jsonl" "$command_text" "$code" "$duration" "$output" "$status" <<'PY'
import json
import sys
from pathlib import Path

legacy = Path(sys.argv[1])
checks = Path(sys.argv[2])
entry = {
    "command": sys.argv[3],
    "status": sys.argv[7],
    "exit_code": int(sys.argv[4]),
    "duration_seconds": int(sys.argv[5]),
    "output_path": sys.argv[6],
}
line = json.dumps(entry, sort_keys=True) + "\n"
with checks.open("a") as handle:
    handle.write(line)
with legacy.open("a") as handle:
    handle.write(line)
PY
  index="$((index + 1))"
done

python3 - "$checks_jsonl" "$results_jsonl" "$checks_json" "$FINDING_ID" "$failures" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

checks = Path(sys.argv[1])
legacy = Path(sys.argv[2])
checks_json = Path(sys.argv[3])
failures = int(sys.argv[5])
if checks.exists():
  results = [json.loads(line) for line in checks.read_text().splitlines() if line.strip()]
elif legacy.exists():
  results = [json.loads(line) for line in legacy.read_text().splitlines() if line.strip()]
else:
  results = []
payload = {
    "finding_id": sys.argv[4],
    "status": "failed" if failures else "passed",
    "created_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "results": results,
}
checks_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

printf 'Checks complete: %s\n' "$checks_json"
if [ "$failures" -ne 0 ] && [ "$NO_FAIL" -eq 0 ]; then
  exit 1
fi
