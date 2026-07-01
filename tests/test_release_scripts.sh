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
  case "${APM44_FAKE_INSTALLER_IDENTITIES:-one}" in
    zero)
      ;;
    one)
      echo '  1) FAKECERT "Developer ID Installer: APM44 Test Org (LOCALTEAM)"'
      ;;
    multiple)
      echo '  1) FAKECERT "Developer ID Installer: APM44 Test Org (LOCALTEAM)"'
      echo '  2) FAKECERT "Developer ID Installer: APM44 Other Org (OTHERTEAM)"'
      ;;
    application-only)
      echo '  1) FAKECERT "Developer ID Application: APM44 Test Org (LOCALTEAM)"'
      ;;
    *)
      echo "unsupported fake identity mode: ${APM44_FAKE_INSTALLER_IDENTITIES}" >&2
      exit 64
      ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "import" ]]; then
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

cat >"$FAKE_BIN/pkgbuild" <<'EOF'
#!/bin/bash
set -euo pipefail
log="${APM44_FAKE_XCRUN_LOG:?}"
printf '%s\n' "pkgbuild $*" >>"$log"
out="${@: -1}"
mkdir -p "$(dirname "$out")"
printf 'unsigned pkg\n' >"$out"
EOF

cat >"$FAKE_BIN/productsign" <<'EOF'
#!/bin/bash
set -euo pipefail
log="${APM44_FAKE_XCRUN_LOG:?}"
printf '%s\n' "productsign $*" >>"$log"
if [[ "${1:-}" != "--sign" ]]; then
  echo "unsupported fake productsign command: $*" >&2
  exit 64
fi
identity="$2"
src="$3"
dest="$4"
if [[ "$identity" != Developer\ ID\ Installer:* ]]; then
  echo "fake productsign rejected non-installer identity: $identity" >&2
  exit 1
fi
cp "$src" "$dest"
EOF

cat >"$FAKE_BIN/ditto" <<'EOF'
#!/bin/bash
set -euo pipefail
log="${APM44_FAKE_XCRUN_LOG:?}"
printf '%s\n' "ditto $*" >>"$log"
args=("$@")
src="${args[$((${#args[@]} - 2))]}"
dest="${args[$((${#args[@]} - 1))]}"
if printf '%s\n' "$*" | grep -q -- '--keepParent'; then
  mkdir -p "$(dirname "$dest")"
  printf 'fake archive for %s\n' "$src" >"$dest"
else
  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  if [[ -d "$src" ]]; then
    cp -R "$src" "$dest"
  else
    cp "$src" "$dest"
  fi
fi
EOF

cat >"$FAKE_BIN/curl" <<'EOF'
#!/bin/bash
set -euo pipefail
out=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
if [[ -z "$out" ]]; then
  echo "fake curl requires -o" >&2
  exit 64
fi
mkdir -p "$(dirname "$out")"
printf 'fake cert\n' >"$out"
EOF

cat >"$FAKE_BIN/pkgutil" <<'EOF'
#!/bin/bash
set -euo pipefail
log="${APM44_FAKE_XCRUN_LOG:?}"
printf '%s\n' "pkgutil $*" >>"$log"
case "${1:-}" in
  --check-signature)
    echo "Package \"$2\":"
    echo "   Status: signed by a certificate trusted by macOS"
    echo "   1. Developer ID Installer: APM44 Test Org (LOCALTEAM)"
    ;;
  *)
    echo "unsupported fake pkgutil command: $*" >&2
    exit 64
    ;;
esac
EOF

cat >"$FAKE_BIN/spctl" <<'EOF'
#!/bin/bash
set -euo pipefail
log="${APM44_FAKE_XCRUN_LOG:?}"
printf '%s\n' "spctl $*" >>"$log"
echo "accepted"
EOF

cat >"$FAKE_BIN/bash" <<'EOF'
#!/bin/bash
set -euo pipefail

script="${1:-}"
if [[ -n "$script" ]]; then
  shift
fi

