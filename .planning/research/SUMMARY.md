# Project Research Summary

**Project:** APM44 Bridge
**Domain:** Open-source macOS audio utility release hygiene
**Researched:** 2026-06-28
**Confidence:** HIGH

## Executive Summary

APM44 Bridge is already public on GitHub, so v1.1 is not about flipping a
visibility switch. It is about making the public project feel professionally
safe: a user can quit the app from the UI, docs tell the exact truth, release
artifacts are signed/notarized and traceable, and the latest GitHub release is
only promoted after evidence is collected.

The recommended approach is conservative. Add the Quit control inside the
existing menu bar app and delegate shutdown to the lifecycle owner. Then perform
a public-surface and release-gate pass using repo-native scripts, current
GitHub state, and Apple distribution checks. Do not introduce new frameworks,
new release paths, or broad compatibility claims.

## Key Findings

### Recommended Stack

- Existing Swift/AppKit app: add the Quit control without changing UI stack.
- Existing process lifecycle code: stop app-owned bridge work before app exit.
- Existing release scripts: strengthen and use current gates rather than adding
  parallel release procedures.
- GitHub Releases: remain the public artifact of record.
- Developer ID signing/notarization: remain required for public macOS trust.

### Expected Features

**Must have:**
- Visible app Quit control.
- Graceful quit semantics and regression/manual proof.
- Public docs and metadata aligned with current release truth.
- Secret/private-artifact review.
- Full local CI, installed-sync proof, artifact validation, and latest GitHub
  release verification.

**Defer:**
- Signed PKG promotion.
- Broad DAW compatibility claims.
- Support bundle export.

### Architecture Approach

Keep the product architecture unchanged. v1.1 should touch the menu UI, process
lifecycle seam, public docs, release scripts/checklists, and GitHub release
state. It should not alter realtime audio architecture unless a release gate
finds a blocker.

### Critical Pitfalls

1. **Quit bypasses cleanup** - avoid by routing through existing lifecycle owner.
2. **Public claims outrun evidence** - avoid by tying docs and release notes to
   exact validation proof.
3. **Secret/private leakage** - avoid by scanning tracked files, release assets,
   and public-facing docs.
4. **Stale latest release** - avoid by verifying GitHub latest release after
   publication.

## Implications for Roadmap

### Phase 42: App Quit Control

Implement the visible quit affordance and prove graceful app shutdown.

### Phase 43: Public Documentation and Repository Surface

Audit and update README, docs, metadata, templates, license/security/contribution
posture, and public claims.

### Phase 44: Security and Release Hygiene Gate

Run secret/private-artifact checks, release-script gates, CI, installed sync,
artifact signing/notary/stapling/Gatekeeper validation, and profile/repo safety
checks.

### Phase 45: Latest GitHub Release Publication Closure

Publish or update the latest GitHub release only after Phase 44 passes, then
verify assets, checksums, notes, latest URL, and caveats.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Existing stack is sufficient. |
| Features | HIGH | User scope is clear and narrow. |
| Architecture | HIGH | Release confidence should layer on existing lifecycle and scripts. |
| Pitfalls | HIGH | Prior milestones already identified installed-sync, secrets, and release drift as real risks. |

## Sources

### Primary

- GitHub Docs: repository READMEs, security policies, secret scanning, and
  release management.
- Apple Developer Documentation: notarizing and distributing macOS software
  outside the Mac App Store.
- Open Source Guides: open-source project README, licensing, contribution, and
  community expectations.
- Local checks on 2026-06-28: repo visibility is public; GitHub latest release is
  `v0.10.0`; `.planning/` remains ignored; working tree has unrelated modified
  source/script/test files.

---
*Research completed: 2026-06-28*
*Ready for roadmap: yes*
