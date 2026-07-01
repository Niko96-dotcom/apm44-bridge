---
phase: 46
slug: pkg-installer-promotion
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-07-01
---

# Phase 46 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | CTest/Catch2 native tests plus Bash release-script harness |
| **Config file** | `tests/CMakeLists.txt`; Bash release tests are invoked from `scripts/ci.sh` |
| **Quick run command** | `bash tests/test_release_scripts.sh` |
| **Full suite command** | `bash scripts/ci.sh` |
| **Estimated runtime** | ~2-6 minutes for full CI on this machine |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/test_release_scripts.sh`
- **After every plan wave:** Run `bash scripts/ci.sh`
- **Before `$gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** one task commit

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 46-01-01 | 01 | 1 | PKG-02 | T-46-01 | Missing or ambiguous Developer ID Installer identity cannot create a public final package path | release-script unit | `bash tests/test_release_scripts.sh` | W0 needed | pending |
| 46-01-02 | 01 | 1 | PKG-01, PKG-04 | T-46-02 | Package payload is staged from signed/stapled app and HAL driver into `/Applications` and `/Library/Audio/Plug-Ins/HAL` | release-script unit / payload probe | `bash tests/test_release_scripts.sh` | W0 needed | pending |
| 46-02-01 | 02 | 1 | PKG-03 | T-46-03 | Package notarization, stapling, signature validation, Gatekeeper assessment, and checksum happen after final package bytes | release-script unit + release-Mac command | `bash tests/test_release_scripts.sh` | W0 needed | pending |
| 46-03-01 | 03 | 2 | PKG-01, PKG-03, PKG-04 | T-46-04 | Normal notarized release orchestration includes the public package gate before the DMG wrapper consumes artifacts | release-script unit + full CI | `bash scripts/ci.sh` | W0 needed | pending |
| 46-04-01 | 04 | 2 | PKG-05 | T-46-05 | First install and upgrade semantics replace stale app/helper/driver state and are handed to Phase 48 for final mounted-artifact proof | script inspection + recorded package probe | `bash tests/test_release_scripts.sh` | W0 needed | pending |

*Status: pending, green, red, flaky*

---

## Wave 0 Requirements

- [ ] `tests/test_release_scripts.sh` — fake `productsign`, `pkgutil`, and `spctl` coverage for package signing and validation gates
- [ ] `tests/test_release_scripts.sh` — fake `security` modes for zero, one, multiple, and explicit Developer ID Installer identity resolution
- [ ] `tests/test_release_scripts.sh` — package gate order assertions: inner stapling before package build, package notary/staple/signature/Gatekeeper before checksum
- [ ] `scripts/build-release-pkg.sh` and `scripts/notarize-release-pkg.sh` — deterministic error output that tests can assert

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Real package notarization and Gatekeeper installer assessment | PKG-03 | Apple notary service and Developer ID Installer certificate require maintainer Keychain credentials | `bash scripts/release-all.sh`, then `pkgutil --check-signature build/signing/APM44Bridge-<version>.pkg`, `xcrun stapler validate build/signing/APM44Bridge-<version>.pkg`, and `spctl --assess --type install --verbose=4 build/signing/APM44Bridge-<version>.pkg` |
| Real install/upgrade over current public release | PKG-05 | Writes `/Applications` and `/Library/Audio/Plug-Ins/HAL` and may require admin authorization/Core Audio reload | Phase 46 may run a package probe, but final mounted-DMG install/upgrade proof is owned by Phase 48 |

---

## Validation Sign-Off

- [x] All tasks have automated verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all missing references
- [x] No watch-mode flags
- [x] Feedback latency is bounded by task commit
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-07-01
