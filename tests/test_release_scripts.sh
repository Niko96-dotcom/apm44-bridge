#!/usr/bin/env bash
# Credential-free regression tests for release notarization scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
FAKE_BIN="$TMP/bin"
LOG="$TMP/fake-xcrun.log"

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

mkdir -p "$FAKE_BIN"

cat >"$FAKE_BIN/xcrun" <<'EOF'
#!/bin/bash
set -euo pipefail

log="${APM44_FAKE_XCRUN_LOG:?}"
printf '%s\n' "xcrun $*" >>"$log"

if [[ "$1" == "notarytool" && "$2" == "submit" ]]; then
  case "${APM44_FAKE_NOTARY_MODE:-accepted}" in
    accepted)
      echo "id: accepted-submission"
      echo "status: Accepted"
      exit 0
      ;;
    rejected)
      echo "id: rejected-submission"
      echo "status: Invalid"
      exit 0
      ;;
    auth-failure)
      echo "id: auth-submission"
      echo "Error: notary credentials unavailable"
      exit 1
      ;;
    network-failure)
      echo "id: network-submission"
      echo "Error: network unavailable"
      exit 75
      ;;
    malformed)
      echo "id: malformed-submission"
      echo "upload complete"
      exit 0
      ;;
    *)
      echo "unknown fake notary mode" >&2
      exit 64
      ;;
  esac
fi

if [[ "$1" == "notarytool" && "$2" == "log" ]]; then
  echo "notary log for $3"
  exit 0
fi

if [[ "$1" == "notarytool" && "$2" == "history" ]]; then
  if [[ "${APM44_FAKE_NOTARY_HISTORY:-fail}" == "ok" ]]; then
    echo "notary history ok"
    exit 0
  fi
  echo "notary profile unavailable" >&2
  exit 1
fi

if [[ "$1" == "stapler" && ( "$2" == "staple" || "$2" == "validate" ) ]]; then
  echo "stapler $2 ok"
  exit 0
fi

echo "unsupported fake xcrun command: $*" >&2
exit 64
EOF

cat >"$FAKE_BIN/security" <<'EOF'
#!/bin/bash
set -euo pipefail

if [[ "${1:-}" == "find-identity" ]]; then
  echo '  1) FAKECERT "Developer ID Installer: APM44 Test Org (LOCALTEAM)"'
  exit 0
fi

echo "unsupported fake security command: $*" >&2
exit 64
EOF

cat >"$FAKE_BIN/xcodegen" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "fake xcodegen"
EOF

cat >"$FAKE_BIN/bash" <<'EOF'
#!/bin/bash
set -euo pipefail

script="${1:-}"
if [[ -n "$script" ]]; then
  shift
fi

case "$script" in
  scripts/build-release-dmg.sh|scripts/notary-dry-run.sh|scripts/notarize-release-dmg.sh|scripts/build-release-pkg.sh|scripts/notarize-release-pkg.sh)
    printf '%s\n' "bash $script $*" >>"${APM44_FAKE_XCRUN_LOG:?}"
    exit 0
    ;;
  *)
    exec /bin/bash "$script" "$@"
    ;;
esac
EOF

cat >"$FAKE_BIN/ls" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "fake ls $*"
EOF

chmod +x "$FAKE_BIN/xcrun" "$FAKE_BIN/security" "$FAKE_BIN/xcodegen" "$FAKE_BIN/bash" "$FAKE_BIN/ls"

DMG="$TMP/APM44Bridge.dmg"
PKG="$TMP/APM44Bridge.pkg"
touch "$DMG" "$PKG"

reset_log() {
  : >"$LOG"
}

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq "$needle" "$file"; then
    echo "expected to find '$needle' in $file" >&2
    echo "--- $file ---" >&2
    cat "$file" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq "$needle" "$file"; then
    echo "did not expect to find '$needle' in $file" >&2
    echo "--- $file ---" >&2
    cat "$file" >&2
    exit 1
  fi
}

