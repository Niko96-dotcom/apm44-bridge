# Phase 46: PKG Installer Promotion - Pattern Map

**Mapped:** 2026-07-01
**Files analyzed:** 15
**Analogs found:** 15 / 15

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `scripts/build-release-pkg.sh` | utility | file-I/O + request-response | `scripts/build-release-pkg.sh` | exact |
| `scripts/notarize-release-pkg.sh` | utility | request-response + file-I/O | `scripts/notarize-release-dmg.sh`, `scripts/notary-result.sh` | exact |
| `scripts/release-all.sh` | utility | batch orchestration | `scripts/release-all.sh` | exact |
| `tests/test_release_scripts.sh` | test | batch + fake external I/O | `tests/test_release_scripts.sh` | exact |
| `scripts/notarize-release-dmg.sh` | utility | request-response + file-I/O | `scripts/notarize-release-dmg.sh` | exact |
| `scripts/notary-result.sh` | utility | transform + request-response | `scripts/notary-result.sh` | exact |
| `scripts/build-release-dmg.sh` | utility | file-I/O + batch | `scripts/build-release-dmg.sh` | exact |
| `scripts/codesign-verify-release.sh` | utility | batch validation | `scripts/codesign-verify-release.sh` | exact |
| `scripts/create-installer-csr.sh` | utility | file-I/O | `scripts/create-installer-csr.sh` | role-match |
| `scripts/install-installer-cert.sh` | utility | file-I/O + request-response | `scripts/install-installer-cert.sh` | role-match |
| `scripts/verify-installed-sync.sh` | utility | request-response + transform | `scripts/verify-installed-sync.sh` | role-match |
| `scripts/verify-hal-driver.sh` | utility | request-response + file-I/O | `scripts/verify-hal-driver.sh` | role-match |
| `scripts/verify-release-pkg.sh` | utility | request-response + transform | `scripts/verify-installed-sync.sh`, `scripts/verify-hal-driver.sh`, `scripts/codesign-verify-release.sh` | role-match |
| `docs/release.md` | config/docs | batch instructions | `docs/release.md` | exact |
| `docs/release-validation.md` | config/docs | batch validation | `docs/release-validation.md` | exact |

## Pattern Assignments

### `scripts/build-release-pkg.sh` (utility, file-I/O + request-response)

**Analog:** `scripts/build-release-pkg.sh`

**Shell/import pattern** (lines 1-13):
```bash
#!/usr/bin/env bash
# Build signed pkg installing HAL driver + menu bar app (POL-01).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${APM44_BUILD_CONFIG:-Release}"
VERSION="${APM44_VERSION:-0.11.1}"
PKG="${APM44_PKG_PATH:-$ROOT/build/signing/APM44Bridge-${VERSION}.pkg}"
UNSIGNED_PKG="${PKG%.pkg}-unsigned.pkg"
PAYLOAD="$ROOT/build/signing/pkg-root"
INSTALLER_ID="${INSTALLER_SIGN_ID:-}"
```

**Installer identity pattern to harden** (lines 29-42):
```bash
resolve_installer_id() {
  if [[ -n "$INSTALLER_ID" ]]; then
    printf '%s\n' "$INSTALLER_ID"
    return
  fi

  local identities
  identities="$(security find-identity -v -p basic 2>/dev/null | sed -n 's/.*"\(Developer ID Installer: .*\)".*/\1/p' || true)"
  local count
  count="$(printf '%s\n' "$identities" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$count" == "1" ]]; then
    printf '%s\n' "$identities"
  fi
}
```