case "$script" in
  scripts/build-release-dmg.sh|scripts/codesign-verify-release.sh|scripts/notary-dry-run.sh|scripts/notarize-release-dmg.sh|scripts/build-release-pkg.sh|scripts/notarize-release-pkg.sh)
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

chmod +x "$FAKE_BIN/xcrun" "$FAKE_BIN/security" "$FAKE_BIN/codesign" "$FAKE_BIN/xcodegen" "$FAKE_BIN/pkgbuild" "$FAKE_BIN/productsign" "$FAKE_BIN/ditto" "$FAKE_BIN/curl" "$FAKE_BIN/pkgutil" "$FAKE_BIN/spctl" "$FAKE_BIN/bash" "$FAKE_BIN/ls"

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

prepare_pkg_inputs() {
  rm -rf "$ROOT/build/Release/APM44 Bridge.app" "$ROOT/build/Driver/APM44Bridge.driver"
  mkdir -p "$ROOT/build/Release/APM44 Bridge.app/Contents/MacOS"
  mkdir -p "$ROOT/build/Driver/APM44Bridge.driver/Contents/MacOS"
  printf 'fake app\n' >"$ROOT/build/Release/APM44 Bridge.app/Contents/MacOS/APM44Bridge"
  printf 'fake driver\n' >"$ROOT/build/Driver/APM44Bridge.driver/Contents/MacOS/APM44Bridge"
}

run_pkg_builder_case() {
  local mode="$1"
  local expected="$2"
  local label="$3"
  local out="$TMP/$label.out"
  local status=0

  prepare_pkg_inputs
  rm -f "$PKG" "${PKG%.pkg}-unsigned.pkg" "${PKG%.pkg}-local-unsigned.pkg"
  reset_log

  local env_args=(
    PATH="$FAKE_BIN:$PATH"
    APM44_FAKE_XCRUN_LOG="$LOG"
    APM44_FAKE_INSTALLER_IDENTITIES="$mode"
    APM44_PKG_PATH="$PKG"
    APM44_DEVID_G2_CA="$TMP/DeveloperIDG2CA.cer"
  )
  if [[ "$expected" == "local-unsigned" ]]; then
    env_args+=(APM44_ALLOW_UNSIGNED_PKG=1)
  fi

  if env "${env_args[@]}" /bin/bash "$ROOT/scripts/build-release-pkg.sh" >"$out" 2>&1; then
    status=0
  else
    status=$?
  fi

  case "$expected" in
    success)
      if [[ "$status" -ne 0 ]]; then
        echo "$label: expected success, got exit $status" >&2
        cat "$out" >&2
        exit 1
      fi
      [[ -f "$PKG" ]] || { echo "$label: expected final pkg at $PKG" >&2; cat "$out" >&2; exit 1; }
      assert_contains "$LOG" "productsign --sign Developer ID Installer: APM44 Test Org (LOCALTEAM)"
      ;;
    failure)
      if [[ "$status" -eq 0 ]]; then
        echo "$label: expected failure, got success" >&2
        cat "$out" >&2
        exit 1
      fi
      [[ ! -f "$PKG" ]] || { echo "$label: final public pkg should not exist" >&2; cat "$out" >&2; exit 1; }
      ;;
    local-unsigned)
      if [[ "$status" -ne 0 ]]; then
        echo "$label: expected local unsigned success, got exit $status" >&2
        cat "$out" >&2
        exit 1
      fi
      [[ ! -f "$PKG" ]] || { echo "$label: final public pkg should not exist" >&2; cat "$out" >&2; exit 1; }
      [[ -f "${PKG%.pkg}-local-unsigned.pkg" ]] || { echo "$label: expected local unsigned pkg" >&2; cat "$out" >&2; exit 1; }
      assert_contains "$out" "LOCAL-ONLY UNSIGNED PKG"
      ;;
  esac

  LAST_PKG_CASE_OUT="$out"
}

