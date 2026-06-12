# Pitfalls Research

**Domain:** macOS audio bridge public-release hardening
**Researched:** 2026-06-12
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: Seqlock Around Plain C++ Object

**What goes wrong:**
The writer stores a plain `MetricsSnapshot` while readers concurrently copy it. The sequence counter can detect torn reads, but it does not remove the data race on the non-atomic payload.

**Why it happens:**
Seqlock patterns are common in low-level systems code, but standard C++ still treats concurrent non-atomic read/write of the same object as undefined behavior.

**How to avoid:**
Use atomic fields, atomic bit-cast storage for doubles, or a preallocated buffer scheme where the writer never overwrites a buffer currently being copied by a reader.

**Warning signs:**
`MetricsPublisherState` contains `std::atomic` metadata plus a plain `MetricsSnapshot snapshot{}`; `ReadMetrics` copies `state.snapshot` while `PublishMetrics` assigns it.

**Phase to address:**
Phase 13: Runtime Correctness Blockers.

---

### Pitfall 2: `snprintf` Truncation Treated as Written Length

**What goes wrong:**
`std::string(buffer, written)` reads past the stack buffer if `snprintf` truncates and returns the would-have-written length.

**Why it happens:**
The `snprintf` return contract is easy to misremember: a non-negative return can still exceed the supplied buffer.

**How to avoid:**
Return `{}` or allocate/retry when `written >= sizeof(buffer)`. Add a long `srcQuality` regression test.

**Warning signs:**
Fixed char buffer plus string construction from the raw `written` value.

**Phase to address:**
Phase 13: Runtime Correctness Blockers.

---

### Pitfall 3: Error-Path Cleanup Uses Resources That Do Not Exist

**What goes wrong:**
Virtual-device mode can call input-device cleanup when no input IOProc was created after output start fails.

**Why it happens:**
Common start/stop cleanup logic assumes physical input mode and virtual-device mode have the same resource graph.

**How to avoid:**
Guard input cleanup with `!virtualDevice_ && inputProc_ != nullptr`, then call the shared `stop()` cleanup.

**Warning signs:**
`AudioDeviceStop(devices_.input.deviceId, inputProc_)` on an output-start failure path regardless of mode.

**Phase to address:**
Phase 13: Runtime Correctness Blockers.

---

### Pitfall 4: Per-Channel Frame Mismatch in Non-Interleaved Input

**What goes wrong:**
Input uses buffer 0 frame count for both channels. If buffer 1 is shorter, the engine can read past it.

**Why it happens:**
Stereo non-interleaved buffers are usually same-sized in practice, so malformed/test cases are easy to overlook.

**How to avoid:**
Compute `b0Frames`, `b1Frames`, use `std::min`, then clamp.

**Warning signs:**
The output callback already uses min-buffer sizing, but the input callback does not.

**Phase to address:**
Phase 13: Runtime Correctness Blockers.

---

### Pitfall 5: Notary Scripts Only Fail on One Failure String

**What goes wrong:**
Auth failures, network errors, malformed output, future status strings, or other non-accepted states can be treated as success.

**Why it happens:**
Script captures `notarytool` output with `|| true` and greps only for `status: Invalid`.

**How to avoid:**
Capture return code, require return code 0 and `status: Accepted`, and print/fetch logs on failure when an id is available.

**Warning signs:**
`RESULT=$(xcrun notarytool submit ... 2>&1) || true` followed by only an `Invalid` grep.

**Phase to address:**
Phase 14: Release Automation Fail-Closed.

---

### Pitfall 6: Release Commands Emit Artifacts After Skipping Notarization

**What goes wrong:**
Maintainers can accidentally publish artifacts that were never notarized.

**Why it happens:**
The script is convenient for local development but named and documented like a release command.

**How to avoid:**
Make missing credentials a hard failure unless `APM44_ALLOW_UNNOTARIZED=1` is set.

**Warning signs:**
`release-all.sh` prints `SKIP notarization` and still lists release artifacts.

**Phase to address:**
Phase 14: Release Automation Fail-Closed.

---

### Pitfall 7: Public Security Posture Hidden in Implementation Details

**What goes wrong:**
`0666` shared memory can be read/written/DoSed by other local users/processes, but users do not see that assumption.

**Why it happens:**
The mode is technically useful because the HAL driver runs in `coreaudiod` and the daemon runs as the user; the trust model was encoded in code/docs only briefly.

**How to avoid:**
Add a public Security / Local IPC section describing the local-machine assumption and non-boundary. Track per-user/group/XPC options for later.

**Warning signs:**
Docs mention `0666` as a fact but do not explain threat implications.

