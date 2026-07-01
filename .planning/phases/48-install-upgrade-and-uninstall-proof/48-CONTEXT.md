# Phase 48 Context: Install, Upgrade, and Uninstall Proof

## Goal

Prove the final mounted DMG/PKG path is the install source and provide guarded install, upgrade, installed-sync, HAL, and uninstall proof commands.

## Local Constraint

`sudo -n true` failed on this machine with `sudo: a password is required`.
The autonomous run must not hang on an interactive password prompt, so Phase 48
will add fail-closed scripts and non-destructive proof by default. Destructive
install/uninstall smoke requires explicit opt-in and passwordless/admin sudo in
the operator environment.

## Recommended Scope

1. Add `scripts/verify-final-install-artifact.sh`:
   - mounts or accepts a mounted final DMG,
   - proves the top-level PKG is the install source,
   - validates package signature/notary/Gatekeeper through existing gates,
   - runs destructive install smoke only with `APM44_RUN_FINAL_INSTALL_SMOKE=1`,
   - fails before prompting if `sudo -n true` is unavailable.
2. Add `scripts/uninstall-apm44.sh`:
   - dry-run by default,
   - `--yes` required for destructive removal,
   - removes app, HAL driver, and package receipt when explicitly approved.
3. Update tests and release validation docs.

