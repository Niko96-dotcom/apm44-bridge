#!/usr/bin/env bash
# Credential-free regression tests for release and validation scripts.
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
FAKE_BIN="$TMP/bin"
LOG="$TMP/fake-xcrun.log"

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

# Run the current scripts in a disposable repository layout. Builders may
# replace bundles and staging directories freely without touching local builds.
ROOT="$TMP/repo"
mkdir -p "$FAKE_BIN" "$ROOT/App"
cp -R "$SOURCE_ROOT/scripts" "$SOURCE_ROOT/.github" "$ROOT/"
cp "$SOURCE_ROOT/VERSION" "$ROOT/"
cp "$SOURCE_ROOT/App/project.yml" "$ROOT/App/"

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
    runtime-flag)
      echo "Authority=Developer ID Application: APM44 Test Org (LOCALTEAM)" >&2
      echo "CodeDirectory v=20200 flags=0x10000(runtime)" >&2
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

cat >"$FAKE_BIN/hdiutil" <<'EOF'
#!/bin/bash
set -euo pipefail
log="${APM44_FAKE_XCRUN_LOG:?}"
printf '%s\n' "hdiutil $*" >>"$log"
case "${1:-}" in
  create)
    src=""
    out="${@: -1}"
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        -srcfolder)
          src="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    [[ -n "$src" ]] || { echo "fake hdiutil create requires -srcfolder" >&2; exit 64; }
    mkdir -p "$(dirname "$out")"
    printf 'fake dmg from %s\n' "$src" >"$out"
    ;;
  attach)
    echo "/dev/disk99 Apple_HFS /Volumes/APM44 Bridge"
    ;;
  detach)
    ;;
  *)
    echo "unsupported fake hdiutil command: $*" >&2
    exit 64
    ;;
esac
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
    # Longer than a pipe buffer: an early grep -q match must not turn a valid
    # signature into failure when the caller enables pipefail.
    for ((i = 0; i < 2048; i++)); do
      echo "       Certificate chain detail $i: trusted timestamp and fingerprint"
    done
    ;;
  --payload-files)
    echo "Applications/APM44 Bridge.app"
    echo "Applications/APM44 Bridge.app/Contents/MacOS/APM44Bridge"
    echo "Library/Audio/Plug-Ins/HAL/APM44Bridge.driver"
    echo "Library/Audio/Plug-Ins/HAL/APM44Bridge.driver/Contents/MacOS/APM44Bridge"
    for ((i = 0; i < 2048; i++)); do
      echo "Applications/APM44 Bridge.app/Contents/Resources/payload-$i"
    done
    ;;
  --expand-full)
    dest="$3"
    mkdir -p "$dest/Scripts"
    cat >"$dest/Scripts/preinstall" <<'PRE'
#!/bin/bash
set -e
APP_PATTERN='^/Applications/APM44 Bridge.app/Contents/MacOS/APM44 Bridge([[:space:]]|$)'
if pgrep -f "$APP_PATTERN" >/dev/null 2>&1; then
  echo "Terminating running APM44 Bridge before replacing the app" >&2
  pkill -TERM -f "$APP_PATTERN" 2>/dev/null || true
  pkill -KILL -f "$APP_PATTERN" 2>/dev/null || true
fi
rm -rf "/Applications/APM44 Bridge.app"
rm -rf "/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver"
exit 0
PRE
    cat >"$dest/Scripts/postinstall" <<'POST'
#!/bin/bash
set -e
[[ -d "/Applications/APM44 Bridge.app" ]] || { echo "APM44 Bridge.app missing after install" >&2; exit 1; }
[[ -d "/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver" ]] || { echo "APM44Bridge.driver missing after install" >&2; exit 1; }
echo "Installed app/driver/helper build ID mismatch" >&2
POST
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
  scripts/build-release-dmg.sh|scripts/codesign-verify-release.sh|scripts/notary-dry-run.sh|scripts/notarize-release-dmg.sh|scripts/build-release-pkg.sh|scripts/notarize-release-pkg.sh|scripts/verify-release-pkg.sh|scripts/verify-release-dmg-layout.sh|scripts/verify-version-identity.sh|scripts/verify-release-architectures.sh|scripts/generate-appcast.sh|scripts/validate-appcast.sh|scripts/ensure-sparkle-tools.sh)
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

