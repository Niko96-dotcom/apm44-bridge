# Requirements: APM44 Bridge

**Defined:** 2026-06-12
**Milestone:** v0.4 Public Release Blocker Closure
**Core Value:** A producer can start monitoring once and trust Cubase at 44.1
kHz to keep playing through USB-C AirPods at 48 kHz without silent wedges or
mystery relaunches.

## v0.4 Requirements

### Runtime Correctness

- [ ] **METR-01**: Metrics publication is standard C++ data-race-free; readers
  and writers no longer concurrently access a non-atomic `MetricsSnapshot`
  payload.
- [ ] **METR-02**: Metrics values remain available to CLI JSON and app UI after
  the publication mechanism changes, including fill, ratio, ppm, underruns,
  overruns, xruns, estimated realtime latency, target fill, and SRC quality.
- [ ] **METR-03**: Metrics regression coverage proves the race-free contract
  with ThreadSanitizer where practical, or with an explicit source-level guard
  when sanitizer execution is not available in CI.
- [ ] **JSON-01**: `BridgeMetrics::ToJsonLine` handles `snprintf` failure and
  truncation without reading past its fixed stack buffer.
- [ ] **JSON-02**: A regression test uses an intentionally long `src_quality`
  value to prove JSON serialization returns safe output on truncation.
- [ ] **AUD-01**: Virtual-device output-start failure cleanup never stops a null
  or nonexistent input IOProc.
- [ ] **AUD-02**: Non-interleaved input callbacks use the minimum available
  frame count across channel buffers before clamping, preventing overread of a
  shorter second buffer.
- [ ] **AUD-03**: Core Audio regression tests cover virtual-device output-start
  failure cleanup and mismatched non-interleaved input buffer sizes.
- [ ] **RT-01**: The input overrun helper name and comments match the actual
  drop-new-input behavior.
- [ ] **RT-02**: The unused `WriteSilence` helper is deleted or rewritten so no
  dead realtime helper remains with incorrect byte-count assumptions.

### Release Automation

- [ ] **REL-01**: `scripts/notarize-release-dmg.sh` fails unless `notarytool`
  exits successfully and reports `status: Accepted`.
- [ ] **REL-02**: `scripts/notarize-release-pkg.sh` follows the same
  fail-closed notarization contract as the DMG script.
- [ ] **REL-03**: Notarization scripts print the submission output and attempt to
  fetch the notary log when a failed submission id is available.
- [ ] **REL-04**: `scripts/release-all.sh` treats missing notarization
  credentials as a release-blocking failure unless an explicit
  `APM44_ALLOW_UNNOTARIZED=1` local-development override is set.
- [ ] **REL-05**: Any unnotarized override path labels artifacts clearly as
  local-only and not public-release-ready.
- [ ] **REL-06**: `.github/workflows/sign-notarize.yml` does not mask app build
  verification failure with `|| true` or an equivalent soft-fail pattern.
- [ ] **REL-07**: Release-script regression coverage simulates accepted,
  rejected, auth-failure, network-failure, and malformed `notarytool` output
  without requiring Apple credentials.

### Public Trust and Distribution UX

- [ ] **DOC-01**: Public docs include a Security / Local IPC section explaining
  that the shared-memory ring is local-machine IPC and not an authentication or
  privilege boundary.
- [ ] **DOC-02**: Docs explicitly describe the implications of shm mode `0666`
  and avoid overclaiming protection against other local users or processes.
- [ ] **DOC-03**: Docs list future hardening options for local IPC, such as
  per-user naming, tighter ownership, a privileged installer/helper, or an
  XPC-mediated setup path.
- [ ] **PKG-01**: The milestone records a clear decision on whether v0.4 makes a
  signed PKG the primary installer or keeps DMG-primary with PKG as a tracked
  release follow-up.
- [ ] **PKG-02**: If DMG remains primary, release docs make the admin install
  flow explicit and professional for a HAL driver.
- [ ] **PKG-03**: Release automation staples and validates inner app/driver
  artifacts and the final public container in an order that matches the
  distributed artifact.
