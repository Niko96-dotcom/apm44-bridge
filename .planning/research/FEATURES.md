# Feature Research

**Domain:** Open-source macOS audio utility release hygiene
**Researched:** 2026-06-28
**Confidence:** HIGH

## Feature Landscape

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Visible Quit control | Menu bar apps are expected to expose a clear exit path. | LOW | Should reuse existing process-stop lifecycle. |
| Graceful app shutdown | Users should not need Activity Monitor or force quit. | MEDIUM | Must avoid deleting HAL driver or corrupting live audio state. |
| Accurate README and release docs | Public users judge safety from docs before installing audio drivers. | MEDIUM | Must match current artifact names, version, install path, and caveats. |
| License, security, contribution posture | Open-source repos should make reuse and vulnerability reporting clear. | LOW | Verify files exist and are not stale or overbroad. |
| Secret and private-artifact scan | Public release should not expose credentials or planning/private files. | MEDIUM | Include current tree, tracked history where practical, and shell-history caveat awareness. |
| Latest release verification | Users use the latest GitHub release as the product truth. | MEDIUM | Current latest is `v0.10.0` as of 2026-06-28 local check. |
| Signed/notarized artifact evidence | macOS users need Gatekeeper-safe distribution. | HIGH | Keep DMG-first; PKG remains future unless validated. |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Release evidence document | Professional public confidence without vague claims. | MEDIUM | Link commands, checksums, notarization, Gatekeeper, and caveats. |
| Installed-system proof | Separates "build passed" from "the running driver is current." | HIGH | Requires local install/reload and optional target hardware smoke. |
| Public profile/repo metadata audit | Reduces embarrassment risk beyond code correctness. | LOW | Check description, homepage, topics, issue templates, and release notes. |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| "Quit" that uninstalls the driver | Feels like fully closing everything | Surprising, privileged, and risky during audio sessions | Quit app only; keep uninstall separate and explicit. |
| Automatic GitHub publication before proof | Saves time | Can publish broken or private artifacts | Publish only after release gate passes. |
| Marketing-heavy docs | Looks polished | Can hide caveats and reduce trust | Plain, exact, user-facing release truth. |
| Broad DAW compatibility claims | Attractive for public profile | Not validated | Keep Cubase 15 and USB-C AirPods Max as validation anchor. |

## MVP Definition

### Launch With

- [ ] Quit control implemented and tested.
- [ ] Docs and metadata audited and updated.
- [ ] Secret/private-artifact scan completed.
- [ ] Full local CI and installed-sync gate completed.
- [ ] Signed/notarized release artifact evidence captured or explicit blocker
  recorded.
- [ ] Latest GitHub release state verified after publication.

### Add After Validation

- [ ] Signed PKG installer promotion, only after Developer ID Installer path is
  intentionally validated.
- [ ] Broader DAW compatibility matrix.
- [ ] Support bundle export.

## Sources

- GitHub Docs: releases, security policy, secret scanning, repository metadata.
- Apple Developer Documentation: Developer ID distribution and notarization.
- Open Source Guides: README, license, contribution, and community expectations.
- Local repository and GitHub CLI checks on 2026-06-28.

---
*Feature research for: APM44 Bridge v1.1*
*Researched: 2026-06-28*