**Payload staging pattern** (lines 44-61):
```bash
APP="$ROOT/build/$CONFIG/APM44 Bridge.app"
DRIVER="${APM44_DRIVER_PATH:-$ROOT/build/Driver/APM44Bridge.driver}"

for artifact in "$APP" "$DRIVER"; do
  if [[ ! -e "$artifact" ]]; then
    echo "error: missing $artifact - run scripts/build-release-dmg.sh first" >&2
    exit 1
  fi
done

SCRIPTS="$ROOT/build/signing/pkg-scripts"
rm -rf "$PAYLOAD" "$SCRIPTS"
mkdir -p "$PAYLOAD/Applications"
mkdir -p "$PAYLOAD/Library/Audio/Plug-Ins/HAL"
mkdir -p "$SCRIPTS"

ditto "$APP" "$PAYLOAD/Applications/APM44 Bridge.app"
ditto "$DRIVER" "$PAYLOAD/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver"
```

**Postinstall pattern to extend for replacement semantics** (lines 63-80):
```bash
cat > "$SCRIPTS/postinstall" <<'POST'
#!/bin/bash
set -e
chown -R root:wheel /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver
xattr -cr /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver 2>/dev/null || true
DRIVER_BIN="$(find /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver/Contents/MacOS -maxdepth 1 -type f | head -1)"
if [[ -z "$DRIVER_BIN" ]]; then
  echo "APM44Bridge.driver executable missing after install" >&2
  exit 1
fi
killall coreaudiod 2>/dev/null || true
```

**Signing boundary that must become fail-closed** (lines 82-98):
```bash
pkgbuild --root "$PAYLOAD" --scripts "$SCRIPTS" \
  --identifier com.niko.apm44.pkg --version "$VERSION" \
  "$UNSIGNED_PKG"

INSTALLER_ID="$(resolve_installer_id)"
if [[ -n "$INSTALLER_ID" ]] && security find-identity -v -p basic 2>/dev/null | grep -qF "$INSTALLER_ID"; then
  productsign --sign "$INSTALLER_ID" "$UNSIGNED_PKG" "$PKG"
  rm -f "$UNSIGNED_PKG"
  echo "Signed pkg: $PKG"
else
  mv "$UNSIGNED_PKG" "$PKG"
  echo "WARN: no Developer ID Installer identity - set INSTALLER_SIGN_ID or run scripts/install-installer-cert.sh first"
fi
```

Planner note: replace the warning/move branch with a public-mode error before final `$PKG` is created. Keep any unsigned output behind an explicit local-only override and label it non-publishable.

---

### `scripts/verify-release-pkg.sh` (utility, request-response + transform)

**Analogs:** `scripts/verify-installed-sync.sh`, `scripts/verify-hal-driver.sh`, `scripts/codesign-verify-release.sh`

**Strict shell entrypoint pattern:**
```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${APM44_VERSION:-0.11.1}"
PKG="${APM44_PKG_PATH:-$ROOT/build/signing/APM44Bridge-${VERSION}.pkg}"
```

**Verifier behavior pattern:**
Use the existing verification scripts' style: print named pass/fail checks,
fail nonzero for missing artifacts or public-release gate failures, and keep
destructive installed-system checks behind an explicit opt-in. The new verifier
should default to non-destructive package checks (`pkgutil --check-signature`,
`xcrun stapler validate`, `spctl --assess --type install`, payload path checks,
and checksum validation), then run `installer`, `verify-installed-sync.sh`,
`verify-hal-driver.sh`, and `apm44-bridge --shm-status` only when
`APM44_RUN_PKG_INSTALL_SMOKE=1` is set.

Planner note: this file is new in Plan 46-04; follow existing script style from
`verify-installed-sync.sh` and `verify-hal-driver.sh` rather than inventing a
new reporting framework.

---

### `scripts/notarize-release-pkg.sh` (utility, request-response + file-I/O)

**Analogs:** `scripts/notarize-release-pkg.sh`, `scripts/notarize-release-dmg.sh`, `scripts/notary-result.sh`

**Shared helper import pattern** (lines 5-11):
```bash
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${APM44_VERSION:-0.11.1}"
PKG="${APM44_PKG_PATH:-$ROOT/build/signing/APM44Bridge-${VERSION}.pkg}"
PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"

# shellcheck source=scripts/notary-result.sh
source "$ROOT/scripts/notary-result.sh"
```

