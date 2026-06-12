# 15-01 Summary: Local IPC Threat Model and Installer Decision

**Completed:** 2026-06-12
**Status:** Complete

## Work Completed

- Added public local IPC security wording to `docs/hal-driver.md` and
  `docs/release.md`.
- Explained that `/apm44_bridge_ring` is local-machine IPC, not an
  authentication or privilege boundary.
- Documented the implication of shm mode `0666`: other local users or processes
  may be able to open the object, so no secrets or authorization decisions
  belong in the ring.
- Listed future hardening options: per-user/per-session names, tighter
  owner/group permissions, privileged helper or launchd setup, XPC-mediated
  coordination, and moving sensitive control state out of shared memory.
- Made the public installer posture explicit: v0.4 remains DMG-primary.
- Clarified that the DMG admin password prompt is expected because the HAL
  driver installs under `/Library/Audio/Plug-Ins/HAL/`.
- Recorded that PKG tooling remains maintainer-only/future until Developer ID
  Installer signing, UX, and validation are complete.

## Requirements Closed

- DOC-01: Public docs explain local-machine IPC and no auth/privilege boundary.
- DOC-02: Docs explain shm mode `0666` implications without overclaiming.
- DOC-03: Docs list future local IPC hardening options.
- PKG-01: Milestone records DMG-primary public distribution and PKG follow-up.
- PKG-02: Public docs make the admin HAL install flow explicit and professional.

## Verification

```bash
grep -n 'not an authentication or privilege boundary\|0666\|Future hardening' docs/hal-driver.md docs/release.md
grep -n 'DMG-primary\|maintainer-only\|admin password' docs/install.md docs/release.md README.md .planning/PROJECT.md
```

All checks passed.

## Follow-Up

15-02 must align the final DMG packaging order with stapled inner artifacts and
record the GitHub Actions trust decision for release/signing workflows.
