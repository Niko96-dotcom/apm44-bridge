# Pitfalls Research

**Domain:** Open-source macOS audio utility release hygiene
**Researched:** 2026-06-28
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: Quit control bypasses lifecycle cleanup

**What goes wrong:** The app exits while an app-owned daemon or metrics state is
left in an ambiguous state.

**Why it happens:** UI code calls a direct terminate path instead of the existing
process-manager stop path.

**How to avoid:** Route Quit through the lifecycle owner, reuse existing stop and
idle-reset behavior, and test the transition.

**Warning signs:** New UI code kills processes directly or touches HAL driver
state.

**Phase to address:** Phase 42.

### Pitfall 2: Public release claims outrun evidence

**What goes wrong:** README or release notes imply broader safety,
compatibility, or freshness than the gates prove.

**Why it happens:** Docs are polished separately from release validation.

**How to avoid:** Link docs to exact release artifacts, checksums, validation
commands, and caveats.

**Warning signs:** "Latest", "stable", or compatibility claims without a
specific version and validation date.

**Phase to address:** Phases 43 and 45.

### Pitfall 3: Secret or private planning leakage

**What goes wrong:** Credentials, shell-history traces, `.planning`, internal
agent files, or private notes become public.

**Why it happens:** Release work focuses on artifacts and misses public surface
review.

**How to avoid:** Run repo secret scans, inspect tracked files, inspect release
assets, and keep `.planning/` ignored unless intentionally force-added.

**Warning signs:** Public tree contains planning files, local paths, tokens,
notary credentials, or maintainer-only instructions.

**Phase to address:** Phase 44.

### Pitfall 4: GitHub latest release is stale or mismatched

**What goes wrong:** Users download an older or incorrectly described artifact.

**Why it happens:** Tags, GitHub release names, release notes, and docs drift.

**How to avoid:** Verify `gh release list`, tags, checksums, asset names, and
README links after publication.

**Warning signs:** README and GitHub latest release disagree on version or
artifact name.

**Phase to address:** Phase 45.

## Looks Done But Is Not Checklist

- [ ] **Quit UI:** Button exists, but does not go through graceful stop.
- [ ] **Docs:** README looks polished, but version/artifact names are stale.
- [ ] **Security:** Current tree scans clean, but release assets or history were
  not checked.
- [ ] **Release:** DMG exists, but signing/notary/stapling/Gatekeeper evidence
  is missing.
- [ ] **Installed proof:** CI passes, but installed helper/driver build IDs do
  not match the release artifact.
- [ ] **GitHub:** Tag exists, but latest release page/assets were not verified.

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Lifecycle bypass | Phase 42 | Swift tests/manual app quit proof. |
| Overclaiming docs | Phase 43 | Public docs diff review and release-doc consistency checks. |
| Secret/private leakage | Phase 44 | Secret scan, tracked-file review, release-asset review. |
| Stale latest release | Phase 45 | `gh release list`, asset checksums, README/latest URL check. |

## Sources

- GitHub Docs: public repository profile files, releases, security policies, and
  secret scanning.
- Apple Developer Documentation: notarization, stapling, and Gatekeeper
  validation expectations.
- Local APM44 Bridge release history and prior secret-hygiene notes.

---
*Pitfalls research for: APM44 Bridge v1.1*
*Researched: 2026-06-28*
