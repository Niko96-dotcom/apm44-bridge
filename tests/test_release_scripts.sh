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

cat >"$FAKE_BIN/codesign" <<'EOF'
#!/bin/bash
set -euo pipefail

if [[ "${1:-}" == "--verify" ]]; then
  exit 0
fi

if [[ "${1:-}" == "-dv" ]]; then
  case "${APM44_FAKE_CODESIGN_INFO:-strict-ok}" in
    strict-ok)
      echo "Authority=Developer ID Application: APM44 Test Org (LOCALTEAM)" >&2
      echo "Runtime Version=15.0.0" >&2
      ;;
    no-runtime)
      echo "Authority=Developer ID Application: APM44 Test Org (LOCALTEAM)" >&2
      ;;
    no-developer-id)
      echo "Runtime Version=15.0.0" >&2
      echo "Authority=Apple Development: Local" >&2
      ;;
    ad-hoc)
      echo "Authority=ad-hoc" >&2
      ;;
    *)
      echo "unsupported fake codesign info mode" >&2
      exit 64
      ;;
  esac
  exit 0
fi

echo "unsupported fake codesign command: $*" >&2
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
    prefix=""
    if [[ "${APM44_DMG_PACKAGE_ONLY:-0}" == "1" ]]; then
      prefix="APM44_DMG_PACKAGE_ONLY=1 "
    fi
    printf '%s\n' "${prefix}bash $script $*" >>"${APM44_FAKE_XCRUN_LOG:?}"
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

chmod +x "$FAKE_BIN/xcrun" "$FAKE_BIN/security" "$FAKE_BIN/codesign" "$FAKE_BIN/xcodegen" "$FAKE_BIN/bash" "$FAKE_BIN/ls"

DMG="$TMP/APM44Bridge.dmg"
PKG="$TMP/APM44Bridge.pkg"
DRIVER="$TMP/APM44Bridge.driver"
touch "$DMG" "$PKG"
mkdir -p "$DRIVER"

reset_log() {
  : >"$LOG"
}

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

run_release_all_notary_ready_sequence() {
  local out="$TMP/release-all-notary-ready.out"

  reset_log
  env \
    PATH="$FAKE_BIN:$PATH" \
    APM44_FAKE_XCRUN_LOG="$LOG" \
    APM44_FAKE_NOTARY_HISTORY=ok \
    /bin/bash "$ROOT/scripts/release-all.sh" >"$out" 2>&1

  assert_contains "$LOG" "bash scripts/build-release-dmg.sh"
  assert_contains "$LOG" "bash scripts/notary-dry-run.sh"
  assert_contains "$LOG" "xcrun stapler staple build/Release/APM44 Bridge.app"
  assert_contains "$LOG" "xcrun stapler validate build/Release/APM44 Bridge.app"
  assert_contains "$LOG" "xcrun stapler staple build/Driver/APM44Bridge.driver"
  assert_contains "$LOG" "xcrun stapler validate build/Driver/APM44Bridge.driver"
  assert_contains "$LOG" "APM44_DMG_PACKAGE_ONLY=1 bash scripts/build-release-dmg.sh"
  assert_contains "$LOG" "bash scripts/notarize-release-dmg.sh"
}

