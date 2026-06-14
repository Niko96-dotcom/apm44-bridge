# Requirements: APM44 Bridge v0.9 Public Polish Final Hardening

**Defined:** 2026-06-14
**Core Value:** A producer can start monitoring once and trust Cubase at 44.1
kHz to keep playing through USB-C AirPods at 48 kHz without silent wedges or
mystery relaunches.

## v0.9 Requirements

### Core Audio Format Contract

- [x] **ASBD-01**: `AsbdMatchesFloat32Stereo` rejects stereo Float32 ASBDs whose
  `mFramesPerPacket` is not exactly `1`.
- [x] **ASBD-02**: `AsbdMatchesFloat32Stereo` rejects interleaved stereo Float32
  ASBDs unless `kAudioFormatFlagIsPacked` is set and both byte-size fields are
  exactly `sizeof(float) * 2`.
- [x] **ASBD-03**: `AsbdMatchesFloat32Stereo` rejects non-interleaved stereo
  Float32 ASBDs unless both byte-size fields are exactly `sizeof(float)`.
- [x] **ASBD-04**: Regression tests cover incorrect interleaved and
  non-interleaved byte-size ASBDs so IOProc memory assumptions stay guarded.

### Shared-Memory Compatibility Truth

- [x] **SHM-01**: Shared-memory release/security docs accurately say which ring
  fields are hard validation gates and which fields are diagnostic evidence.
- [x] **SHM-02**: Build ID is either enforced as a hard compatibility check in
  `MmapShmRing` open/validation or documented only as diagnostic evidence.
- [x] **SHM-03**: Ring sample rate compatibility is validated or explicitly
  documented as outside the current hard validation contract.

### Public Documentation Truth

- [x] **DOC-01**: README, changelog, install docs, release docs, artifact names,
  issue-template placeholders, and validation commands use one current release
  version identity.
- [x] **DOC-02**: Latency preset docs and release checklists identify Safe as
  the fresh-install default when that is the app default.
- [x] **DOC-03**: Release docs consistently use the actual HAL driver build
  path, `build/Driver/APM44Bridge.driver`.

### Release Automation

- [x] **REL-01**: `scripts/release-all.sh` runs
  `scripts/codesign-verify-release.sh` after signed app/driver artifacts exist
  and before notarization proceeds.
- [x] **REL-02**: Release-script regression coverage proves `release-all.sh`
  cannot skip strict codesign verification on the normal release path.
- [x] **REL-03**: The full release automation path still supports the explicit
  local-development override behavior already documented for weak/local signing.

### GitHub Workflow Intent

- [x] **GHA-01**: `.github/workflows/sign-notarize.yml` either produces and
  uploads signed release artifacts or is renamed/commented as maintainer
  credential smoke-test / release-evidence workflow.
- [x] **GHA-02**: Public workflow wording makes clear whether GitHub Actions is
  authoritative for public artifacts or only supports maintainer evidence.

### Verification Closure

- [ ] **QA-01**: Native, Swift, release-script, and installed-sync CI gates pass
  after the v0.9 changes.
- [ ] **QA-02**: v0.9 closeout records any remaining operator-owned publication
  or target-hardware validation caveats without reopening completed release
  automation work.

## Future Requirements

### Distribution

- **PKG-01**: Promote signed PKG installer validation from maintainer-only to a
  public release path after Developer ID Installer validation is intentionally
  completed.
- **PUB-01**: Automate GitHub release upload/publication after the maintainer is
  ready to move artifact publication out of the operator-owned path.

### Compatibility

- **COMP-01**: Validate Logic and Ableton host behavior after the Cubase 15
  USB-C AirPods path remains stable.

## Out of Scope

| Feature | Reason |
|---------|--------|
| New DSP/resampler architecture | v0.9 is final public-polish hardening, not a DSP rewrite. |
| PKG-primary public installer | Remains future/maintainer-only until Developer ID Installer validation is completed. |
| Broad DAW validation matrix | Cubase 15 USB-C AirPods remains the public validation anchor for this release. |
| New authentication/security boundary for local IPC | Current scope is truthful local IPC documentation and compatibility validation, not changing the local trust model. |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| ASBD-01 | Phase 33 | Complete |
| ASBD-02 | Phase 33 | Complete |
| ASBD-03 | Phase 33 | Complete |
| ASBD-04 | Phase 33 | Complete |
| SHM-01 | Phase 34 | Complete |
| SHM-02 | Phase 34 | Complete |
| SHM-03 | Phase 34 | Complete |
| DOC-01 | Phase 35 | Complete |
| DOC-02 | Phase 35 | Complete |
| DOC-03 | Phase 35 | Complete |
| REL-01 | Phase 36 | Complete |
| REL-02 | Phase 36 | Complete |
| REL-03 | Phase 36 | Complete |
| GHA-01 | Phase 36 | Complete |
| GHA-02 | Phase 36 | Complete |
| QA-01 | Phase 37 | Pending |
| QA-02 | Phase 37 | Pending |

**Coverage:**
- v0.9 requirements: 17 total
- Mapped to phases: 17
- Unmapped: 0

---
*Requirements defined: 2026-06-14*
*Last updated: 2026-06-14 after v0.9 roadmap creation*
