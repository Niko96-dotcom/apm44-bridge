---
phase: 16-release-validation-closure
status: passed
verified: 2026-06-12
score: 5/5
human_verification_required: false
---

# Phase 16 Verification: Release Validation Closure

## Verdict

Phase 16 passed automated and release-artifact verification.

## Must-Haves

| # | Must-have | Status | Evidence |
|---|-----------|--------|----------|
| 1 | QA-01 final automated verification includes secret scan, native tests, Swift tests, app build verification, and release-script regression tests. | Passed | `bash scripts/ci.sh` passed after the Phase 16 review commit with build id `0.1.1+7803169fb3bc`. |
| 2 | QA-02 release validation sequence is recorded from clean build through signing, notarization, stapling, and Gatekeeper assessment. | Passed | `docs/release-validation.md` records the full command sequence and `16-01-SUMMARY.md`/`16-02-SUMMARY.md` record live execution evidence. |
| 3 | QA-03 selected DMG-primary artifact path is assessed with `codesign`, `stapler validate`, `spctl`, and supporting artifact checks. | Passed | `bash scripts/release-all.sh`, `bash scripts/codesign-verify-release.sh`, DMG codesign verification, app/driver/DMG stapler validation, corrected Gatekeeper assessment, and `hdiutil verify` all passed. |
| 4 | QA-04 credential, certificate, hardware, or operator blockers are recorded with exact unblock commands. | Passed | Apple credentials were available and used successfully; `docs/release-validation.md` still records exact unblock commands for Developer ID, notary profile, stapler/Gatekeeper failures, optional PKG validation, and hardware/operator evidence. |
| 5 | QA-05 planning state records satisfied requirements, accepted gaps, and public-release caveats. | Passed | `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/STATE.md`, and this verification record reflect completed QA requirements and remaining publication/hardware/operator caveats. |

## Automated Evidence

```bash
gsd-sdk query verify.schema-drift 16
```

Result: no schema drift; blocking false.

```bash
gsd-sdk query verify.codebase-drift
```

Result: skipped with `no-structure-md`; action required false.

```bash
gsd-sdk query state.validate
```

Result: valid; no warnings or drift.

```bash
bash scripts/ci.sh
```

Result: passed.

Final CI evidence included:

- secret scan: OK, 1162 tracked/non-ignored files scanned,
- Release CMake configure with build id `0.1.1+7803169fb3bc`,
- native build,
- native CTest suite,
- release-script regression tests,
- Swift app build verification,
- Swift unit tests: 42 tests, 0 failures,
- daemon embedding into `build/Release/APM44 Bridge.app`,
- installed-sync dry-run with repo/helper build id
  `0.1.1+7803169fb3bc`, and
- final output `ci: OK`.

## Release Artifact Evidence

```bash
bash scripts/release-all.sh
```

Result: passed.

Key release evidence:

- release build id: `0.1.1+d5efb41ec1ca`,
- app/driver evidence zip submission id:
  `cd75ded5-9cf3-4d4e-824e-62f620882d9b`, status `Accepted`,
- app stapler validation: passed,
- driver stapler validation: passed,
- final DMG submission id: `a0d1c64b-d45b-4e17-bc85-a4d3d78ff562`,
  status `Accepted`,
- final DMG stapler validation: passed,
- public DMG: `build/signing/APM44Bridge-0.1.1.dmg`,
- public DMG SHA-256:
  `64653ec98e2a7ada4b3fa6c73f905f467a2851a3cbeb39cb35070aefcd973d16`.

```bash
bash scripts/codesign-verify-release.sh
codesign --verify --verbose build/signing/APM44Bridge-0.1.1.dmg
xcrun stapler validate "build/Release/APM44 Bridge.app"
xcrun stapler validate build/Driver/APM44Bridge.driver
xcrun stapler validate build/signing/APM44Bridge-0.1.1.dmg
spctl --assess --type open --context context:primary-signature --verbose=4 build/signing/APM44Bridge-0.1.1.dmg
hdiutil verify build/signing/APM44Bridge-0.1.1.dmg
```

Results:

- `codesign-verify-release: passed`,
- DMG codesign verification passed,
- app/driver/DMG stapler validation passed,
- Gatekeeper accepted the DMG with `source=Notarized Developer ID`,
- `hdiutil verify` reported a valid DMG checksum.

## Review Evidence

`16-REVIEW.md` status: clean.

During execution, the first DMG Gatekeeper command without
`--context context:primary-signature` returned `source=Insufficient Context`.
The checklist and plan were corrected, and the corrected command passed.

## Residual Caveats

- GitHub release publication/upload remains an operator action after reviewing
  the generated DMG and release notes.
- PKG remains maintainer-only/future unless `APM44_BUILD_PKG=1` is intentionally
  run with Developer ID Installer validation.
- Live USB-C AirPods/Cubase soak evidence remains operator-dependent hardware
  validation, documented as a caveat rather than a blocker for the automated and
  release-artifact validation path.

## Human Verification

None required for Phase 16 release-artifact closure. The generated DMG has local
Developer ID signing, Apple notarization, stapling, and Gatekeeper evidence.

## Gaps

None.