**Existing pkg preflight/error pattern** (lines 13-31):
```bash
if [[ ! -f "$PKG" ]]; then
  echo "error: pkg not found at $PKG - run scripts/build-release-pkg.sh first" >&2
  exit 1
fi

if [[ -z "$INSTALLER_ID" ]] || ! security find-identity -v | grep -qF "$INSTALLER_ID"; then
  echo "error: pkg is unsigned - create a Developer ID Installer cert in Apple Developer," >&2
  echo "  then set INSTALLER_SIGN_ID and run scripts/build-release-pkg.sh before notarizing." >&2
  echo "  Or ship the notarized DMG: bash scripts/notarize-release-dmg.sh" >&2
  exit 1
fi
```

**Notary/stapler pattern** (lines 34-39):
```bash
require_notary_accepted "$PKG" "$PROFILE" "pkg"

echo "Stapling pkg..."
xcrun stapler staple "$PKG"
xcrun stapler validate "$PKG"
echo "Notarized pkg ready: $PKG"
```

**Checksum pattern to copy from DMG** (`scripts/notarize-release-dmg.sh` lines 20-29):
```bash
echo "Stapling DMG..."
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "Writing DMG checksum..."
(
  cd "$(dirname "$DMG")"
  shasum -a 256 "$(basename "$DMG")" >"$(basename "$DMG").sha256"
)
echo "Checksum ready: $DMG.sha256"
```

Planner note: add `pkgutil --check-signature "$PKG"` and `spctl --assess --type install --verbose=4 "$PKG"` after stapler validation and before checksum generation.

---

### `scripts/release-all.sh` (utility, batch orchestration)

**Analog:** `scripts/release-all.sh`

**Release readiness gate** (lines 12-27):
```bash
if xcrun notarytool history --keychain-profile "$PROFILE" &>/dev/null; then
  NOTARY_READY=1
fi

if [[ "$NOTARY_READY" != "1" && "${APM44_ALLOW_UNNOTARIZED:-0}" != "1" ]]; then
  echo "error: notary profile \"$PROFILE\" is not configured or not usable." >&2
  echo "Public release artifacts must be notarized." >&2
  echo "Configure credentials with scripts/setup-notary-profile.sh, or rerun with" >&2
  echo "APM44_ALLOW_UNNOTARIZED=1 for local-only unnotarized artifacts." >&2
  exit 1
fi
```

**Normal notarized release order** (lines 34-53):
```bash
if [[ "$NOTARY_READY" == "1" ]]; then
  echo "== Verify release codesigning =="
  bash scripts/codesign-verify-release.sh

  echo "== Notarize release zip (app + driver evidence) =="
  bash scripts/notary-dry-run.sh

  echo "== Staple app and driver =="
  xcrun stapler staple "build/Release/APM44 Bridge.app"
  xcrun stapler validate "build/Release/APM44 Bridge.app"
  xcrun stapler staple build/Driver/APM44Bridge.driver
  xcrun stapler validate build/Driver/APM44Bridge.driver

  echo "== Package final DMG from stapled artifacts =="
  APM44_DMG_PACKAGE_ONLY=1 bash scripts/build-release-dmg.sh

  echo "== Notarize DMG (primary distribution) =="
  bash scripts/notarize-release-dmg.sh
```

**Optional PKG branch to promote** (lines 55-62):
```bash
if [[ "${APM44_BUILD_PKG:-0}" == "1" ]]; then
  echo "== Build pkg from stapled artifacts =="
  bash scripts/build-release-pkg.sh
  echo "== Notarize pkg =="
  bash scripts/notarize-release-pkg.sh
else
  echo "SKIP pkg: DMG is the public release artifact. Set APM44_BUILD_PKG=1 to build/notarize a PKG."
fi
```

Planner note: move the package build/notarize gate into the normal notary-ready path. Leave unnotarized/local override behavior explicit and non-public.

---

### `tests/test_release_scripts.sh` (test, batch + fake external I/O)

**Analog:** `tests/test_release_scripts.sh`