chmod +x "$FAKE_BIN/xcrun" "$FAKE_BIN/security" "$FAKE_BIN/codesign" "$FAKE_BIN/xcodegen" "$FAKE_BIN/pkgbuild" "$FAKE_BIN/productsign" "$FAKE_BIN/ditto" "$FAKE_BIN/curl" "$FAKE_BIN/hdiutil" "$FAKE_BIN/pkgutil" "$FAKE_BIN/spctl" "$FAKE_BIN/bash" "$FAKE_BIN/ls"

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

run_pkg_replacement_script_check() {
  run_pkg_builder_case one success "pkg-replacement-scripts"

  local preinstall="$ROOT/build/signing/pkg-scripts/preinstall"
  local postinstall="$ROOT/build/signing/pkg-scripts/postinstall"
  [[ -x "$preinstall" ]] || { echo "expected executable preinstall at $preinstall" >&2; exit 1; }
  [[ -x "$postinstall" ]] || { echo "expected executable postinstall at $postinstall" >&2; exit 1; }

  assert_contains "$preinstall" 'rm -rf "/Applications/APM44 Bridge.app"'
  assert_contains "$preinstall" 'rm -rf "/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver"'
  assert_contains "$postinstall" 'chown -R root:wheel /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver'
  assert_contains "$postinstall" 'APM44 Bridge.app missing after install'
  assert_contains "$postinstall" 'APM44Bridge.driver missing after install'
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

run_release_all_pkg_gate_sequence() {
  local out="$TMP/release-all-pkg-gate.out"

  reset_log
  env \
    PATH="$FAKE_BIN:$PATH" \
    APM44_FAKE_XCRUN_LOG="$LOG" \
    APM44_FAKE_NOTARY_HISTORY=ok \
    /bin/bash "$ROOT/scripts/release-all.sh" >"$out" 2>&1

  assert_contains "$LOG" "bash scripts/build-release-pkg.sh"
  assert_contains "$LOG" "bash scripts/notarize-release-pkg.sh"
  assert_contains "$LOG" "bash scripts/verify-release-dmg-layout.sh"
  assert_not_contains "$out" "SKIP pkg"

  local driver_validate_line
  local pkg_build_line
  local pkg_notarize_line
  local package_only_line
  local layout_verify_line
  local dmg_notarize_line
  driver_validate_line="$(grep -n "xcrun stapler validate build/Driver/APM44Bridge.driver" "$LOG" | head -1 | cut -d: -f1)"
  pkg_build_line="$(grep -n "bash scripts/build-release-pkg.sh" "$LOG" | head -1 | cut -d: -f1)"
  pkg_notarize_line="$(grep -n "bash scripts/notarize-release-pkg.sh" "$LOG" | head -1 | cut -d: -f1)"
  package_only_line="$(grep -n "APM44_DMG_PACKAGE_ONLY=1 bash scripts/build-release-dmg.sh" "$LOG" | head -1 | cut -d: -f1)"
  layout_verify_line="$(grep -n "bash scripts/verify-release-dmg-layout.sh" "$LOG" | head -1 | cut -d: -f1)"
  dmg_notarize_line="$(grep -n "bash scripts/notarize-release-dmg.sh" "$LOG" | head -1 | cut -d: -f1)"

  if [[ -z "$driver_validate_line" || -z "$pkg_build_line" || -z "$pkg_notarize_line" || -z "$package_only_line" || -z "$layout_verify_line" || -z "$dmg_notarize_line" ]]; then
    echo "release-all PKG gate: expected lines missing from log" >&2
    cat "$LOG" >&2
    exit 1
  fi

  if [[ "$driver_validate_line" -ge "$pkg_build_line" || "$pkg_build_line" -ge "$pkg_notarize_line" || "$pkg_notarize_line" -ge "$package_only_line" || "$package_only_line" -ge "$layout_verify_line" || "$layout_verify_line" -ge "$dmg_notarize_line" ]]; then
    echo "release-all PKG gate order is wrong" >&2
    cat "$LOG" >&2
    exit 1
  fi
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
  assert_contains "$LOG" "spctl --assess --type open --context context:primary-signature --verbose=4 $DMG"
  assert_contains "$out" "Checksum ready: $DMG.sha256"
  if [[ ! -f "$DMG.sha256" ]]; then
    echo "expected DMG checksum artifact: $DMG.sha256" >&2
    cat "$out" >&2
    exit 1
  fi
  assert_contains "$DMG.sha256" "$(basename "$DMG")"
  (cd "$(dirname "$DMG")" && shasum -a 256 -c "$(basename "$DMG").sha256" >/dev/null)
}

run_dmg_pkg_first_layout_check() {
  local out="$TMP/dmg-pkg-first.out"
  local staging="$TMP/dmg-staging"
  local dmg="$TMP/APM44Bridge-pkg-first.dmg"
  local pkg="$TMP/APM44Bridge-0.12.1.pkg"
  printf 'signed pkg\n' >"$pkg"
  rm -rf "$staging" "$dmg"

  reset_log
  env \
    PATH="$FAKE_BIN:$PATH" \
    APM44_FAKE_XCRUN_LOG="$LOG" \
    APM44_DMG_PACKAGE_ONLY=1 \
    APM44_DMG_STAGING="$staging" \
    APM44_DMG_PATH="$dmg" \
    APM44_PKG_PATH="$pkg" \
    /bin/bash "$ROOT/scripts/build-release-dmg.sh" >"$out" 2>&1

  [[ -f "$staging/$(basename "$pkg")" ]] || { echo "expected pkg in DMG staging" >&2; cat "$out" >&2; exit 1; }
  [[ -f "$staging/README.txt" ]] || { echo "expected README in DMG staging" >&2; cat "$out" >&2; exit 1; }
  [[ ! -e "$staging/APM44 Bridge.app" ]] || { echo "raw app must not be in final DMG staging" >&2; exit 1; }
  [[ ! -e "$staging/APM44Bridge.driver" ]] || { echo "raw driver must not be in final DMG staging" >&2; exit 1; }
  [[ ! -e "$staging/Install APM44 Bridge.command" ]] || { echo "command installer must not be in final DMG staging" >&2; exit 1; }
  assert_contains "$LOG" "hdiutil create"
}

run_verify_release_dmg_layout_check() {
  local good="$TMP/dmg-layout-good"
  local bad="$TMP/dmg-layout-bad"
  local out="$TMP/dmg-layout.out"
  rm -rf "$good" "$bad"
  mkdir -p "$good" "$bad"
  printf 'pkg\n' >"$good/APM44Bridge-0.12.1.pkg"
  printf 'readme\n' >"$good/README.txt"
  mkdir -p "$bad/APM44 Bridge.app" "$bad/APM44Bridge.driver"
  printf 'pkg\n' >"$bad/APM44Bridge-0.12.1.pkg"
  printf 'readme\n' >"$bad/README.txt"
  printf 'cmd\n' >"$bad/Install APM44 Bridge.command"

  env APM44_DMG_STAGING="$good" APM44_VERIFY_DMG_STAGING=1 /bin/bash "$ROOT/scripts/verify-release-dmg-layout.sh" >"$out" 2>&1
  assert_contains "$out" "verify-release-dmg-layout: OK"

  if env APM44_DMG_STAGING="$bad" APM44_VERIFY_DMG_STAGING=1 /bin/bash "$ROOT/scripts/verify-release-dmg-layout.sh" >"$out" 2>&1; then
    echo "old raw DMG layout should fail verification" >&2
    cat "$out" >&2
    exit 1
  fi
  assert_contains "$out" "raw app bundle must not be exposed"
}

run_final_install_artifact_verifier_check() {
  local mount="$TMP/final-mounted-dmg"
  local out="$TMP/final-install-artifact.out"
  rm -rf "$mount"
  mkdir -p "$mount"
  printf 'mounted pkg\n' >"$mount/APM44Bridge-0.12.1.pkg"

  reset_log
  env \
    PATH="$FAKE_BIN:$PATH" \
    APM44_FAKE_XCRUN_LOG="$LOG" \
    APM44_MOUNTED_DMG_PATH="$mount" \
    /bin/bash "$ROOT/scripts/verify-final-install-artifact.sh" >"$out" 2>&1

  assert_contains "$out" "Final install source: $mount/APM44Bridge-0.12.1.pkg"
  assert_contains "$out" "Install smoke skipped"
  assert_contains "$out" "verify-final-install-artifact: OK"
  assert_contains "$LOG" "pkgutil --check-signature $mount/APM44Bridge-0.12.1.pkg"
  assert_contains "$LOG" "stapler validate $mount/APM44Bridge-0.12.1.pkg"
  assert_contains "$LOG" "spctl --assess --type install --verbose=4 $mount/APM44Bridge-0.12.1.pkg"

  rm -f "$mount/APM44Bridge-0.12.1.pkg"
  if env \
    PATH="$FAKE_BIN:$PATH" \
    APM44_FAKE_XCRUN_LOG="$LOG" \
    APM44_MOUNTED_DMG_PATH="$mount" \
    /bin/bash "$ROOT/scripts/verify-final-install-artifact.sh" >"$out" 2>&1; then
    echo "final install verifier should fail without mounted pkg" >&2
    cat "$out" >&2
    exit 1
  fi
  assert_contains "$out" "expected exactly one top-level pkg"
}

run_uninstall_script_check() {
  local out="$TMP/uninstall-dry-run.out"
  /bin/bash "$ROOT/scripts/uninstall-apm44.sh" --dry-run >"$out" 2>&1
  assert_contains "$out" "dry-run: would remove /Applications/APM44 Bridge.app"
  assert_contains "$out" "dry-run: would remove /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver"
  assert_contains "$out" "dry-run: would forget package receipt com.niko.apm44.pkg"
}

run_pkg_validation_order_check() {
  local out="$TMP/pkg-validation-order.out"
  rm -f "$PKG.sha256"

  reset_log
  env \
    PATH="$FAKE_BIN:$PATH" \
    APM44_FAKE_XCRUN_LOG="$LOG" \
    APM44_FAKE_NOTARY_MODE=accepted \
    NOTARY_PROFILE=TEST_PROFILE \
    APM44_PKG_PATH="$PKG" \
    /bin/bash "$ROOT/scripts/notarize-release-pkg.sh" >"$out" 2>&1

  assert_contains "$LOG" "notarytool submit"
  assert_contains "$LOG" "stapler staple"
  assert_contains "$LOG" "stapler validate"
  assert_contains "$LOG" "pkgutil --check-signature $PKG"
  assert_contains "$LOG" "spctl --assess --type install --verbose=4 $PKG"
  assert_contains "$out" "Checksum ready: $PKG.sha256"
  [[ -f "$PKG.sha256" ]] || { echo "expected package checksum artifact: $PKG.sha256" >&2; cat "$out" >&2; exit 1; }
  (cd "$(dirname "$PKG")" && shasum -a 256 -c "$(basename "$PKG").sha256" >/dev/null)

  local submit_line
  local staple_line
  local validate_line
  local final_pkgutil_line
  local spctl_line
  submit_line="$(grep -n "notarytool submit" "$LOG" | head -1 | cut -d: -f1)"
  staple_line="$(grep -n "stapler staple" "$LOG" | head -1 | cut -d: -f1)"
  validate_line="$(grep -n "stapler validate" "$LOG" | head -1 | cut -d: -f1)"
  final_pkgutil_line="$(grep -n "pkgutil --check-signature $PKG" "$LOG" | tail -1 | cut -d: -f1)"
  spctl_line="$(grep -n "spctl --assess --type install" "$LOG" | head -1 | cut -d: -f1)"

  if [[ -z "$submit_line" || -z "$staple_line" || -z "$validate_line" || -z "$final_pkgutil_line" || -z "$spctl_line" ]]; then
    echo "PKG validation order: expected lines missing from log" >&2
    cat "$LOG" >&2
    exit 1
  fi
  if [[ "$submit_line" -ge "$staple_line" || "$staple_line" -ge "$validate_line" || "$validate_line" -ge "$final_pkgutil_line" || "$final_pkgutil_line" -ge "$spctl_line" ]]; then
    echo "PKG validation order is wrong" >&2
    cat "$LOG" >&2
    exit 1
  fi

  rm -f "$PKG.sha256"
  reset_log
  if env \
    PATH="$FAKE_BIN:$PATH" \
    APM44_FAKE_XCRUN_LOG="$LOG" \
    APM44_FAKE_NOTARY_MODE=rejected \
    NOTARY_PROFILE=TEST_PROFILE \
    APM44_PKG_PATH="$PKG" \
    /bin/bash "$ROOT/scripts/notarize-release-pkg.sh" >"$out" 2>&1; then
    echo "PKG validation order: rejected notarization should fail" >&2
    cat "$out" >&2
    exit 1
  fi
  [[ ! -f "$PKG.sha256" ]] || { echo "rejected package notarization must not create checksum" >&2; cat "$out" >&2; exit 1; }
}

prepare_verify_pkg_inputs() {
  VERIFY_APP="$TMP/verify-inputs/APM44 Bridge.app"
  VERIFY_DRIVER_EXE="$TMP/verify-inputs/APM44Bridge.driver/Contents/MacOS/APM44Bridge"
  VERIFY_BRIDGE="$TMP/verify-inputs/apm44-bridge"
  mkdir -p "$VERIFY_APP/Contents/MacOS"
  mkdir -p "$(dirname "$VERIFY_DRIVER_EXE")"
  printf 'verify app\n' >"$VERIFY_APP/Contents/MacOS/APM44Bridge"
  printf 'verify driver\n' >"$VERIFY_DRIVER_EXE"
  cat >"$VERIFY_BRIDGE" <<'BRIDGE'
#!/bin/bash
set -euo pipefail
case "${1:-}" in
  --version)
    echo "APM44 Bridge 0.12.1 build=FAKEPKG123"
    ;;
  --shm-status)
    echo "helper_build_id=FAKEPKG123"
    ;;
  *)
    echo "fake bridge"
    ;;