run_notary_case() {
  local script="$1"
  local artifact_env="$2"
  local artifact_path="$3"
  local mode="$4"
  local expected="$5"
  local label="$6"
  local out="$TMP/$label.out"
  local status=0

  reset_log
  if env \
    PATH="$FAKE_BIN:$PATH" \
    APM44_FAKE_XCRUN_LOG="$LOG" \
    APM44_FAKE_NOTARY_MODE="$mode" \
    NOTARY_PROFILE=TEST_PROFILE \
    "$artifact_env=$artifact_path" \
    /bin/bash "$ROOT/$script" >"$out" 2>&1; then
    status=0
  else
    status=$?
  fi

  if [[ "$expected" == "success" && "$status" -ne 0 ]]; then
    echo "$label: expected success, got exit $status" >&2
    cat "$out" >&2
    exit 1
  fi

  if [[ "$expected" == "failure" && "$status" -eq 0 ]]; then
    echo "$label: expected failure, got success" >&2
    cat "$out" >&2
    exit 1
  fi

  assert_contains "$LOG" "notarytool submit"
  if [[ "$expected" == "success" ]]; then
    assert_contains "$LOG" "stapler staple"
    assert_contains "$LOG" "stapler validate"
    assert_not_contains "$LOG" "notarytool log"
  else
    assert_not_contains "$LOG" "stapler staple"
    assert_contains "$LOG" "notarytool log"
  fi
}

run_release_all_missing_credentials() {
  local out="$TMP/release-all-missing.out"
  local status=0

  reset_log
  if env \
    PATH="$FAKE_BIN:$PATH" \
    APM44_FAKE_XCRUN_LOG="$LOG" \
    APM44_FAKE_NOTARY_HISTORY=fail \
    /bin/bash "$ROOT/scripts/release-all.sh" >"$out" 2>&1; then
    status=0
  else
    status=$?
  fi

  if [[ "$status" -eq 0 ]]; then
    echo "release-all missing credentials: expected failure" >&2
    cat "$out" >&2
    exit 1
  fi

  assert_contains "$out" "Public release artifacts must be notarized"
  assert_contains "$out" "APM44_ALLOW_UNNOTARIZED=1"
  assert_not_contains "$LOG" "scripts/build-release-dmg.sh"
}

run_release_all_unnotarized_override() {
  local out="$TMP/release-all-override.out"

  reset_log
  env \
    PATH="$FAKE_BIN:$PATH" \
    APM44_FAKE_XCRUN_LOG="$LOG" \
    APM44_FAKE_NOTARY_HISTORY=fail \
    APM44_ALLOW_UNNOTARIZED=1 \
    /bin/bash "$ROOT/scripts/release-all.sh" >"$out" 2>&1

  assert_contains "$out" "LOCAL-ONLY UNNOTARIZED"
  assert_contains "$out" "Local-only unnotarized artifacts"
  assert_contains "$LOG" "scripts/build-release-dmg.sh"
  assert_not_contains "$LOG" "notarytool submit"
}

run_notary_case "scripts/notarize-release-dmg.sh" APM44_DMG_PATH "$DMG" accepted success "dmg-accepted"
run_notary_case "scripts/notarize-release-pkg.sh" APM44_PKG_PATH "$PKG" accepted success "pkg-accepted"

run_notary_case "scripts/notarize-release-dmg.sh" APM44_DMG_PATH "$DMG" rejected failure "dmg-rejected"
run_notary_case "scripts/notarize-release-pkg.sh" APM44_PKG_PATH "$PKG" rejected failure "pkg-rejected"

run_notary_case "scripts/notarize-release-dmg.sh" APM44_DMG_PATH "$DMG" auth-failure failure "dmg-auth-failure"
run_notary_case "scripts/notarize-release-dmg.sh" APM44_DMG_PATH "$DMG" network-failure failure "dmg-network-failure"
run_notary_case "scripts/notarize-release-dmg.sh" APM44_DMG_PATH "$DMG" malformed failure "dmg-malformed"

run_release_all_missing_credentials
run_release_all_unnotarized_override

echo "release script tests: OK"
