# Phase 3: Menu Bar Application - Context

**Gathered:** 2026-06-01
**Status:** Ready for planning
**Mode:** Smart discuss (yolo — recommended answers accepted)

<domain>
## Phase Boundary

SwiftUI menu bar app to start/stop `apm44-bridge`, select output device, choose latency mode (Low/Balanced/Safe) and SRC quality tier, show buffer fill/glitch meters, handle AirPods hotplug, and report honest round-trip latency. Communicate with daemon via XPC or subprocess + JSON status file (MVP: subprocess spawn acceptable). No HAL driver work in this phase.

</domain>

<decisions>
## Implementation Decisions

### App shell
- macOS 14+ target; `MenuBarExtra` with icon states: running (green tint), stopped (gray), error (red)
- App bundle `APM44Bridge.app` built via Xcode project under `App/` or SwiftPM executable + bundle script
- Launch daemon as child process with pipes for stdout; parse metrics JSON lines on background queue

### Control surface
- Latency presets map to `--target-fill-ms` and `--src-quality` on daemon CLI:
  - Low: 8 ms + SRC_SINC_MEDIUM
  - Balanced (default): 15 ms + SRC_SINC_MEDIUM
  - Safe: 30 ms + SRC_SINC_BEST
- Device picker lists output devices (filter AirPods/USB); persist last selection in UserDefaults
- Start/Stop toggles bridge; on hotplug, restart bridge if was running

### Meters & honesty
- Poll daemon metrics every 500 ms: fill ms, xruns, effective ratio, estimated RT latency (buffer + SRC group delay documented constant)
- Never claim zero latency; show "~X ms monitoring latency" string
- Glitch indicator when xrun count increases

### Hotplug
- `NSNotification` / Core Audio property listener on background thread; debounce 1s; restart bridge

### Claude's Discretion
- XPC vs subprocess for MVP (prefer subprocess + JSON for speed)
- Exact SwiftUI layout

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `apm44-bridge` CLI with Phase 2 flags
- C++ metrics logging hooks in BridgeEngine (extend if needed for JSON status)

### Integration Points
- Spawn `./build/BridgeDaemon/apm44-bridge` with args from UI
- Future: XPC service in Phase 4/5

</code_context>

<specifics>
## Specific Ideas

- ROADMAP UI hint: yes — follow Apple HIG for menu bar utilities
- APP-01 through APP-05, QA-03 requirements

</specifics>

<deferred>
## Deferred Ideas

- HAL virtual device (Phase 4)
- Notarization installer (Phase 5)

</deferred>