# DIST-01: enforce that inner app/driver are stapled before the final DMG is packaged,
# and that the final DMG is notarized after it is built from the stapled artifacts.
run_dist_01_staple_before_dmg_order() {
  local out="$TMP/dist-01-order.out"

  reset_log
  env \
    PATH="$FAKE_BIN:$PATH" \
    APM44_FAKE_XCRUN_LOG="$LOG" \
    APM44_FAKE_NOTARY_HISTORY=ok \
    /bin/bash "$ROOT/scripts/release-all.sh" >"$out" 2>&1

  local app_staple_line
  local driver_staple_line
  local package_only_line
  local dmg_notarize_line

  app_staple_line="$(grep -n "xcrun stapler staple build/Release/APM44 Bridge.app" "$LOG" | head -1 | cut -d: -f1)"
  driver_staple_line="$(grep -n "xcrun stapler staple build/Driver/APM44Bridge.driver" "$LOG" | head -1 | cut -d: -f1)"
  package_only_line="$(grep -n "APM44_DMG_PACKAGE_ONLY=1 bash scripts/build-release-dmg.sh" "$LOG" | head -1 | cut -d: -f1)"
  dmg_notarize_line="$(grep -n "bash scripts/notarize-release-dmg.sh" "$LOG" | head -1 | cut -d: -f1)"

  if [[ -z "$app_staple_line" || -z "$driver_staple_line" || -z "$package_only_line" || -z "$dmg_notarize_line" ]]; then
    echo "DIST-01: expected staple/package/notarize lines missing from log" >&2
    cat "$LOG" >&2
    exit 1
  fi

  if [[ "$app_staple_line" -ge "$package_only_line" ]]; then
    echo "DIST-01: app staple must occur before package-only DMG build" >&2
    exit 1
  fi

  if [[ "$driver_staple_line" -ge "$package_only_line" ]]; then
    echo "DIST-01: driver staple must occur before package-only DMG build" >&2
    exit 1
  fi

  if [[ "$package_only_line" -ge "$dmg_notarize_line" ]]; then
    echo "DIST-01: package-only DMG build must occur before DMG notarization" >&2
    exit 1
  fi
}

# DIST-05: generated DMG command installer replaces the app bundle deterministically.
run_dist_05_dmg_command_installer_check() {
  local script="$ROOT/scripts/build-release-dmg.sh"

  assert_contains "$script" 'sudo rm -rf "/Applications/APM44 Bridge.app"'
  assert_contains "$script" 'sudo ditto "\$DIR/APM44 Bridge.app" "/Applications/APM44 Bridge.app"'
  assert_contains "$script" 'sudo chown -R root:wheel "/Applications/APM44 Bridge.app"'
  assert_not_contains "$script" 'cp -R "\$DIR/APM44 Bridge.app" /Applications/'
}

# REL-03: sign-notarize.yml must fail the workflow if verify-app-build.sh fails.
run_sign_notarize_workflow_check() {     # [REL-03]
  local workflow="$ROOT/.github/workflows/sign-notarize.yml"
  if [[ ! -f "$workflow" ]]; then
    echo "REL-03: workflow file not found: $workflow" >&2
    exit 1
  fi
  assert_contains "$workflow" "bash scripts/verify-app-build.sh"
  assert_contains "$workflow" "cmake --build build --target apm44-bridge APM44Bridge"
  assert_contains "$workflow" "error: APPLE_SIGN_ID secret is required"
  assert_contains "$workflow" "error: AC_NOTARY keychain profile is required"
  assert_not_contains "$workflow" "SKIP: APPLE_SIGN_ID"
  assert_not_contains "$workflow" "SKIP: AC_NOTARY"
  if grep -Eq 'verify-app-build\.sh.*(\|\| *true|continue-on-error:\s*true)' "$workflow"; then
    echo "REL-03: sign-notarize.yml masks verify-app-build.sh failure" >&2
    exit 1
  fi
}

run_notarize_hal_driver_shared_helper_check() {
  local script="$ROOT/scripts/notarize-hal-driver.sh"
  assert_contains "$script" 'source "$ROOT/scripts/notary-result.sh"'
  assert_contains "$script" 'require_notary_accepted "$ZIP" "$PROFILE" "HAL driver"'
  assert_not_contains "$script" 'xcrun notarytool submit "$ZIP"'
}