**Harness setup pattern** (lines 1-16):
```bash
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
```

**Fake `xcrun` pattern** (lines 17-79):
```bash
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
```

**Fake `security` installer identity pattern to extend** (lines 81-92):
```bash
cat >"$FAKE_BIN/security" <<'EOF'
#!/bin/bash
set -euo pipefail

if [[ "${1:-}" == "find-identity" ]]; then
  echo '  1) FAKECERT "Developer ID Installer: APM44 Test Org (LOCALTEAM)"'
  exit 0
fi
```

**Assertion helpers** (lines 174-198):
```bash
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
```

**Parameterized notary case pattern** (lines 200-244):
```bash
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
```

**Release order assertion pattern** (lines 345-383):
```bash
app_staple_line="$(grep -n "xcrun stapler staple build/Release/APM44 Bridge.app" "$LOG" | head -1 | cut -d: -f1)"
codesign_verify_line="$(grep -n "bash scripts/codesign-verify-release.sh" "$LOG" | head -1 | cut -d: -f1)"
notary_dry_run_line="$(grep -n "bash scripts/notary-dry-run.sh" "$LOG" | head -1 | cut -d: -f1)"
driver_staple_line="$(grep -n "xcrun stapler staple build/Driver/APM44Bridge.driver" "$LOG" | head -1 | cut -d: -f1)"
package_only_line="$(grep -n "APM44_DMG_PACKAGE_ONLY=1 bash scripts/build-release-dmg.sh" "$LOG" | head -1 | cut -d: -f1)"
dmg_notarize_line="$(grep -n "bash scripts/notarize-release-dmg.sh" "$LOG" | head -1 | cut -d: -f1)"

if [[ "$app_staple_line" -ge "$package_only_line" ]]; then
  echo "DIST-01: app staple must occur before package-only DMG build" >&2
  exit 1
fi
```

Planner note: add fake `productsign`, `pkgbuild`, `pkgutil`, `spctl`, and richer fake `security` modes for zero/one/multiple/explicit installer identities. Follow the existing `run_*` function plus final invocation pattern at lines 610-656.

---

### `scripts/notarize-release-dmg.sh` (utility, request-response + file-I/O)

**Analog:** `scripts/notarize-release-dmg.sh`

**Apply to:** Keep as stable analog for package checksum order; modify only if the package promotion needs a shared checksum helper.

**Core pattern** (lines 10-29):
```bash
# shellcheck source=scripts/notary-result.sh
source "$ROOT/scripts/notary-result.sh"

if [[ ! -f "$DMG" ]]; then
  echo "error: DMG not found at $DMG - run scripts/build-release-dmg.sh first" >&2
  exit 1
fi

require_notary_accepted "$DMG" "$PROFILE" "DMG"

echo "Stapling DMG..."
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "Writing DMG checksum..."
(
  cd "$(dirname "$DMG")"
  shasum -a 256 "$(basename "$DMG")" >"$(basename "$DMG").sha256"
)
```

---

### `scripts/notary-result.sh` (utility, transform + request-response)

**Analog:** `scripts/notary-result.sh`

**Submission ID parser** (lines 4-10):
```bash
extract_notary_submission_id() {
  sed -nE '/^[[:space:]]*id:[[:space:]]*/ {
    s/^[[:space:]]*id:[[:space:]]*([^[:space:]]+).*/\1/
    p
    q
  }'
}
```

**Fail-closed notary helper** (lines 32-59):
```bash
require_notary_accepted() {
  local artifact="$1"
  local profile="$2"
  local label="${3:-artifact}"
  local output=""
  local submit_status=0

  echo "Submitting $label to notary (profile: $profile)..."
  if output="$(xcrun notarytool submit "$artifact" --keychain-profile "$profile" --wait 2>&1)"; then
    submit_status=0
  else
    submit_status=$?
  fi

  printf '%s\n' "$output"

  if [[ "$submit_status" -ne 0 ]]; then
    echo "error: notarization submit failed for $label (exit $submit_status)" >&2
    fetch_notary_log_if_available "$output" "$profile"
    return "$submit_status"
  fi

  if ! grep -Eq '^[[:space:]]*status:[[:space:]]*Accepted[[:space:]]*$' <<<"$output"; then
    echo "error: notarization did not report status: Accepted for $label" >&2
    fetch_notary_log_if_available "$output" "$profile"
    return 1
  fi
}
```

