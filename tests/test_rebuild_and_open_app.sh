#!/usr/bin/env bash
# Credential-free tests for the local kill-build-run entrypoint.
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
FAKE_BIN="$TMP/bin"
PS_TABLE="$TMP/ps-table"
KILL_LOG="$TMP/kill.log"

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

ROOT="$TMP/repo"
mkdir -p "$FAKE_BIN" "$ROOT/scripts" "$ROOT/.codex/environments"
# Keep the fixture's expected Debug path independent of CI's exported build
# paths, which point at the real checkout.
export APM44_APP_DERIVED_DATA="$ROOT/build/app"
export APM44_BUILD_CONFIG=Debug
cp "$SOURCE_ROOT/scripts/rebuild-and-open-app.sh" "$ROOT/scripts/"
cp "$SOURCE_ROOT/.codex/environments/environment.toml" "$ROOT/.codex/environments/environment.toml"

SCRIPT="$ROOT/scripts/rebuild-and-open-app.sh"
ISOLATED_EXE="$ROOT/build/isolated-app/Build/Products/Debug/APM44 Bridge.app/Contents/MacOS/APM44 Bridge"
INSTALLED_EXE="/Applications/APM44 Bridge.app/Contents/MacOS/APM44 Bridge"

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "expected to find '$needle' in $file" >&2
    echo "--- $file ---" >&2
    cat "$file" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$file"; then
    echo "did not expect to find '$needle' in $file" >&2
    echo "--- $file ---" >&2
    cat "$file" >&2
    exit 1
  fi
}

cat >"$FAKE_BIN/ps" <<'EOF'
#!/bin/bash
set -euo pipefail
table="${APM44_FAKE_PS_TABLE:?}"
if [[ "${1:-}" == "-p" ]]; then
  want="$2"
  while IFS= read -r line; do
    read -r pid cmd <<<"$line"
    if [[ "$pid" == "$want" ]]; then
      printf '%s\n' "$cmd"
      exit 0
    fi
  done <"$table"
  exit 1
fi
cat "$table"
EOF

cat >"$FAKE_BIN/kill" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "kill $*" >>"${APM44_FAKE_KILL_LOG:?}"
pid=""
for arg in "$@"; do
  if [[ "$arg" =~ ^[0-9]+$ ]]; then
    pid="$arg"
  fi
done
[[ -n "$pid" ]] || exit 0
tmp="$(mktemp)"
while IFS= read -r line; do
  read -r row_pid _ <<<"$line"
  if [[ "$row_pid" != "$pid" ]]; then
    printf '%s\n' "$line"
  fi
done <"${APM44_FAKE_PS_TABLE:?}" >"$tmp"
mv "$tmp" "${APM44_FAKE_PS_TABLE:?}"
EOF

cat >"$FAKE_BIN/pkill" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "pkill $*" >>"${APM44_FAKE_KILL_LOG:?}"
exit 0
EOF

cat >"$FAKE_BIN/pgrep" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "pgrep $*" >>"${APM44_FAKE_KILL_LOG:?}"
if [[ -f "${APM44_FAKE_STARTED:-}" ]]; then
  echo 4242
  exit 0
fi
exit 1
EOF

cat >"$FAKE_BIN/sleep" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$FAKE_BIN/bash" <<'EOF'
#!/bin/bash
set -euo pipefail
script="${1:-}"
if [[ "$script" == scripts/verify-app-build.sh ]]; then
  printf '%s\n' "BUILD $script" >>"${APM44_FAKE_KILL_LOG:?}"
  dest="${PWD}/build/app/Build/Products/Debug/APM44 Bridge.app/Contents/MacOS"
  mkdir -p "$dest"
  printf 'fake app\n' >"$dest/APM44 Bridge"
  chmod +x "$dest/APM44 Bridge"
  exit 0
fi
exec /bin/bash "$@"
EOF

cat >"$FAKE_BIN/open" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "open $*" >>"${APM44_FAKE_KILL_LOG:?}"
: >"${APM44_FAKE_STARTED:?}"
exit 0
EOF

chmod +x "$FAKE_BIN/ps" "$FAKE_BIN/kill" "$FAKE_BIN/pkill" "$FAKE_BIN/pgrep" "$FAKE_BIN/sleep" "$FAKE_BIN/bash" "$FAKE_BIN/open"

run_isolated_stop_leaves_installed_app() {
  : >"$KILL_LOG"
  cat >"$PS_TABLE" <<EOF
 2222 $INSTALLED_EXE
EOF

  env \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    APM44_FAKE_PS_TABLE="$PS_TABLE" \
    APM44_FAKE_KILL_LOG="$KILL_LOG" \
    /bin/bash "$SCRIPT" --isolated-stop

  assert_not_contains "$KILL_LOG" "pkill"
  assert_contains "$PS_TABLE" "$INSTALLED_EXE"
}

run_local_pid_matcher() {
  local out="$TMP/pids.out"
  cat >"$PS_TABLE" <<EOF
 1111 $ISOLATED_EXE -SUEnableAutomaticChecks NO -SUAutomaticallyUpdate NO
 2222 $INSTALLED_EXE
EOF
  awk -v target="$ISOLATED_EXE" '
    {
      pid=$1
      sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "")
      if ($0 == target || index($0, target " ") == 1) print pid
    }' "$PS_TABLE" >"$out"
  [[ "$(tr -d '[:space:]' <"$out")" == "1111" ]] || {
    echo "local pid matcher should select only the isolated executable" >&2
    cat "$out" >&2
    exit 1
  }
}

