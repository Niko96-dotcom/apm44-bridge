# Roadmap: APM44 Bridge

## Milestones

- Complete **v0.1.0 Initial Distribution** - Phases 1-4 (shipped 2026-06-01)
- Complete **v0.1.1 Public Release** - HAL dropout recovery, metrics clarity,
  notarized DMG (shipped 2026-06-03)
- Complete **v0.2 Reliability and Self-Healing** - Phases 5-8 (shipped
  2026-06-11) - [archive](milestones/v0.2-ROADMAP.md)
- Complete **v0.3 Realtime Audio Hardening** - Phases 9-12 (shipped
  2026-06-12) - [archive](milestones/v0.3-ROADMAP.md)
- Complete **v0.4 Public Release Blocker Closure** - Phases 13-16 (shipped
  2026-06-12) - [archive](milestones/v0.4-ROADMAP.md)
- Complete **v0.5 Release Readiness Hardening** - Phases 17-22 (shipped
  2026-06-13) - [archive](milestones/v0.5-ROADMAP.md)
- Complete **v0.6 Public Release Safety Fixes** - Phases 23-26 (shipped
  2026-06-13) - [archive](milestones/v0.6-ROADMAP.md)
- Complete **v0.7 Release Automation Final Polish** - Phases 27-29 (shipped
  2026-06-13) - [archive](milestones/v0.7-ROADMAP.md)
- Complete **v0.8 Release Candidate Closure** - Phases 30-32 (shipped
  2026-06-13) - [archive](milestones/v0.8-ROADMAP.md)
- Active **v0.9 Public Polish Final Hardening** - Phases 33-37

## Overview

v0.9 closes the last public-polish hardening gaps from the 2026-06-14 audit.
The milestone is intentionally narrow: prove the Core Audio ASBD memory contract
before IOProc code trusts buffer layout, align shared-memory validation wording
with actual behavior, normalize public release/version/default/path truth, wire
strict codesign verification into the one-command release path, and clarify
whether the GitHub signing workflow produces artifacts or evidence only.

## Phase Numbering

Phase numbering continues from shipped history:

- Phases 1-4: v0.1/v0.1.1 shipped product path.
- Phases 5-8: v0.2 Reliability and Self-Healing.
- Phases 9-12: v0.3 Realtime Audio Hardening.
- Phases 13-16: v0.4 Public Release Blocker Closure.
- Phases 17-22: v0.5 Release Readiness Hardening.
- Phases 23-26: v0.6 Public Release Safety Fixes.
- Phases 27-29: v0.7 Release Automation Final Polish.
- Phases 30-32: v0.8 Release Candidate Closure.
- Phases 33-37: v0.9 Public Polish Final Hardening.

## Phases

- [x] **Phase 33: ASBD Memory Contract** - Make Float32 stereo ASBD acceptance (completed 2026-06-14)
  match the exact interleaved and non-interleaved IOProc memory assumptions.
- [x] **Phase 34: Shared-Memory Compatibility Truth** - Align build-id and (completed 2026-06-14)
  sample-rate compatibility behavior with public release/security docs.
- [x] **Phase 35: Public Version and Defaults Truth** - Normalize release (completed 2026-06-14)
  version identity, Safe latency default wording, and HAL driver build path
  references.
- [ ] **Phase 36: Release Automation and Workflow Intent** - Run strict release
  codesign verification inside `release-all.sh` and clarify
  `sign-notarize.yml` artifact intent.
- [ ] **Phase 37: Regression and Public Polish Closure** - Run the full truth
  gates and record remaining operator-owned caveats without overclaiming.

## Phase Details

### Phase 33: ASBD Memory Contract

**Goal:** IOProc code only accepts ASBDs whose byte layout exactly matches the
Float32 stereo memory layout it will read.

**Depends on:** v0.8 shipped baseline

**Requirements:** ASBD-01, ASBD-02, ASBD-03, ASBD-04

**Success Criteria** (what must be TRUE):
1. Sample-rate, linear PCM, Float32, stereo, and 32-bit checks remain intact.
2. `mFramesPerPacket != 1` is rejected before buffer memory is trusted.
3. Interleaved stereo requires packed Float32 with `mBytesPerFrame` and
   `mBytesPerPacket` equal to two floats.
4. Non-interleaved stereo requires one float per frame/packet in each buffer.
5. Regression tests reject wrong byte-size ASBDs for both interleaved and
   non-interleaved formats.

**Plans:** 2/2 plans complete

Planned work:
- 33-01 - Tighten `AsbdMatchesFloat32Stereo` against exact packet/frame byte
  layout (ASBD-01, ASBD-02, ASBD-03)
- 33-02 - Add ASBD layout regression tests for weird Float32 stereo variants
  (ASBD-04)

### Phase 34: Shared-Memory Compatibility Truth

**Goal:** Shared-memory docs and validation behavior agree on whether build ID
and sample rate are hard compatibility gates or diagnostic evidence.

**Depends on:** Phase 33

**Requirements:** SHM-01, SHM-02, SHM-03