Planner note: do not duplicate notary parsing in package scripts; call this helper for PKG just as DMG and HAL scripts do.

---

### `scripts/build-release-dmg.sh` (utility, file-I/O + batch)

**Analog:** `scripts/build-release-dmg.sh`

**Package-only reuse pattern** (lines 10-23, 43-60):
```bash
PACKAGE_ONLY="${APM44_DMG_PACKAGE_ONLY:-0}"

if [[ "$PACKAGE_ONLY" != "1" ]]; then
  echo "Building Release..."
  cmake -S "$ROOT" -B "$ROOT/build" -DCMAKE_BUILD_TYPE=Release
  cmake --build "$ROOT/build" --target apm44-bridge APM44Bridge
  ...
else
  echo "Packaging existing app and driver into DMG..."
fi
```

**Staged artifact copy pattern** (lines 62-75):
```bash
APP="$ROOT/build/$CONFIG/APM44 Bridge.app"
DRIVER="${APM44_DRIVER_PATH:-$ROOT/build/Driver/APM44Bridge.driver}"

for artifact in "$APP" "$DRIVER"; do
  if [[ ! -e "$artifact" ]]; then
    echo "error: missing $artifact - run scripts/build-release-dmg.sh before package-only mode" >&2
    exit 1
  fi
done

rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/APM44 Bridge.app"
ditto "$DRIVER" "$STAGING/APM44Bridge.driver"
```

**Upgrade replacement command pattern** (lines 80-97):
```bash
sudo rm -rf /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver
sudo ditto "$DIR/APM44Bridge.driver" /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver
sudo chown -R root:wheel /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver
sudo xattr -cr /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver 2>/dev/null || true
...
sudo rm -rf "/Applications/APM44 Bridge.app"
sudo ditto "$DIR/APM44 Bridge.app" "/Applications/APM44 Bridge.app"
sudo chown -R root:wheel "/Applications/APM44 Bridge.app"
open "/Applications/APM44 Bridge.app"
```

Planner note: copy this replacement intent into PKG preinstall/postinstall scripts where Installer package semantics need explicit stale-state removal.

---

### `scripts/codesign-verify-release.sh` (utility, batch validation)

**Analog:** `scripts/codesign-verify-release.sh`

**Reusable validation accumulator** (lines 7-23):
```bash
FAIL=0
ALLOW_LOCAL_CODESIGN="${APM44_ALLOW_LOCAL_CODESIGN:-0}"

check() {
  local label="$1"
  local path="$2"
  local deep="${3:-0}"

  if [[ ! -e "$path" ]]; then
    echo "FAIL: $label missing at $path"
    FAIL=1
    return
  fi
```

**Fail/warn public-mode pattern** (lines 41-58):
```bash
local info
info="$(codesign -dv --verbose=2 "$path" 2>&1 || true)"
if grep -q 'Runtime Version' <<<"$info"; then
  echo "OK: $label hardened runtime"
elif [[ "$ALLOW_LOCAL_CODESIGN" == "1" ]]; then
  echo "WARN: $label - hardened runtime flag not detected (APM44_ALLOW_LOCAL_CODESIGN=1)"
else
  echo "FAIL: $label - hardened runtime flag not detected"
  FAIL=1
fi
if grep -qi 'Developer ID Application' <<<"$info"; then
  echo "OK: $label Developer ID Application"
elif [[ "$ALLOW_LOCAL_CODESIGN" == "1" ]]; then
  echo "WARN: $label - not Developer ID (APM44_ALLOW_LOCAL_CODESIGN=1)"
else
  echo "FAIL: $label - not Developer ID Application"
  FAIL=1
fi
```