# CI-01: release-facing workflows must reference only official actions/* actions,
# or document any third-party action in docs/release.md.
run_ci_01_workflow_trust_check() {       # [CI-01]
  local workflow
  for workflow in "$ROOT/.github/workflows/release.yml" "$ROOT/.github/workflows/sign-notarize.yml" "$ROOT/.github/workflows/ci.yml"; do
    if [[ ! -f "$workflow" ]]; then
      echo "CI-01: workflow file not found: $workflow" >&2
      exit 1
    fi

    if ! grep -q "CI-01" "$workflow"; then
      echo "CI-01: missing CI-01 trust marker in $workflow" >&2
      exit 1
    fi

    local line
    while IFS= read -r line; do
      if [[ "$line" =~ uses:[[:space:]]*([^[:space:]]+) ]]; then
        local action="${BASH_REMATCH[1]}"
        if [[ "$action" != actions/* ]]; then
          echo "CI-01: non-official action '$action' in $workflow must be documented in docs/release.md" >&2
          exit 1
        fi
      fi
    done < "$workflow"
  done
}

# CI-02: public GitHub CI must run release-script regressions after native tests.
run_ci_02_release_script_tests_in_github_ci() {
  local workflow="$ROOT/.github/workflows/ci.yml"
  if [[ ! -f "$workflow" ]]; then
    echo "CI-02: workflow file not found: $workflow" >&2
    exit 1
  fi

  assert_contains "$workflow" "Release script tests"
  assert_contains "$workflow" "bash tests/test_release_scripts.sh"

  local native_line
  local release_line
  native_line="$(grep -n "name: Native tests" "$workflow" | head -1 | cut -d: -f1)"
  release_line="$(grep -n "name: Release script tests" "$workflow" | head -1 | cut -d: -f1)"

  if [[ -z "$native_line" || -z "$release_line" ]]; then
    echo "CI-02: expected native and release-script test steps in $workflow" >&2
    exit 1
  fi

  if [[ "$release_line" -le "$native_line" ]]; then
    echo "CI-02: release-script tests must run after native tests" >&2
    exit 1
  fi
}

run_sign_01_03_workflow_release_app_alignment_check() {
  local workflow="$ROOT/.github/workflows/sign-notarize.yml"
  assert_contains "$workflow" "xcodebuild -project App/APM44Bridge.xcodeproj"
  assert_contains "$workflow" "-configuration Release"
  assert_contains "$workflow" 'CONFIGURATION_BUILD_DIR="$PWD/build/Release"'
  assert_contains "$workflow" "APM44_APP_OUTPUT_DIR=\"\$PWD/build/Release\""
  assert_contains "$workflow" "APM44_APP_PATH: \${{ github.workspace }}/build/Release/APM44 Bridge.app"
}

run_ci_03_local_ci_app_bundle_proof_check() {
  local script="$ROOT/scripts/ci.sh"
  assert_contains "$script" 'APP_PATH="$BUILD_DIR/$CONFIG/APM44 Bridge.app"'
  assert_contains "$script" 'APM44_APP_OUTPUT_DIR="$BUILD_DIR/$CONFIG"'
  assert_contains "$script" 'APM44_APP_PATH="$APP_PATH"'
  assert_contains "$script" 'bash scripts/embed-daemon-in-app.sh'
  assert_contains "$script" 'bash scripts/verify-installed-sync.sh --dry-run'
  assert_contains "$script" 'embedded helper missing'
}

run_doc_truth_check() { # [DOC-01][DOC-02][DOC-03]
  local install_doc="$ROOT/docs/install.md"
  local menu_qa="$ROOT/docs/menu-bar-qa.md"
  local release_doc="$ROOT/docs/release.md"
  local validation_doc="$ROOT/docs/release-validation.md"

  assert_contains "$install_doc" "Safe (~30 ms)"
  assert_contains "$install_doc" "fresh-install default"
  assert_contains "$menu_qa" "Safe default on fresh install"
  assert_not_contains "$menu_qa" "Balanced default on fresh install"

  assert_contains "$release_doc" "build/Driver/APM44Bridge.driver"
  assert_not_contains "$release_doc" "build/Release/APM44Bridge.driver"

  assert_contains "$validation_doc" "v0.9 public-polish validation path"
  assert_contains "$validation_doc" 'APM44Bridge-${APM44_VERSION:-0.1.1}.dmg'
  assert_not_contains "$validation_doc" "v0.8 release-candidate closeout"
}

run_codesign_verify_case() {
  local mode="$1"
  local override="$2"
  local expected="$3"
  local label="$4"
  local out="$TMP/$label.out"
  local root="$TMP/$label"
  local status=0

  mkdir -p "$root/app/APM44 Bridge.app" "$root/driver/APM44Bridge.driver" "$root/bin"
  touch "$root/bin/apm44-bridge"
  chmod +x "$root/bin/apm44-bridge"

  local env_args=(
    PATH="$FAKE_BIN:$PATH"
    APM44_FAKE_CODESIGN_INFO="$mode"
    APM44_DAEMON_PATH="$root/bin/apm44-bridge"
    APM44_APP_PATH="$root/app/APM44 Bridge.app"
    APM44_DRIVER_PATH="$root/driver/APM44Bridge.driver"
  )
  if [[ "$override" == "1" ]]; then
    env_args+=(APM44_ALLOW_LOCAL_CODESIGN=1)
  fi

  if env "${env_args[@]}" /bin/bash "$ROOT/scripts/codesign-verify-release.sh" >"$out" 2>&1; then
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
}

run_notary_case "scripts/notarize-release-dmg.sh" APM44_DMG_PATH "$DMG" accepted success "dmg-accepted"
run_notary_case "scripts/notarize-release-pkg.sh" APM44_PKG_PATH "$PKG" accepted success "pkg-accepted"
run_notary_case "scripts/notarize-hal-driver.sh" APM44_DRIVER_PATH "$DRIVER" accepted success "driver-accepted"

# REL-01: notarization must fail closed for any non-Accepted result or nonzero notarytool exit.
run_notary_case "scripts/notarize-release-dmg.sh" APM44_DMG_PATH "$DMG" rejected failure "dmg-rejected"       # [REL-01]
run_notary_case "scripts/notarize-release-pkg.sh" APM44_PKG_PATH "$PKG" rejected failure "pkg-rejected"     # [REL-01]
run_notary_case "scripts/notarize-hal-driver.sh" APM44_DRIVER_PATH "$DRIVER" rejected failure "driver-rejected" # [NOTARY-02]

run_notary_case "scripts/notarize-release-dmg.sh" APM44_DMG_PATH "$DMG" auth-failure failure "dmg-auth-failure"     # [REL-01]
run_notary_case "scripts/notarize-release-dmg.sh" APM44_DMG_PATH "$DMG" network-failure failure "dmg-network-failure" # [REL-01]
run_notary_case "scripts/notarize-release-dmg.sh" APM44_DMG_PATH "$DMG" malformed failure "dmg-malformed"           # [REL-01]

# REL-02: release-all requires explicit APM44_ALLOW_UNNOTARIZED=1 override when credentials are missing.
run_release_all_missing_credentials      # [REL-02]
run_release_all_unnotarized_override     # [REL-02]

run_release_all_notary_ready_sequence

run_dist_01_staple_before_dmg_order      # [DIST-01]

run_dist_05_dmg_command_installer_check  # [DIST-05]

run_sign_notarize_workflow_check         # [REL-03]

run_notarize_hal_driver_shared_helper_check # [NOTARY-01][NOTARY-02][NOTARY-03]

run_ci_01_workflow_trust_check           # [CI-01]

run_ci_02_release_script_tests_in_github_ci # [CI-02]

run_sign_01_03_workflow_release_app_alignment_check # [SIGN-01][SIGN-02][SIGN-03]

run_ci_03_local_ci_app_bundle_proof_check # [CI-01][CI-02][CI-03]

run_doc_truth_check # [DOC-01][DOC-02][DOC-03]

run_codesign_verify_case strict-ok 0 success "codesign-strict-ok"
run_codesign_verify_case no-runtime 0 failure "codesign-no-runtime"        # [REL-01]
run_codesign_verify_case no-developer-id 0 failure "codesign-no-dev-id"    # [REL-02]
run_codesign_verify_case ad-hoc 1 success "codesign-local-override"        # [REL-01][REL-02]

echo "release script tests: OK"