**Success Criteria** (what must be TRUE):
1. Release/security docs no longer imply build-ID rejection unless the code
   actually enforces that behavior.
2. `MmapShmRing` compatibility checks are either expanded to enforce build ID
   and sample rate or the docs explicitly identify them as diagnostics.
3. Any fixed-44.1 kHz daemon assumption is reflected in validation or plainly
   scoped in docs.
4. Regression tests or documentation checks cover the chosen behavior.

**Plans:** 2/2 plans complete

Planned work:
- 34-01 - Audit `MmapShmRing` open/validation behavior and pick enforcement vs
  documentation truth for build ID/sample rate (SHM-01, SHM-02, SHM-03)
- 34-02 - Add tests or doc guards proving the selected compatibility contract
  (SHM-01, SHM-02, SHM-03)

### Phase 35: Public Version and Defaults Truth

**Goal:** Public docs, release docs, templates, artifact wording, and latency
defaults agree with the code and current release identity.

**Depends on:** Phase 34

**Requirements:** DOC-01, DOC-02, DOC-03

**Success Criteria** (what must be TRUE):
1. README, changelog, install docs, release docs, artifact names, issue
   template placeholders, and validation commands use one current version
   identity.
2. Latency preset docs/checklists identify Safe as the fresh-install default
   when code defaults to Safe.
3. Release docs consistently reference `build/Driver/APM44Bridge.driver`.
4. Source or script tests catch the most important public-truth regressions
   where practical.

**Plans:** 2/2 plans complete

Planned work:
- 35-01 - Normalize release version identity across public docs, artifacts, and
  templates (DOC-01)
- 35-02 - Align latency-default wording and HAL driver build-path references
  with current code/scripts (DOC-02, DOC-03)

### Phase 36: Release Automation and Workflow Intent

**Goal:** The one-command release path proves strict signing posture before
notarization, and the GitHub signing workflow clearly states whether it creates
public artifacts or release evidence only.

**Depends on:** Phase 35

**Requirements:** REL-01, REL-02, REL-03, GHA-01, GHA-02

**Success Criteria** (what must be TRUE):
1. `scripts/release-all.sh` calls `scripts/codesign-verify-release.sh` after
   signed artifacts exist and before notarization proceeds.
2. Release-script regressions fail if the normal release path omits strict
   codesign verification.
3. Existing local-development override behavior remains explicit and tested.
4. `.github/workflows/sign-notarize.yml` either produces/upload signed
   artifacts or is clearly named/commented as a maintainer smoke-test/evidence
   workflow.
5. Public workflow docs no longer make GitHub Actions look more authoritative
   for public artifacts than it actually is.

**Plans:** 0/2 plans complete

Planned work:
- 36-01 - Insert release codesign verification into `release-all.sh` and
  regression-test the gate (REL-01, REL-02, REL-03)
- 36-02 - Clarify `sign-notarize.yml` artifact-producing vs evidence-only
  intent in workflow and docs (GHA-01, GHA-02)

### Phase 37: Regression and Public Polish Closure

**Goal:** v0.9 closes with clean repo truth gates and exact caveats for anything
that remains operator-owned.

**Depends on:** Phase 36

**Requirements:** QA-01, QA-02

**Success Criteria** (what must be TRUE):
1. Native tests, Swift tests, release-script regressions, and installed-sync
   dry-run pass through `scripts/ci.sh`.
2. Any additional targeted tests added in Phases 33-36 pass directly and through
   the full gate.
3. `docs/release-validation.md` and planning state distinguish automated
   release readiness from operator-owned publication/target-hardware validation.
4. Requirements traceability is reconciled before milestone closeout.

**Plans:** 0/1 plans complete

Planned work:
- 37-01 - Run full v0.9 regression gate and record final public-polish evidence
  (QA-01, QA-02)

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| ASBD-01 | Phase 33 | Pending |
| ASBD-02 | Phase 33 | Pending |
| ASBD-03 | Phase 33 | Pending |
| ASBD-04 | Phase 33 | Pending |
| SHM-01 | Phase 34 | Pending |
| SHM-02 | Phase 34 | Pending |
| SHM-03 | Phase 34 | Pending |
| DOC-01 | Phase 35 | Pending |
| DOC-02 | Phase 35 | Pending |
| DOC-03 | Phase 35 | Pending |
| REL-01 | Phase 36 | Pending |
| REL-02 | Phase 36 | Pending |
| REL-03 | Phase 36 | Pending |
| GHA-01 | Phase 36 | Pending |
| GHA-02 | Phase 36 | Pending |
| QA-01 | Phase 37 | Pending |
| QA-02 | Phase 37 | Pending |

**Coverage:** 17/17 requirements mapped.

## Verification Gates

- `scripts/ci.sh`
- Targeted native ASBD/shared-memory tests added or updated during execution
- Release-script regression tests covering `release-all.sh` and
  `sign-notarize.yml` truth

## Next Step

Start Phase 33 with:

`$gsd-plan-phase 33`

---
*Last updated: 2026-06-14 after v0.9 roadmap creation*