**Exit pattern** (lines 68-74):
```bash
if [[ "$FAIL" -eq 0 ]]; then
  echo "codesign-verify-release: passed"
else
  echo "codesign-verify-release: failed"
fi
exit "$FAIL"
```

Planner note: use the same `FAIL` accumulator style if adding a dedicated package signature verifier.

---

### `scripts/create-installer-csr.sh` (utility, file-I/O)

**Analog:** `scripts/create-installer-csr.sh`

**Operator setup error pattern** (lines 11-19):
```bash
mkdir -p "$DIR"
if [[ -z "$EMAIL" ]]; then
  echo "error: set APM44_CSR_EMAIL or git config user.email" >&2
  exit 1
fi
if [[ -z "$CN" ]]; then
  echo "error: set APM44_CSR_CN or git config user.name" >&2
  exit 1
fi
```

**CSR creation pattern** (lines 21-35):
```bash
openssl genrsa -out "$DIR/installer.key" 2048
SUBJECT="/emailAddress=${EMAIL}/CN=${CN}"
if [[ -n "$COUNTRY" ]]; then
  SUBJECT="${SUBJECT}/C=${COUNTRY}"
fi
openssl req -new -key "$DIR/installer.key" \
  -out "$DIR/DeveloperIDInstaller.certSigningRequest" \
  -subj "$SUBJECT"

echo "CSR ready: $DIR/DeveloperIDInstaller.certSigningRequest"
echo "Private key (keep secret): $DIR/installer.key"
```

---

### `scripts/install-installer-cert.sh` (utility, file-I/O + request-response)

**Analog:** `scripts/install-installer-cert.sh`

**Input preflight pattern** (lines 15-23):
```bash
if [[ -z "$CER" || ! -f "$CER" ]]; then
  echo "Usage: install-installer-cert.sh ~/Downloads/developerID_installer.cer" >&2
  exit 1
fi

if [[ ! -f "$KEY" ]]; then
  echo "error: private key not found at $KEY (run scripts/create-installer-csr.sh on this Mac)" >&2
  exit 1
fi
```

**Keychain import pattern** (lines 25-37):
```bash
curl -fsSL -o "$G2_CA" "$G2_CA_URL"
security import "$G2_CA" -k "$KC" 2>/dev/null || true

openssl x509 -inform DER -in "$CER" -out "$PEM"
openssl pkcs12 -export -legacy -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg SHA1 \
  -out "$P12" -inkey "$KEY" -in "$PEM" \
  -passout "pass:$P12_PASS" -name "$P12_NAME"

security import "$P12" -k "$KC" -P "$P12_PASS" -A \
  -T /usr/bin/productsign -T /usr/bin/codesign -f pkcs12 2>/dev/null || \
  security import "$P12" -k "$KC" -P "$P12_PASS" -T /usr/bin/productsign -T /usr/bin/codesign -f pkcs12
```

**Verification output pattern** (lines 46-54):
```bash
echo ""
echo "Installed. Verify:"
if security find-identity -v -p basic 2>/dev/null | grep -q "Developer ID Installer"; then
  security find-identity -v -p basic | grep "Developer ID Installer"
else
  echo "  (If empty, open Keychain Access and confirm Developer ID Installer + private key are paired)"
fi
```

---

### `scripts/verify-installed-sync.sh` (utility, request-response + transform)

**Analog:** `scripts/verify-installed-sync.sh`

**Parse helper pattern** (lines 45-63):
```bash
parse_build_id() {
  local out="$1"
  if [[ "$out" =~ build=([^[:space:]]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
```