esac
BRIDGE
  chmod +x "$VERIFY_BRIDGE"
}

run_verify_release_pkg_check() {
  local out="$TMP/verify-release-pkg.out"
  rm -f "$PKG.sha256" "$PKG.provenance.txt"
  printf 'verify pkg\n' >"$PKG"
  (cd "$(dirname "$PKG")" && shasum -a 256 "$(basename "$PKG")" >"$(basename "$PKG").sha256")
  prepare_verify_pkg_inputs

  reset_log
  env \
    PATH="$FAKE_BIN:$PATH" \
    APM44_FAKE_XCRUN_LOG="$LOG" \
    APM44_PKG_PATH="$PKG" \
    APM44_APP_PATH="$VERIFY_APP" \
    APM44_DRIVER_EXECUTABLE="$VERIFY_DRIVER_EXE" \
    APM44_BRIDGE_BIN="$VERIFY_BRIDGE" \
    /bin/bash "$ROOT/scripts/verify-release-pkg.sh" >"$out" 2>&1

  assert_contains "$LOG" "pkgutil --payload-files $PKG"
  assert_contains "$LOG" "pkgutil --expand-full $PKG"
  assert_contains "$out" "verify-release-pkg: OK"
  [[ -f "$PKG.provenance.txt" ]] || { echo "expected pkg.provenance.txt" >&2; cat "$out" >&2; exit 1; }
  assert_contains "$PKG.provenance.txt" "pkg_sha256="
  assert_contains "$PKG.provenance.txt" "helper_build_id=FAKEPKG123"
  assert_contains "$PKG.provenance.txt" "app_bundle_sha256="
  assert_contains "$PKG.provenance.txt" "driver_executable_sha256="
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

run_workflow_action_trust_check() {
  local workflow
  for workflow in "$ROOT/.github/workflows/release.yml" "$ROOT/.github/workflows/sign-notarize.yml" "$ROOT/.github/workflows/ci.yml"; do
    local line
    while IFS= read -r line; do
      if [[ "$line" =~ uses:[[:space:]]*([^[:space:]]+) ]]; then
        local action="${BASH_REMATCH[1]}"
        if [[ "$action" != actions/* ]]; then
          echo "non-official action '$action' in $workflow requires review" >&2
          exit 1
        fi
      fi
    done < "$workflow"
  done
}

run_release_workflow_does_not_upload_unsigned_installables() {
  assert_not_contains "$ROOT/.github/workflows/release.yml" "actions/upload-artifact"
}

run_public_release_hygiene_check() {
  local repo="$TMP/hygiene-repo"
  local out="$TMP/hygiene.out"
  mkdir -p "$repo"
  git -C "$repo" init -q
  (cd "$repo" && PATH=/usr/bin:/bin /bin/bash "$ROOT/scripts/check-public-release-hygiene.sh") >"$out" 2>&1

  mkdir -p "$repo/.planning"
  printf 'private planning fixture\n' >"$repo/.planning/private.md"
  git -C "$repo" add .planning/private.md
  if (cd "$repo" && PATH=/usr/bin:/bin /bin/bash "$ROOT/scripts/check-public-release-hygiene.sh") >"$out" 2>&1; then
    echo "tracked planning files should fail the public release hygiene check" >&2
    exit 1
  fi
  assert_contains "$out" ".planning/private.md"
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

run_export_rate_cases() {
  cat >"$FAKE_BIN/afinfo" <<'EOF'
#!/bin/bash
printf '%s\n' "$APM44_FAKE_AFINFO"
exit "${APM44_FAKE_AFINFO_STATUS:-0}"
EOF
  chmod +x "$FAKE_BIN/afinfo"
  local fixture="$TMP/export.wav" out="$TMP/export-result.json" status expected info
  touch "$fixture"
  while IFS='|' read -r expected info; do
    status=0
    env PATH="$FAKE_BIN:$PATH" APM44_FAKE_AFINFO="$info" \
      bash "$ROOT/scripts/validate-export-rate.sh" --check-file "$fixture" --json >"$out" 2>/dev/null || status=$?
    if [[ "$status" -ne "$expected" ]]; then
      echo "export rate: expected exit $expected, got $status for $info" >&2
      exit 1
    fi
    if [[ "$expected" -eq 0 ]]; then
      assert_contains "$out" '"pass":true'
      assert_contains "$out" '"sample_rate_hz":44100'
    fi
  done <<'EOF'
0|Data format:     2 ch,  44100 Hz, lpcm (0x0000000C) 24-bit little-endian signed integer
0|Data format: 1 ch, 44100.000000 Hz, lpcm
0|sample rate: 44100.0 Hz
0|Sample Rate: 44100
1|Data format: 2 ch, 48000 Hz, lpcm
1|Data format: 2 ch, 44100.9 Hz, lpcm
1|sample rate: 44100.9 Hz
1|Data format: 2 ch, unknown Hz, lpcm
1|audio 44100 bytes
EOF
  if env PATH="$FAKE_BIN:$PATH" APM44_FAKE_AFINFO='sample rate: 44100' APM44_FAKE_AFINFO_STATUS=1 \
    bash "$ROOT/scripts/validate-export-rate.sh" --check-file "$fixture" >"$out" 2>&1; then
    echo "export rate: accepted failed afinfo inspection" >&2
    exit 1
  fi
}

run_export_rate_cases

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

run_release_all_pkg_gate_sequence

run_pkg_identity_gate_cases

run_pkg_replacement_script_check

run_dmg_checksum_artifact_check        # [DOC-04]

run_dmg_pkg_first_layout_check

run_verify_release_dmg_layout_check

run_final_install_artifact_verifier_check

run_uninstall_script_check

run_pkg_validation_order_check

run_verify_release_pkg_check

run_dist_01_staple_before_dmg_order      # [DIST-01]

run_release_workflow_does_not_upload_unsigned_installables

run_workflow_action_trust_check

run_public_release_hygiene_check

run_codesign_verify_case strict-ok 0 success "codesign-strict-ok"
run_codesign_verify_case runtime-flag 0 success "codesign-runtime-flag"  # [REL-01]
run_codesign_verify_case no-runtime 0 failure "codesign-no-runtime"        # [REL-01]
run_codesign_verify_case no-developer-id 0 failure "codesign-no-dev-id"    # [REL-02]
run_codesign_verify_case ad-hoc 1 success "codesign-local-override"        # [REL-01][REL-02]

echo "release script tests: OK"
