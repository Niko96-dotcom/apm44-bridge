---
phase: 12
plan: 01
title: CI dry-run for installed-sync and full automated gate run
subsystem: verification
status: complete
---

# Plan 12-01: CI dry-run for installed-sync and full automated gate run

## What was done

### Task 1 — Wired `verify-installed-sync.sh --dry-run` into `ci.sh`

Added a new step at the end of `scripts/ci.sh`, after the Swift
unit tests and before the final `ci: OK`:

```bash
echo "== Installed-sync dry-run =="
bash scripts/verify-installed-sync.sh --dry-run
```

The dry-run path is non-fatal: the existing
`verify-installed-sync.sh` exits 0 with a `WARN:` if the
embedded helper is missing, or `0` with an `OK:` line if the
build IDs match. The CI exit code is therefore unaffected by
the typical "helper not yet embedded" state, but the WARN
surfaces that drift to operators reading the log.

### Task 2 — Ran the full CI gate

`bash scripts/ci.sh` was executed end-to-end:

- Secret scan: OK.
- Prepare submodules: OK.
- Configure CMake (Release): OK.
- Build native targets: OK.
- Native tests (ctest): 20/20 passed.
- Swift app build: `** BUILD SUCCEEDED **`.
- Swift unit tests: 42/42 passed.
- Installed-sync dry-run: `OK: repo and embedded helper match
  (0.1.1+4fd2f6d43cf7-dirty)`.
- `ci: OK` (script exit 0).

Full log: `12-ci-run.log` (same directory).

### Task 3 — Wrote `12-AUTOMATED-VERIFICATION.md`

Captured the table of CI steps and results, the test totals,
and the deviation note (the first dry-run caught a real
build-ID drift between the repo daemon and the embedded
helper; re-embedded via `scripts/embed-daemon-in-app.sh` and
the gate went green).

## Deviations

None at the source level. The first CI run **caught a real
build-ID drift** — exactly the class of drift the dry-run is
designed to surface. This is recorded as a positive
observation in the verification document, not as a defect.

## Commits

- `chore(ci): run verify-installed-sync.sh --dry-run as a
  non-hardware gate` — adds the new step in `scripts/ci.sh`.
- `docs(12):` — adds `12-AUTOMATED-VERIFICATION.md` and
  `12-ci-run.log`.