run_help_and_usage() {
  local out="$TMP/help.out"
  /bin/bash "$SCRIPT" --help >"$out" 2>&1
  assert_contains "$out" "--isolated"
  assert_contains "$out" "--isolated-stop"

  local status=0
  /bin/bash "$SCRIPT" --not-a-mode >"$out" 2>&1 || status=$?
  [[ "$status" -eq 2 ]] || { echo "invalid mode should exit 2, got $status" >&2; cat "$out" >&2; exit 1; }
}

run_source_contracts() {
  assert_not_contains "$SOURCE_ROOT/scripts/rebuild-and-open-app.sh" "notary"
  assert_not_contains "$SOURCE_ROOT/scripts/verify-app-build.sh" "notary"
  [[ ! -e "$SOURCE_ROOT/script/build_and_run.sh" ]] || {
    echo "do not add script/build_and_run.sh; rebuild-and-open-app.sh is the entry" >&2
    exit 1
  }
  assert_contains "$SOURCE_ROOT/.codex/environments/environment.toml" \
    "bash scripts/rebuild-and-open-app.sh --isolated"
  assert_contains "$SOURCE_ROOT/scripts/rebuild-and-open-app.sh" "ps -axww -o pid=,command="

  local stop_line build_line isolated_exit
  stop_line="$(grep -n '^  stop_named_processes$' "$SOURCE_ROOT/scripts/rebuild-and-open-app.sh" | head -1 | cut -d: -f1)"
  build_line="$(grep -n '^build_app$' "$SOURCE_ROOT/scripts/rebuild-and-open-app.sh" | head -1 | cut -d: -f1)"
  isolated_exit="$(grep -nF -- 'isolated-stop" ]] && exit 0' "$SOURCE_ROOT/scripts/rebuild-and-open-app.sh" | head -1 | cut -d: -f1)"
  if [[ -z "$stop_line" || -z "$build_line" || -z "$isolated_exit" ]]; then
    echo "rebuild-and-open-app.sh is missing kill/build call sites" >&2
    exit 1
  fi
  if [[ "$stop_line" -ge "$build_line" ]]; then
    echo "default run must stop existing processes before rebuilding the bundle" >&2
    exit 1
  fi
  if [[ "$isolated_exit" -ge "$build_line" ]]; then
    echo "--isolated-stop must exit before verify-app-build" >&2
    exit 1
  fi
}

run_stubbed_default_run_stops_before_build() {
  local out="$TMP/default-run.out"
  local started="$TMP/started"
  local exe="$ROOT/build/app/Build/Products/Debug/APM44 Bridge.app/Contents/MacOS/APM44 Bridge"
  : >"$KILL_LOG"
  rm -f "$started"
  printf ' 4242 %s\n' "$exe" >"$PS_TABLE"

  env \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    APM44_FAKE_PS_TABLE="$PS_TABLE" \
    APM44_FAKE_KILL_LOG="$KILL_LOG" \
    APM44_FAKE_STARTED="$started" \
    APM44_OPEN_BIN="$FAKE_BIN/open" \
    /bin/bash "$SCRIPT" run >"$out" 2>&1

  assert_contains "$KILL_LOG" "pkill -TERM -x APM44 Bridge"
  assert_contains "$KILL_LOG" "BUILD scripts/verify-app-build.sh"
  assert_contains "$KILL_LOG" "open -n"
  assert_contains "$out" "Running: 4242"

  local pkill_line build_line open_line
  pkill_line="$(grep -n 'pkill -TERM -x APM44 Bridge' "$KILL_LOG" | head -1 | cut -d: -f1)"
  build_line="$(grep -n 'BUILD scripts/verify-app-build.sh' "$KILL_LOG" | head -1 | cut -d: -f1)"
  open_line="$(grep -n 'open -n' "$KILL_LOG" | head -1 | cut -d: -f1)"
  if [[ -z "$pkill_line" || -z "$build_line" || -z "$open_line" ]]; then
    echo "stubbed default run: missing pkill/build/open" >&2
    cat "$KILL_LOG" >&2
    cat "$out" >&2
    exit 1
  fi
  if [[ "$pkill_line" -ge "$build_line" || "$build_line" -ge "$open_line" ]]; then
    echo "stubbed default run order must be stop, build, launch" >&2
    cat "$KILL_LOG" >&2
    exit 1
  fi
}

run_stubbed_no_launch_skips_stop() {
  local out="$TMP/no-launch.out"
  : >"$KILL_LOG"

  env \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    APM44_FAKE_PS_TABLE="$PS_TABLE" \
    APM44_FAKE_KILL_LOG="$KILL_LOG" \
    APM44_FAKE_STARTED="$TMP/started-no-launch" \
    APM44_OPEN_BIN="$FAKE_BIN/open" \
    /bin/bash "$SCRIPT" --no-launch >"$out" 2>&1

  assert_contains "$KILL_LOG" "BUILD scripts/verify-app-build.sh"
  assert_not_contains "$KILL_LOG" "pkill"
  assert_not_contains "$KILL_LOG" "open -n"
}

run_help_and_usage
run_source_contracts
run_local_pid_matcher
run_isolated_stop_leaves_installed_app
run_stubbed_default_run_stops_before_build
run_stubbed_no_launch_skips_stop

echo "rebuild-and-open-app tests: OK"
