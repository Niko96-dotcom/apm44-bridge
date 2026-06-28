# Stack Research

**Domain:** Open-source macOS audio utility release hygiene
**Researched:** 2026-06-28
**Confidence:** HIGH

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Swift/AppKit menu bar app | Existing project stack | Add visible Quit control | Matches current app surface; no new UI framework needed. |
| C++/Core Audio HAL driver and daemon | Existing project stack | Preserve audio bridge behavior | Release confidence depends on not destabilizing the validated realtime path. |
| GitHub Releases | Current service | Publish latest public artifact | Repo already uses GitHub Releases and has a current latest release. |
| Developer ID signing and Apple notarization | Current Apple platform requirements | macOS distribution outside the App Store | Existing release flow already signs, notarizes, staples, and validates DMG artifacts. |

### Supporting Tools

| Tool | Purpose | When to Use |
|------|---------|-------------|
| `scripts/ci.sh` | Full local regression gate | Before claiming implementation or release readiness. |
| `scripts/check-secrets.sh` | Repository secret hygiene | Before any public release or push. |
| `scripts/verify-installed-sync.sh` | App/helper/driver identity proof | Before claiming the running installed build is current. |
| `scripts/verify-hal-driver.sh` | Installed HAL driver proof | After installing/reloading the current driver. |
| `apm44-bridge --shm-status` | Live ring/helper/driver status | After the HAL ring is live. |
| `gh release` | Inspect and publish GitHub release state | Final publication and latest-release verification. |

## Integration Notes

- No new package manager or dependency should be introduced for the Quit control.
- Release work should strengthen existing scripts rather than inventing a second
  release path.
- Public docs should remain user-facing; `.planning/` stays local unless
  explicitly force-added for internal GSD continuity.

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| A second ad-hoc release checklist | Diverges from validated scripts and docs | Extend repo-native scripts/docs and evidence files. |
| UI quit behavior that kills `coreaudiod` or removes the driver | Dangerous and surprising for users | Stop only app-owned work and exit the menu bar app. |
| Publishing from a dirty or unverified tree | Makes release provenance ambiguous | Require clean release diff, CI, secret scan, artifact checks, and explicit caveats. |
| Public claims of "flawless" without evidence | Overclaims can embarrass and mislead | Publish exact verified gates and known caveats. |

## Sources

- GitHub Docs: READMEs, security policies, secret scanning, and releases.
- Apple Developer Documentation: notarization and distributing macOS software
  outside the Mac App Store.
- Open Source Guides: project README, licensing, contribution, and community
  expectations.
- Local repo evidence: `scripts/ci.sh`, `scripts/check-secrets.sh`,
  `scripts/verify-installed-sync.sh`, `scripts/verify-hal-driver.sh`,
  `docs/release-validation.md`, GitHub release list.

---
*Stack research for: APM44 Bridge v1.1*
*Researched: 2026-06-28*