**Build identity proof pattern** (lines 104-131):
```bash
REPO_VERSION_OUT="$(capture_with_timeout 5 "$BRIDGE" --version || true)"
REPO_ID="$(parse_build_id "$REPO_VERSION_OUT")" || fail "could not parse build= from repo daemon --version"
note "repo_build_id=$REPO_ID"

HELPER_VERSION_OUT="$(capture_with_timeout 5 "$HELPER" --version || true)"
if ! HELPER_ID="$(parse_build_id "$HELPER_VERSION_OUT")"; then
  fail "could not parse build= from embedded helper --version"
fi
note "helper_build_id=$HELPER_ID"

if [[ "$REPO_ID" != "$HELPER_ID" ]]; then
  fail "build ID mismatch: repo=$REPO_ID helper=$HELPER_ID"
fi
note "OK: repo and embedded helper match ($REPO_ID)"
```

**Package install proof command:** use with `APM44_APP_PATH="/Applications/APM44 Bridge.app" bash scripts/verify-installed-sync.sh` after a real `installer -pkg ... -target /` probe.

---

### `scripts/verify-hal-driver.sh` (utility, request-response + file-I/O)

**Analog:** `scripts/verify-hal-driver.sh`

**Driver Gatekeeper pattern** (lines 62-69):
```bash
SPCTL_OUT="$(spctl -a -vv -t install "$DRIVER" 2>&1 || true)"
if grep -q 'accepted' <<<"$SPCTL_OUT"; then
  pass "Gatekeeper accepts driver (signed + notarized/stapled)"
elif grep -qi 'Unnotarized' <<<"$SPCTL_OUT"; then
  warn "Developer ID signed but NOT notarized - macOS 15+ will not load HAL (run scripts/notarize-hal-driver.sh)"
else
  warn "Gatekeeper does not accept driver - check codesign / notarization"
fi
```

**Installed HAL replacement proof** (lines 71-83):
```bash
INSTALLED="/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver"
if [[ -d "$INSTALLED" ]]; then
  INSTALLED_BIN=$(find "$INSTALLED/Contents/MacOS" -maxdepth 1 -type f 2>/dev/null | head -1)
  if [[ -n "$BIN" && -n "$INSTALLED_BIN" ]]; then
    BUILD_SHA="$(sha256 "$BIN")"
    INSTALLED_SHA="$(sha256 "$INSTALLED_BIN")"
    if [[ "$BUILD_SHA" == "$INSTALLED_SHA" ]]; then
      pass "installed HAL executable matches build ($BUILD_SHA)"
    elif [[ "${APM44_ALLOW_STALE_INSTALLED:-0}" == "1" ]]; then
      warn "installed HAL executable differs from build (build=$BUILD_SHA installed=$INSTALLED_SHA)"
    else
      fail "installed HAL executable differs from build (build=$BUILD_SHA installed=$INSTALLED_SHA)"
```

---

### `docs/release.md` (config/docs, batch instructions)

**Analog:** `docs/release.md`

**Current distribution posture to update if docs are in scope** (lines 20-33):
```markdown
The current release-candidate posture is **DMG-primary** for public distribution.
The public artifact is the signed, notarized, stapled DMG produced by
`scripts/release-all.sh`.

PKG tooling remains maintainer-only for now. Use `APM44_BUILD_PKG=1` only to
test the package path after Developer ID Installer signing and validation are
configured.
```

**Release order list pattern** (lines 88-99):
```markdown
`release-all.sh` uses this order:

1. Build Release app, daemon, and driver.
2. Embed the current daemon into `APM44 Bridge.app`.
3. Sign the daemon, app, and driver.
4. Submit a signed app/driver evidence zip with `notarytool --wait`.
5. Staple and validate the inner app and driver.
6. Repackage the final DMG from those stapled inner artifacts.
7. Notarize, staple, and validate the final public DMG.
```

Planner note: Phase 46 does not own polished public docs, but if touched, update only release-maintainer truth about PKG gate status and avoid Phase 47/50 publication claims.

---

### `docs/release-validation.md` (config/docs, batch validation)

**Analog:** `docs/release-validation.md`