run_pkg_identity_gate_cases() {
  run_pkg_builder_case zero failure "pkg-identity-zero"
  assert_contains "$LAST_PKG_CASE_OUT" "error: Developer ID Installer identity is required for public PKG output"
  assert_contains "$LAST_PKG_CASE_OUT" "scripts/create-installer-csr.sh"

  run_pkg_builder_case multiple failure "pkg-identity-multiple"
  assert_contains "$LAST_PKG_CASE_OUT" "error: multiple Developer ID Installer identities found"
  assert_contains "$LAST_PKG_CASE_OUT" "set INSTALLER_SIGN_ID"

  run_pkg_builder_case application-only failure "pkg-identity-application-only"
  assert_contains "$LAST_PKG_CASE_OUT" "Developer ID Installer"

  run_pkg_builder_case zero local-unsigned "pkg-identity-local-unsigned"
  assert_contains "$LAST_PKG_CASE_OUT" "not publishable"

  run_pkg_builder_case one success "pkg-identity-one"
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

run_dmg_checksum_artifact_check() {
  local out="$TMP/dmg-checksum.out"
  rm -f "$DMG.sha256"

  reset_log
  env \
    PATH="$FAKE_BIN:$PATH" \
    APM44_FAKE_XCRUN_LOG="$LOG" \
    APM44_FAKE_NOTARY_MODE=accepted \
    NOTARY_PROFILE=TEST_PROFILE \
    APM44_DMG_PATH="$DMG" \
    /bin/bash "$ROOT/scripts/notarize-release-dmg.sh" >"$out" 2>&1

  assert_contains "$LOG" "stapler validate"
  assert_contains "$out" "Checksum ready: $DMG.sha256"
  if [[ ! -f "$DMG.sha256" ]]; then
    echo "expected DMG checksum artifact: $DMG.sha256" >&2
    cat "$out" >&2
    exit 1
  fi
  assert_contains "$DMG.sha256" "$(basename "$DMG")"
  (cd "$(dirname "$DMG")" && shasum -a 256 -c "$(basename "$DMG").sha256" >/dev/null)
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
  local codesign_verify_line
  local notary_dry_run_line
  local driver_staple_line
  local package_only_line
  local dmg_notarize_line

  app_staple_line="$(grep -n "xcrun stapler staple build/Release/APM44 Bridge.app" "$LOG" | head -1 | cut -d: -f1)"
  codesign_verify_line="$(grep -n "bash scripts/codesign-verify-release.sh" "$LOG" | head -1 | cut -d: -f1)"
  notary_dry_run_line="$(grep -n "bash scripts/notary-dry-run.sh" "$LOG" | head -1 | cut -d: -f1)"
  driver_staple_line="$(grep -n "xcrun stapler staple build/Driver/APM44Bridge.driver" "$LOG" | head -1 | cut -d: -f1)"
  package_only_line="$(grep -n "APM44_DMG_PACKAGE_ONLY=1 bash scripts/build-release-dmg.sh" "$LOG" | head -1 | cut -d: -f1)"
  dmg_notarize_line="$(grep -n "bash scripts/notarize-release-dmg.sh" "$LOG" | head -1 | cut -d: -f1)"

  if [[ -z "$app_staple_line" || -z "$codesign_verify_line" || -z "$notary_dry_run_line" || -z "$driver_staple_line" || -z "$package_only_line" || -z "$dmg_notarize_line" ]]; then
    echo "DIST-01: expected staple/package/notarize lines missing from log" >&2
    cat "$LOG" >&2
    exit 1
  fi

  if [[ "$codesign_verify_line" -ge "$notary_dry_run_line" ]]; then
    echo "REL-01: codesign verification must occur before notary dry-run" >&2
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
  assert_contains "$workflow" "maintainer signing/notary evidence"
  assert_contains "$workflow" "does not publish the public DMG"
  assert_not_contains "$workflow" "SKIP: APPLE_SIGN_ID"
  assert_not_contains "$workflow" "SKIP: AC_NOTARY"
  if grep -Eq 'verify-app-build\.sh.*(\|\| *true|continue-on-error:\s*true)' "$workflow"; then
    echo "REL-03: sign-notarize.yml masks verify-app-build.sh failure" >&2
    exit 1
  fi
}

run_release_workflow_does_not_upload_unsigned_installables() {
  local workflow="$ROOT/.github/workflows/release.yml"
  if [[ ! -f "$workflow" ]]; then
    echo "release workflow file not found: $workflow" >&2
    exit 1
  fi

  assert_contains "$workflow" "Release Verification"
  assert_contains "$workflow" "verification-only"
  assert_contains "$workflow" "Do not distribute CI-built app, driver, or daemon bundles."
  assert_contains "$workflow" "bash scripts/release-all.sh"
  assert_not_contains "$workflow" "actions/upload-artifact"
  assert_not_contains "$workflow" "Upload artifacts"
  assert_not_contains "$workflow" "APM44Bridge-unsigned"
  assert_not_contains "$workflow" "build/Release/APM44 Bridge.app"
  assert_not_contains "$workflow" "build/Driver/APM44Bridge.driver"
  assert_not_contains "$workflow" "build/BridgeDaemon/apm44-bridge"
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
  local verify_script="$ROOT/scripts/verify-app-build.sh"
  local menu_script="$ROOT/scripts/verify-menu-bar.sh"
  local embed_script="$ROOT/scripts/embed-daemon-in-app.sh"
  local ci_workflow="$ROOT/.github/workflows/ci.yml"

  assert_contains "$script" 'APP_PATH="$BUILD_DIR/$CONFIG/APM44 Bridge.app"'
  assert_contains "$script" 'APM44_APP_OUTPUT_DIR="$BUILD_DIR/$CONFIG"'
  assert_contains "$script" 'APM44_APP_PATH="$APP_PATH"'
  assert_contains "$script" 'CODE_SIGNING_ALLOWED=YES'
  assert_contains "$script" 'CODE_SIGN_IDENTITY=-'
  assert_not_contains "$script" 'CODE_SIGNING_ALLOWED=NO'

  assert_contains "$verify_script" 'rm -rf "$APP" "$APP.dSYM"'
  assert_contains "$verify_script" 'CODE_SIGNING_ALLOWED=YES'
  assert_contains "$verify_script" 'CODE_SIGN_IDENTITY=-'
  assert_contains "$verify_script" 'codesign --verify --deep --strict "$APP"'
  assert_not_contains "$verify_script" 'CODE_SIGNING_ALLOWED=NO'

  assert_contains "$embed_script" 'APM44_SKIP_LOCAL_APP_RESIGN'
  assert_contains "$embed_script" 'codesign --force --sign - --timestamp=none "$DEST"'
  assert_contains "$embed_script" 'codesign --verify --deep --strict "$APP"'

  assert_contains "$menu_script" 'CODE_SIGNING_ALLOWED=YES'
  assert_contains "$menu_script" 'CODE_SIGN_IDENTITY=-'
  assert_not_contains "$menu_script" 'CODE_SIGNING_ALLOWED=NO'

  assert_contains "$ci_workflow" 'CODE_SIGNING_ALLOWED=YES'
  assert_contains "$ci_workflow" 'CODE_SIGN_IDENTITY=-'
  assert_not_contains "$ci_workflow" 'CODE_SIGNING_ALLOWED=NO'

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
  assert_contains "$release_doc" "does not publish the public DMG"

  assert_contains "$validation_doc" "current 0.11.1 DMG-primary distribution validation path"
  assert_contains "$validation_doc" 'APM44Bridge-${APM44_VERSION:-0.11.1}.dmg'
  assert_not_contains "$validation_doc" "v0.8 release-candidate closeout"

  assert_contains "$install_doc" "APM44Bridge-0.11.1.dmg.sha256"
  assert_contains "$ROOT/scripts/notarize-release-dmg.sh" 'shasum -a 256 "$(basename "$DMG")"'
  assert_contains "$ROOT/scripts/release-all.sh" "*.dmg.sha256"
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

run_pkg_identity_gate_cases

run_dmg_checksum_artifact_check        # [DOC-04]

run_dist_01_staple_before_dmg_order      # [DIST-01]

run_dist_05_dmg_command_installer_check  # [DIST-05]

run_sign_notarize_workflow_check         # [REL-03]

run_release_workflow_does_not_upload_unsigned_installables

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
