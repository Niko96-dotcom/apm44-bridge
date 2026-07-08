# Changelog

## Unreleased

- Add `deslop-doctor.py` for harness PATH/auth/model readiness checks.
- Reject PASS verdicts that imply behavioral coverage but change no test/spec files.
- Enforce hard per-fix file/line budgets after attempt snapshots.
- Clarify P2-remaining status when P0/P1 loops stop with P2 still queued.
- Add `deslop-resume.py` for `needs_human` / `blocked` resolution.
- Document multi-harness soak recording in `references/soak-runs.md`.
- Persist bounded-loop stop outcomes in `.deslop/state.json` and surface them from `deslop-status.py`.
- Reject thin verifier verdicts that lack evidence or NEEDS_HUMAN follow-up detail.
- Print verifier evidence/concerns/follow-up from `deslop-finalize.py`.
- Add a deterministic end-to-end proof fixture that runs without a live model.

## v0.1.0 - 2026-06-01

- Initial public repository packaging.
- Added multi-harness Ultimate De-Slop skill source.
- Added GitHub Pages landing page, README, CI, contribution, security, and license files.
- Added local control-plane test command and syntax-check workflow.