**Phase to address:**
Phase 15: Public Distribution UX and Security Posture.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Keep misleading helper name | Avoids broad rename | Future realtime bug from trusting the name | Only with a temporary compatibility wrapper and TODO removed in same milestone. |
| Leave unused `WriteSilence` helper | No code movement | Dead helper has wrong byte assumptions and can be revived incorrectly | Not acceptable in realtime code. |
| Continue on missing notary credentials | Easier local builds | Public-release command loses meaning | Only with explicit opt-out variable and loud artifact labeling. |
| Pin actions by major tags in release workflow | Easy updates | Mutable action supply-chain risk near secrets | Accept only with documented trust decision and Dependabot/watch process. |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `notarytool` | Assume only `Invalid` means failure | Require `Accepted` plus successful exit status. |
| `stapler` | Staple after building final container only | Ensure final distributed container includes the exact signed/stapled inner artifacts where feasible, then staple final container. |
| GitHub Actions | Use tags in signing jobs without review | Pin critical actions to full SHA or record an explicit exception. |
| Core Audio virtual mode | Share cleanup path with physical input mode blindly | Check which IOProcs were actually created. |
| Shared memory | Treat local shm as private | Document local access and future hardening. |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Mutex in realtime metrics publisher | Rare callback jitter or priority inversion | Use lock-free/atomic publication | Under audio callback load. |
| Allocating JSON fallback in hot path | CLI/UI jitter less critical, but accidental RT use risky | Keep serialization outside realtime path; use bounded formatting | If metrics serialization moves into callback path. |
| Script tests require Apple credentials | CI cannot run blocker checks | Mock `xcrun`/PATH for parser tests | Every PR without notary profile. |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Undocumented `0666` shm | Local users/processes may read/write/DoS audio ring without users knowing | Public Local IPC threat model. |
| Mutable actions in signing workflow | Third-party action compromise near secrets/artifacts | Full-length SHA pins or documented exception. |
| Silent unsigned/unnotarized artifacts | Users hit Gatekeeper failures or lose trust | Fail release commands by default. |
| TSan runtime in production | Sanitizer runtime not designed for production security constraints | Use TSan only in test builds. |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Terminal-looking installer as primary path | Audio users may distrust or abandon install | Prefer signed PKG or make DMG/admin command explicit and polished. |
| DMG notarized but inner tickets unclear | Offline Gatekeeper/support confusion | Staple/validate inner artifacts and final container. |
| Docs overclaim security | User trust damage if assumptions surface later | Honest threat model with future hardening options. |

## "Looks Done But Isn't" Checklist

- [ ] **Metrics race:** Stress test passes but source still copies a plain shared snapshot - verify no concurrent non-atomic payload access remains.
- [ ] **JSON fix:** Normal src quality passes - verify intentionally long string truncation.
- [ ] **Output-start failure:** Physical input mode tested - verify virtual-device mode with null input IOProc.
- [ ] **Notary script:** Invalid status fails - verify auth error, network error, malformed output, and non-Accepted status.
- [ ] **Release-all:** Builds artifacts - verify missing notary credentials fail unless explicit override is set.
- [ ] **Workflow strictness:** Build step compiles - verify `verify-app-build.sh` is not masked.
- [ ] **Docs:** Install page exists - verify local IPC threat model and installer UX are visible to public users.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Metrics UB ships | HIGH | Replace publisher, add TSan proof, cut patch release, explain fix. |
| Bad notarization script ships unnotarized artifact | HIGH | Pull artifact, rebuild with strict script, replace release asset. |
| SHM threat model omitted | MEDIUM | Publish docs update and create tracked hardening issue. |
| Misleading helper name causes future bug | MEDIUM | Rename helper, update tests, add code-owner review for realtime changes. |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Metrics seqlock data race | Phase 13 | TSan-clean metrics test or equivalent source-level proof plus no plain payload copy. |
| JSON truncation overread | Phase 13 | Long `srcQuality` test returns safe output. |
| Core Audio failure path cleanup | Phase 13 | Virtual output-start failure test does not stop null input proc. |
| Non-interleaved input overread | Phase 13 | Mismatched buffer-size test uses min frame count. |
| Notary status masking | Phase 14 | Mocked `notarytool` failure matrix. |
| Unnotarized release command | Phase 14 | Missing-profile test fails unless override set. |
| Hidden shm threat model | Phase 15 | Public docs include Local IPC/security section. |
| Installer UX ambiguity | Phase 15 | Release docs and scripts agree on DMG/PKG artifact sequence. |
| Final validation drift | Phase 16 | Clean release validation command sequence recorded. |

## Sources

- Attached "Blockers before publishing" review, 2026-06-12.
- https://clang.llvm.org/docs/ThreadSanitizer.html
- https://developer.apple.com/developer-id/
- https://docs.github.com/en/actions/reference/security/secure-use
- Repo source scan, 2026-06-12.

---
*Pitfalls research for: APM44 Bridge v0.4 Public Release Blocker Closure*
*Researched: 2026-06-12*