**Release validation command style** (lines 97-112):
```bash
# 3. Release build, signing, notarization, stapling, and DMG packaging
export SIGN_ID="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
bash scripts/release-all.sh

# 4. Artifact signing/notary assessment
bash scripts/codesign-verify-release.sh
xcrun stapler validate "build/Release/APM44 Bridge.app"
xcrun stapler validate build/Driver/APM44Bridge.driver
xcrun stapler validate "build/signing/APM44Bridge-${APM44_VERSION:-0.11.1}.dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "build/signing/APM44Bridge-${APM44_VERSION:-0.11.1}.dmg"
```

**Existing optional PKG validation block to promote** (lines 159-168):
```markdown
Optional maintainer-only PKG validation is intentionally separate:

~~~bash
APM44_BUILD_PKG=1 bash scripts/release-all.sh
pkgutil --check-signature build/signing/*.pkg
spctl --assess --type install --verbose=4 build/signing/*.pkg
~~~
```

Planner note: if docs are updated in Phase 46, this block should mirror the new normal package gate: signed PKG, notary acceptance, stapler validate, `pkgutil`, `spctl --type install`, and post-staple `.pkg.sha256`.

## Shared Patterns

### Strict Shell Entrypoints
**Source:** `scripts/build-release-pkg.sh` lines 1-13 and `tests/test_release_scripts.sh` lines 1-16
**Apply to:** All modified shell scripts and Bash tests
```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
```

### Public Release Fail-Closed Gates
**Source:** `scripts/release-all.sh` lines 16-21
**Apply to:** `scripts/release-all.sh`, `scripts/build-release-pkg.sh`, `scripts/notarize-release-pkg.sh`
```bash
echo "Public release artifacts must be notarized." >&2
echo "Configure credentials with scripts/setup-notary-profile.sh, or rerun with" >&2
echo "APM44_ALLOW_UNNOTARIZED=1 for local-only unnotarized artifacts." >&2
exit 1
```

### Notary Acceptance
**Source:** `scripts/notary-result.sh` lines 32-59
**Apply to:** `scripts/notarize-release-pkg.sh`, `scripts/notarize-release-dmg.sh`
```bash
require_notary_accepted "$PKG" "$PROFILE" "pkg"
```

### Final-Bytes Checksum
**Source:** `scripts/notarize-release-dmg.sh` lines 20-29
**Apply to:** `scripts/notarize-release-pkg.sh`
```bash
xcrun stapler validate "$DMG"
(
  cd "$(dirname "$DMG")"
  shasum -a 256 "$(basename "$DMG")" >"$(basename "$DMG").sha256"
)
```

### Credential-Free Release Tests
**Source:** `tests/test_release_scripts.sh` lines 17-166 and 174-244
**Apply to:** All package gate tests
```bash
env \
  PATH="$FAKE_BIN:$PATH" \
  APM44_FAKE_XCRUN_LOG="$LOG" \
  APM44_FAKE_NOTARY_MODE="$mode" \
  NOTARY_PROFILE=TEST_PROFILE \
  "$artifact_env=$artifact_path" \
  /bin/bash "$ROOT/$script" >"$out" 2>&1
```

### Package Install Verification
**Source:** `scripts/verify-installed-sync.sh` lines 104-131 and `scripts/verify-hal-driver.sh` lines 71-83
**Apply to:** Manual package install/upgrade proof and any package smoke script
```bash
APM44_APP_PATH="/Applications/APM44 Bridge.app" bash scripts/verify-installed-sync.sh
bash scripts/verify-hal-driver.sh
```

## No Analog Found

All planned Phase 46 file roles have close analogs in the current codebase. No new packaging framework or novel test harness is needed.

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| _none_ | _n/a_ | _n/a_ | Existing release scripts, notary helper, and Bash fake-tool tests cover the needed patterns. |

## Metadata

**Analog search scope:** `scripts/`, `tests/`, `docs/`, `.github/`
**Files scanned:** 29 release/test/doc/workflow matches plus 12 line-numbered source reads
**Pattern extraction date:** 2026-07-01
**Primary phase inputs:** `46-CONTEXT.md`, `46-RESEARCH.md`, `46-VALIDATION.md`