- [ ] **GHA-01**: Critical GitHub Actions used near release artifacts,
  credentials, or signing are pinned to full-length commit SHAs or have an
  explicit documented trust decision.

### Validation Closure

- [ ] **QA-01**: Final automated verification includes secret scan, CMake/Catch2
  tests, Swift app tests, app build verification, and release-script regression
  tests.
- [ ] **QA-02**: Final release validation records the exact command sequence from
  clean build through signing, notarization, stapling, and Gatekeeper assessment.
- [ ] **QA-03**: Final validation checks the current release artifact path with
  `codesign`, `stapler validate`, and `spctl` or `pkgutil` as appropriate for
  the chosen DMG/PKG distribution path.
- [ ] **QA-04**: Any validation step blocked by Apple credentials, installer
  certificate availability, hardware, or operator access is recorded with exact
  unblock commands instead of being silently treated as complete.
- [ ] **QA-05**: Milestone close updates planning state with satisfied
  requirements, accepted gaps, and public-release caveats.

## Future Requirements

### Broader Compatibility

- **DAW-01**: Producer can run the same reliability checks against Logic and
  Ableton with documented DAW-specific setup.
- **OUT-01**: User can choose other 48 kHz USB outputs with the same recovery
  guarantees as USB-C AirPods Max.

### Observability

- **OBS-01**: User can export a compact support bundle with app state, helper
  version, driver version, recent stderr, and shm status.

### IPC Hardening

- **IPC-01**: Shared-memory setup can use per-user naming or tighter ownership
  without breaking the HAL-driver-to-daemon data path.
- **IPC-02**: A privileged helper or XPC-mediated setup path can create the shm
  object with controlled ownership.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Logic/Ableton validation matrix | v0.4 closes public-release blockers before broad DAW expansion. |
| Support bundle export | Useful future diagnostics, but not required to close the publishing blockers. |
| Bluetooth-only AirPods mode | USB-C AirPods Max remains the low-jitter product target. |
| New DSP/resampler architecture | The blocker list targets correctness, automation, and release trust in the existing shipped path. |
| Full local IPC redesign | v0.4 must document the current threat model; ownership/XPC redesign is future hardening unless the PKG decision makes it necessary. |
| Publishing `.planning/` publicly | The public repo intentionally ignores internal planning artifacts unless explicitly force-added for local GSD state. |

## Traceability

Roadmap phase mapping for v0.4.

| Requirement | Phase | Status |
|-------------|-------|--------|
| METR-01 | Phase 13 | Pending |
| METR-02 | Phase 13 | Pending |
| METR-03 | Phase 13 | Pending |
| JSON-01 | Phase 13 | Pending |
| JSON-02 | Phase 13 | Pending |
| AUD-01 | Phase 13 | Pending |
| AUD-02 | Phase 13 | Pending |
| AUD-03 | Phase 13 | Pending |
| RT-01 | Phase 13 | Pending |
| RT-02 | Phase 13 | Pending |
| REL-01 | Phase 14 | Pending |
| REL-02 | Phase 14 | Pending |
| REL-03 | Phase 14 | Pending |
| REL-04 | Phase 14 | Pending |
| REL-05 | Phase 14 | Pending |
| REL-06 | Phase 14 | Pending |
| REL-07 | Phase 14 | Pending |
| DOC-01 | Phase 15 | Pending |
| DOC-02 | Phase 15 | Pending |
| DOC-03 | Phase 15 | Pending |
| PKG-01 | Phase 15 | Pending |
| PKG-02 | Phase 15 | Pending |
| PKG-03 | Phase 15 | Pending |
| GHA-01 | Phase 15 | Pending |
| QA-01 | Phase 16 | Pending |
| QA-02 | Phase 16 | Pending |
| QA-03 | Phase 16 | Pending |
| QA-04 | Phase 16 | Pending |
| QA-05 | Phase 16 | Pending |

**Coverage:**
- v0.4 requirements: 29 total
- Mapped to phases: 29
- Unmapped: 0

---
*Requirements defined: 2026-06-12*
*Last updated: 2026-06-12 after v0.4 roadmap creation*
