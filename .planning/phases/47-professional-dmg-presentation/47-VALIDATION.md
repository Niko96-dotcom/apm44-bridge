---
phase: 47-professional-dmg-presentation
status: draft
created: 2026-07-01
---

# Phase 47 Validation

| ID | Requirement | Proof | Command |
|----|-------------|-------|---------|
| 47-01 | DMG-01, DMG-02 | Package-only staging contains PKG and excludes raw internals | `bash tests/test_release_scripts.sh` |
| 47-02 | DMG-03, DMG-05 | DMG notarization staples, Gatekeeper-assesses, then checksums | `bash tests/test_release_scripts.sh` |
| 47-03 | DMG-04 | Layout verifier accepts PKG-first and rejects old raw layout | `bash tests/test_release_scripts.sh` |
| 47-04 | all | Full repo regression gate | `bash scripts/ci.sh` |

