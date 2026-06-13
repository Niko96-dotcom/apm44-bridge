# Phase 25: App and Installer Reliability - Context

**Gathered:** 2026-06-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 25 hardens app-side helper refresh and metrics lifecycle state, then makes the generated DMG command installer replace the installed app bundle deterministically.

</domain>

<decisions>
## Implementation Decisions

### Device Catalog Refresh
- Avoid unread stderr pipes in `DeviceCatalog.refresh`.
- Preserve stdout parsing and existing preferred-device filtering behavior.
- Prefer discarding helper stderr over keeping a pipe that the app never consumes.
- Cover the contract with a Swift regression guard.

### Metrics Lifecycle Reset
- Reset `latestMetrics`, `lastMetricsAt`, and `metricsStale` together.
- Use a single helper so start and idle transitions cannot drift.
- Preserve existing connection phase behavior.
- Cover both start reset and idle transition reset with Swift unit tests.

### DMG Command Installer
- Replace any existing `/Applications/APM44 Bridge.app` before copy.
- Use privileged `ditto` for the app bundle copy.
- Set `/Applications/APM44 Bridge.app` ownership to `root:wheel`.
- Cover the generated command behavior in release-script tests.

### the agent's Discretion
The agent may use source-level release-script guards where running the full DMG build would require signing or macOS packaging tools not needed for this contract.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `App/APM44Bridge/DeviceCatalog.swift` owns `apm44-bridge --list-devices` invocation.
- `App/APM44Bridge/BridgeProcessManager.swift` owns metrics state, bridge start, and idle transitions.
- `tests/test_device_catalog.swift` and `tests/test_bridge_process_manager.swift` already cover Swift app behavior.
- `scripts/build-release-dmg.sh` writes the generated `Install APM44 Bridge.command`.
- `tests/test_release_scripts.sh` is the credential-free release-script regression suite.

### Established Patterns
- Swift tests use `@testable import APM44Bridge` and internal testing hooks on `BridgeProcessManager`.
- Release-script tests favor shell source/order guards and fake command wrappers over real signing/notarization.
- App lifecycle tests run without launching the real daemon by using `MockProcessLauncher`.

### Integration Points
- `DeviceCatalog.refresh(binaryURL:)` currently reads stdout before wait but assigns stderr to an unread pipe.
- `BridgeProcessManager.start` clears visible metrics but not the timestamp.
- `transitionToIdle` currently sets state and connection phase without clearing metrics.
- The DMG installer command currently copies the app with plain `cp -R`.

</code_context>

<specifics>
## Specific Ideas

Use `FileHandle.nullDevice` for helper stderr, introduce `resetMetricsState()`, add testing accessors for metrics timestamp state, and update the DMG command heredoc to `sudo rm -rf`, `sudo ditto`, and `sudo chown -R root:wheel`.

</specifics>

<deferred>
## Deferred Ideas

None - Phase 25 stays within app helper, metrics lifecycle, and DMG installer reliability.

</deferred>
