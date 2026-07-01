---
phase: 48-install-upgrade-and-uninstall-proof
status: draft
created: 2026-07-01
---

# Phase 48 Validation

| ID | Requirement | Proof | Command |
|----|-------------|-------|---------|
| 48-01 | INST-01, INST-04 | Verifier resolves PKG from final mounted DMG, not repo-local build output | `bash tests/test_release_scripts.sh` |
| 48-02 | INST-02, INST-03 | Install smoke runs installed-sync, HAL verifier, and shm-status only after explicit opt-in | `APM44_RUN_FINAL_INSTALL_SMOKE=1 bash scripts/verify-final-install-artifact.sh` |
| 48-03 | INST-05 | Uninstall command is documented and dry-run safe by default | `bash tests/test_release_scripts.sh` |

