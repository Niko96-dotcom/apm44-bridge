# Feature Research

**Domain:** macOS audio bridge public-release hardening
**Researched:** 2026-06-12
**Confidence:** HIGH

## Feature Landscape

### Table Stakes (Users Expect These)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Race-free metrics publication | Public audio tools should not rely on undefined behavior in UI/CLI metrics | HIGH | Replace plain payload seqlock with atomic representation or safe buffering; include TSan proof. |
| Safe metrics JSON serialization | CLI JSON should not read past stack buffers on truncation | LOW | Guard `snprintf` result and add a long `srcQuality` regression test. |
| Safe Core Audio error paths | Error cleanup should not make an existing failure weirder | MEDIUM | Fix virtual-device output-start failure path and non-interleaved input min-frame sizing. |
| Fail-closed notarization | Public release automation must not treat non-Accepted output as success | MEDIUM | Check `notarytool` return code and require `status: Accepted`; fetch log on failure when an id is present. |
| Strict signing workflow | Release workflows near secrets/artifacts should not hide build failures | LOW | Remove `bash scripts/verify-app-build.sh || true`. |
| Explicit local IPC threat model | `0666` shared memory has local-machine security implications | LOW | Document that the ring is not an authentication or privilege boundary. |
| Blocker regression suite | Each published blocker should have a named test or script check | MEDIUM | Add tests for metrics, JSON truncation, callbacks, virtual failure cleanup, and release scripts. |

### Differentiators (Competitive Advantage)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Signed PKG installer direction | More professional UX for a HAL driver install than a Terminal-looking command | HIGH | Could be primary artifact or explicitly tracked release follow-up. |
| Inner artifact stapling before final container | Better offline/Gatekeeper behavior and clearer support story | MEDIUM | Adjust `release-all.sh` order if final DMG contains the app/driver after stapling. |
| SHA-pinned release workflows | Stronger supply-chain posture around signing/notarization | MEDIUM | Pin critical actions or document trusted tag decision. |
| Mocked notary/release shell tests | Prevents script regressions without needing Apple credentials in CI | MEDIUM | Use fake `xcrun` on PATH to simulate Accepted, Invalid, auth error, network error, and malformed output. |
| Clean release validation command sequence | Gives maintainers one boring, repeatable launch gate | MEDIUM | Combine secret scan, CI, app build, signing/notary checks, stapler, spctl. |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Keep `release-all.sh` permissive | Convenient for local dev | Easy to upload unnotarized artifacts by accident | Hard fail by default; explicit `APM44_ALLOW_UNNOTARIZED=1` for local-only builds. |
| Accept any notary output except `Invalid` | Avoids brittle parsing | Treats auth/network/malformed output as success | Require return code 0 and `status: Accepted`. |
| Leave `DropOldestThenPush` name | Avoids touching call sites/tests | Name contradicts drop-new behavior and invites future realtime bugs | Rename to `PushWithDropNewOnOverrun` or similar. |
| Hide `0666` shm mode | Avoids alarming users | Creates an implicit security overclaim | Document local IPC threat model honestly. |
| Broad DAW expansion in this milestone | Tempting public-facing feature | Distracts from release blockers | Defer Logic/Ableton matrix until release blockers are closed. |

## Feature Dependencies

```text
Race-free metrics representation
    -> TSan/metrics regression proof
    -> release validation confidence

Safe JSON + callback/error-path fixes
    -> blocker regression suite
    -> requirements traceability

Fail-closed release scripts
    -> signing workflow strictness
    -> DMG/PKG validation
    -> public release command sequence

IPC threat model
    -> release docs truthfulness
    -> installer UX decision
```

### Dependency Notes

- **Metrics representation requires tests first or alongside implementation:** a stress test alone is not enough if the source still has a standard C++ data race.
- **Release automation must be strict before final validation:** otherwise validation can pass against stale or unnotarized artifacts.
- **Distribution UX depends on notarization/stapling order:** the final artifact should contain the exact signed/stapled inner artifacts users receive.
- **Security docs depend on actual shm behavior:** if mode remains `0666`, docs must say what that permits and what it does not promise.

## MVP Definition

### Launch With (v0.4)

- [ ] Race-free metrics publication with TSan-oriented proof.
- [ ] Safe JSON truncation handling and test.
- [ ] Core Audio virtual-device output-start failure cleanup fix.
- [ ] Non-interleaved input callback min-buffer frame sizing fix.
- [ ] Notary DMG/PKG scripts fail unless submission is accepted.
- [ ] `release-all.sh` hard-fails without notary credentials unless explicitly opted out.
- [ ] Signing workflow fails on app-build failure.
- [ ] IPC threat model and release docs updated.
- [ ] Misleading overrun helper name fixed and unused silence helper removed or corrected.
- [ ] Final validation sequence recorded.

### Add After Validation (v0.4.x)

- [ ] Signed PKG becomes primary public installer if certificates and UX are validated.
- [ ] Workflow SHA pins are maintained by Dependabot or documented manual process.
- [ ] More complete shell-test framework for release scripts.

### Future Consideration (v0.5+)

- [ ] Logic/Ableton compatibility matrix.
- [ ] Support bundle export.
- [ ] Per-user or tighter-permission shared-memory creation strategy.
- [ ] Privileged helper or XPC-mediated IPC setup.

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Metrics race fix | HIGH | HIGH | P1 |
| JSON truncation fix | HIGH | LOW | P1 |
| Core Audio failure path fixes | HIGH | MEDIUM | P1 |
| Notary/signing fail-closed automation | HIGH | MEDIUM | P1 |
| IPC threat model docs | HIGH | LOW | P1 |
| Helper rename/dead code cleanup | MEDIUM | LOW | P2 |
| DMG/PKG distribution UX decision | HIGH | MEDIUM/HIGH | P2 |
| SHA-pinned actions | MEDIUM | MEDIUM | P2 |
| Logic/Ableton matrix | MEDIUM | HIGH | P3 |

## Competitor Feature Analysis

Not applicable as a feature-comparison exercise. For this milestone, the benchmark is not competitor feature breadth; it is whether the release behaves like a serious macOS audio utility:

| Release expectation | Professional baseline | Our Approach |
|---------------------|-----------------------|--------------|
| Driver install | Signed/notarized installer or extremely clear admin install path | Decide PKG direction and tighten docs/automation. |
| Gatekeeper trust | Developer ID signing and notarization with stapled tickets | Fail release scripts unless `Accepted` and stapler validation succeed. |
| CI trust | Release workflow cannot hide app build failures | Remove `|| true`; pin critical actions or document exception. |
| Local IPC | Honest threat model for local shared memory | Document `0666` mode and future hardening options. |

## Sources

- Attached "Blockers before publishing" review, 2026-06-12.
- https://developer.apple.com/developer-id/ - Developer ID, notarytool, stapler, supported container types.
- https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution - installer package signing.
- https://docs.github.com/en/actions/reference/security/secure-use - action SHA pinning and workflow security.
- https://clang.llvm.org/docs/ThreadSanitizer.html - TSan data-race detection and supported platforms.
- Repo source scan: `scripts/notarize-release-dmg.sh`, `scripts/release-all.sh`, `.github/workflows/sign-notarize.yml`, `BridgeDaemon/src/engine/*`.

---
*Feature research for: APM44 Bridge v0.4 Public Release Blocker Closure*
*Researched: 2026-06-12*
