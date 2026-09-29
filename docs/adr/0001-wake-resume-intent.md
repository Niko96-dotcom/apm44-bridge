# ADR-0001: Keep the resume intent across sleep, wake and hotplug interleavings

- **Status:** Accepted, implemented (updated 2026-09-29; originally Proposed 2026-09-27). Decision items 1-4 shipped in #46 (`10af56f`); action item 5 stays open. See "Implementation status".
- **Date:** 2026-09-27
- **Deciders:** Niko (owner)
- **Source:** tech-debt item #3 and test gap T16 in the 2026-09-27 audit (`.audit/tech-debt.md`, `.audit/test-plan.md`), both at `30707e6`.
- **Evidence rule:** every `file:line` below is at `30707e6`, the revision the decision was written against. Line numbers in the Context, Decision and Consequences sections are therefore historical; the "Implementation status" section names symbols and tests at the current revision.

## Context

`BridgeProcessManager` is a `@MainActor` class. Its sleep, wake and hotplug handlers are `async` and suspend at several points. Each event starts its own unstructured task:

- Hotplug: `App/APM44Bridge/APM44BridgeApp.swift:200-204` wraps `manager.handleHotplug()` in `Task { @MainActor in … }`.
- Sleep and wake: `APM44BridgeApp.swift:205-216` do the same for `handleSystemWillSleep()` and `handleSystemDidWake()`.
- The monitors deliver on the main queue (`SystemLifecycleMonitor.swift:27-43`). Hotplug is debounced by 1 s before it fires (`HotplugMonitor.swift:98-114`).

Main-actor isolation keeps each synchronous stretch atomic, but the handlers interleave at every `await`. Two manager flags carry the "resume" intent across those suspensions:

- `wasRunningBeforeDisconnect` (`BridgeProcessManager.swift:84`)
- `resumeAfterSystemWake` (`:92`)

A third, `settings.resumeAfterUpdateRequestedAt` (`BridgeSettings.swift:40`), belongs to the update flow. Sleep and wake never read it.

`refreshDevices()` bumps a generation counter (`:237-238`) and returns `false` in three different cases:

1. The helper binary is missing (`:241-245`).
2. A newer refresh has started (`:251-252`). This check runs **before** that newer refresh has applied its list (`:254`).
3. Listing threw (`:256-261`). This also happens when the generation has already moved on.

### How a wake resume is lost

1. **A superseded wake refresh looks like a failure.** Sleep records `resumeAfterSystemWake` (`:637`) and clears `wasRunningBeforeDisconnect` (`:641`). Wake copies and clears the resume flag before it awaits anything (`:652-653`), then awaits `refreshDevices()` (`:654`). If another refresh starts before wake's list comes back, wake gets `false` and parks the bridge in `.reconnecting` with the "waiting for devices" banner (`:655-659`). It does not set `wasRunningBeforeDisconnect`, unlike the "output unavailable" park at `:668`.

   A later hotplug restarts a `.reconnecting` bridge only when `devicePresent && wasRunningBeforeDisconnect` (`:715-716`). Otherwise it returns (`:723`). The bridge stays stopped until the user clicks Start.

   Callers that can supersede the wake refresh:
   - the debounced hotplug at wake, when USB audio re-enumerates (`:680`);
   - the menu's `.task` refresh (`MenuContentView.swift:80-82`). This one only counts if `MenuBarExtra` runs the task at that moment, which this repo cannot show (uncertain).

2. **Wake during an unfinished stop.** A stop can take up to two 5 s waits (`:860`, `:868`). If wake reaches `start()` (`:675`) while the state is still `.stopping`, `start()` returns without doing anything (`:367-370`). The resume flag was already consumed at `:653`, and this branch sets no other flag, so nothing retries. If wake's refresh fails instead, it writes `.reconnecting` over `.stopping` (`:657`). The pending termination then misses the `.stopping` branch (`:997`) and is classified as an exit instead (`:1001-1004`).

3. **Sleep during a hotplug or settings restart.** Hotplug and restart both set `.stopping` synchronously in `initiateStop` (`:552`) before they suspend. A sleep that lands in that window takes the `default` branch, stores `resumeAfterSystemWake = false`, and returns (`:631-638`). The restart then calls `start()` (`:626`), so the daemon relaunches as the Mac goes to sleep, and wake has no resume intent. This path is rarer (the window is the stop itself), and it is not fully fixed by the decision below. See Consequences.

The existing test runs sleep and then wake strictly in sequence (`tests/test_bridge_process_manager.swift:486-511`), so none of these orders are exercised. The fake launcher delivers termination only when a test calls `fireTermination` (`test_bridge_process_manager.swift:46-53`), so a test can hold the manager in `.stopping`. The fake device source returns its list at once (`:99-103`). A test that needs a superseded refresh must therefore gate `listDevices`; otherwise the order depends on scheduling and the test can pass on `30707e6`.

### Constraints

- This is app-side Swift only. The daemon, the driver and the real-time rules in `CONTRIBUTING.md` are not involved.
- The Test Rules apply: inject through `init`, and add no new `…ForTesting` members or other API that only tests call (`CONTRIBUTING.md`, "Test Rules"). `setStateForTesting` (`:212`) is existing debt and must not gain new uses.
- The settings-restart coalescer (`restartTask`/`pendingRestartReason`, `:82-83`, `:562-591`, `:903-911`) has tests (`test_bridge_process_manager.swift:997-1024`, `:1241-1294`) and stays as it is.
- The fix is one reviewable PR that `scripts/ci.sh` and the unit tests can prove on the development Mac without a real sleep or USB hardware.

## Decision

Adopt **Option C**: keep the current scheduling and make the resume intent survive every `await` in the wake path. Concretely:

1. **Superseded refreshes join the winner.** `refreshDevices()` keeps the newest refresh as a task. A caller whose refresh is superseded awaits that task and returns its result instead of `false`. The missing-binary and thrown-error cases stay failures. This also fixes hotplug's `guard` at `:680`, which today abandons a superseded hotplug.
2. **Wake waits out an in-flight stop.** Before it refreshes, wake awaits termination when the state is `.stopping`, using the existing `waitForTermination` (`:733-756`), so its `start()` can no longer hit `:370`. If the wait times out, wake parks as in step 3.
3. **Every wake park keeps the intent.** The park at `:655-659` sets `wasRunningBeforeDisconnect = true`, as `:668` already does, so the next hotplug finishes the resume (`:715-716`).
4. **A user stop cancels a pending wake resume.** `initiateUserStop` (`:521-537`) also clears `resumeAfterSystemWake`. Wake reads the flag again after its awaits instead of relying only on the copy taken at `:652`.

## Options considered

### Option A: a serial lifecycle event queue

`BridgeProcessManager` owns an `AsyncStream` of `.willSleep`, `.didWake` and `.hotplug` with one consumer that awaits each handler before taking the next. The app callbacks post events synchronously.

| Dimension | Assessment |
|---|---|
| Complexity | Medium: a queue type plus a consumer task, and three call sites. It still needs fixes 1 and 3 from Option C, because the menu refresh and user actions stay outside the queue. |
| Risk | Medium. A queued handler must never await anything that waits on the queue. `restart(reason:)` waits on `restartTask` (`:562-584`) and is safe today, but the rule is easy to break. |
| Testability | Weak under the Test Rules. Awaiting one event needs an `async post` that no production code calls. Without it, tests fall back to polling. |
| Coverage | Partial. It serializes sleep, wake and hotplug among themselves, but not user `start`/`stop` (`:367`, `:509`), settings restarts (`MenuControlCard.swift:106,161,194`), the auto-retry task (`:964-969`), the stability task (`:937-944`) or termination delivery (`:468-471`). |

**Pros:** it fixes path 3 for the hotplug case, because sleep waits for an in-flight hotplug restart and then stops the relaunched daemon. It rules out orderings among the three events that nobody has listed.

**Cons:** a queued sleep waits behind an in-flight hotplug restart, and the system does not wait for the handler (`SystemLifecycleMonitor.swift:32-34`). The Mac can therefore fall asleep with the relaunched daemon still running, which is the same end state as path 3, only delayed. Settings restarts are still unordered against sleep.

### Option B: a desired-state reconciler

Replace the flags and per-event branches with one model: user intent (`wantsRunning`) plus suspension reasons (`systemAsleep`, `outputMissing`, `updateInstalling`). Every event, termination and user action updates the model and calls one idempotent `reconcile()`.

| Dimension | Assessment |
|---|---|
| Complexity | High. It rewrites `start`, `stop`, `restart`, the three handlers, auto-retry (`:948-972`) and `handleTermination` (`:987`). |
| Risk | High before a release. Many of the 53 tests in `tests/test_bridge_process_manager.swift` assert intermediate states that would change. |
| Testability | Highest in the end: `reconcile` can be a pure function tested from a table. |
| Reversibility | Low. It is a new core. |

**Pros:** it removes the bug class for every trigger, including path 3, tech-debt #13 (the resume-after-update flag outliving a cancel) and T14 (a settings change during a user stop).

**Cons:** it is too large for one reviewable PR, and it re-opens code that PRs #36–#40 only just stabilized.

### Option C: keep scheduling, make the intent explicit (chosen)

The four fixes listed under Decision.

| Dimension | Assessment |
|---|---|
| Complexity | Low: about 40 lines in `BridgeProcessManager.swift`, plus a gate in the test fake. |
| Risk | Low. There is no new scheduling and no new public API. |
| Testability | Good. Tests call the existing handlers directly and control the order with `fireTermination` and a gated `listDevices`. |
| Coverage | It fixes paths 1 and 2. Path 3 remains (see Consequences). |

**Pros:** smallest change that fixes the two likely paths. Every fix can be shown failing on `30707e6`. It adds no test-only API.

**Cons:** the handlers still interleave, so any future handler change has to be checked against the others by hand. Path 3 stays open.

## Trade-off analysis

- **C versus A.** A looks like it solves the bug class, but it covers only three of the eight concurrent entry points. It still needs C's fixes 1 and 3, and it can only be tested through a test-only overload or polling. Its one extra win (path 3 for hotplug) is undercut, because the system does not wait for the queued sleep. C fixes the likely paths with less code and deterministic tests.
- **C versus B.** B is the right end state if more intent flags keep appearing. C does not block B: its fixes (refresh join, explicit intent) carry over into a reconciler.
- **The remaining risk** is path 3 and any interleaving not listed here. C accepts that risk for now and writes down when to revisit it.

## Consequences

- **Easier:** a superseded refresh is never a failure, in wake, hotplug or the menu. Wake after a slow stop resumes. The resume intent is visible in one flag through `.reconnecting`.
- **Harder:** nothing new, but handlers still interleave. Reviews of lifecycle changes must keep checking suspension points.
- **Tests (each must fail on `30707e6`):**
  - **T16, direct calls.** `start()`, then `handleSystemWillSleep()` held in `.stopping` (no `fireTermination` yet), then `handleSystemDidWake()` concurrently, then fire the termination. The run ends `.running` with `makeCount == 2`.
  - **Superseded wake.** Gate `FakeBridgeDeviceSource.listDevices` so wake's refresh blocks inside `Task.detached` (`:248-250`), start a second `refreshDevices()`, then release both. The run ends `.running`, not `.reconnecting`.
  - **User stop during wake.** Wake's refresh is gated, the user calls `stop()`, then the gate is released. The run ends `.idle` with no new launch.
  - The existing sleep, wake and hotplug tests (`test_bridge_process_manager.swift:486-530`, `:601-670`) pass unchanged.
- **Still open:** path 3 (sleep during a hotplug or settings restart), T14 and T15 (settings restarts against a user stop or a device change), and #13. If fixing those needs more intent flags, take that as the signal to start Option B instead.

## Action items

Checked against the code and tests at `844be44` on 2026-09-29.

1. [x] Make `refreshDevices()` join the newest refresh when superseded, and keep missing-binary and thrown-error as failures. `BridgeProcessManager.refreshDevices` keeps `newestDeviceRefresh` and loops on it; a missing binary and a thrown listing return `false`.
2. [x] Have wake await an in-flight stop before refreshing, and set `wasRunningBeforeDisconnect` on every wake park. `handleSystemDidWake` waits with `waitForTermination(timeout: stopTimeout * 2 + 1)` while the sleep stop is in flight; `parkAfterWake` sets the flag for every park it makes.
3. [x] Clear `resumeAfterSystemWake` on a user stop, and re-read it in wake after its awaits. `initiateUserStop` clears it; wake copies and clears it only after its awaits.
4. [x] Add a `listDevices` gate to `FakeBridgeDeviceSource`, plus the three tests above, and show each one failing on `30707e6`. `gateNextListing()` / `ListDevicesGate` in `tests/test_bridge_process_manager.swift`. The #46 description records each test failing on `main` at `6df0350` (the base of that PR, not `30707e6`) and failing under a matching mutation.
5. [ ] Later: decide on Option B when path 3, T14/T15 or #13 are picked up. Still deferred; see "Implementation status" for which of those remain.

## Implementation status (2026-09-29)

The original Context, Decision and Options above are unchanged. Nothing here changes the decision (Option C).

**Decision items, as implemented** (`App/APM44Bridge/BridgeProcessManager.swift`, tests in `tests/test_bridge_process_manager.swift`):

| Decision item | Symbols | Tests |
|---|---|---|
| 1. Superseded refreshes join the winner | `refreshDevices`, `newestDeviceRefresh`; `handleHotplug` returns when a newer hotplug joined the same refresh (`hotplugEventGeneration`) | `testWakeWhoseRefreshIsSupersededByHotplugStillResumes`, `testOverlappingHotplugsRestartRunningBridgeOnce` |
| 2. Wake waits out an in-flight stop | `handleSystemDidWake`, `waitForTermination` | `testWakeDuringUnfinishedSleepStopResumesBridge` (T16), `testWakeParksWhenSleepStopNeverFinishes` |
| 3. Every wake park keeps the intent | `parkAfterWake` | the two wake tests above, `testLateExitAfterWakeParkResumesWhenOutputPresent` |
| 4. A user stop cancels a pending wake resume | `initiateUserStop`, `handleSystemDidWake` | `testUserStopDuringWakeCancelsResume` |

**Follow-ups after the ADR**, all in the same manager:

- #53 (`f721461`): `systemSleepGeneration`. A wake whose refresh a newer sleep overtook keeps the intent for the next wake (`testSecondSleepDuringWakeRefreshKeepsResumeIntent`, `testSleepDuringIdleWakeRefreshDefersResumeToNextWake`).
- #54 (`f6ab66b`): `waitForTermination` uses per-waiter timers that resume with failure, so the stop wait can time out. The pre-existing timeout bug that #46 recorded as making wake's "stop unfinished" park unreachable is fixed (`testStopEscalatesToSigkillWhenHelperIgnoresSigterm`, `testWakeParksWhenSleepStopNeverFinishes`).
- `c569760` (audit B-series): `performRestart` captures `systemSleepGeneration` and `userStopGeneration` before its stop wait. A sleep during a restart defers the relaunch to the wake, and `handleSystemWillSleep` keeps the intent while `restartTask` is set. This addresses path 3 for settings and hotplug restarts (`testSleepDuringSettingsRestartDefersRelaunchToWake`, `testUserStopDuringSettingsRestartCancelsRelaunch`). Tech-debt #13, the resume-after-update flag outliving a cancel, is covered by `testUserStopRevokesPendingUpdateResume` and `testAbandonedUpdateInstallRevokesResume`.
- `fade2f0` (architecture audit A001): the hotplug output-loss stop settles through `reconcileAfterOutputLossStop`, with the same generation guards, instead of parking from the pre-wait decision.

**Still open:** T14 (a settings change during a user stop) and T15 (a device-change restart together with a settings restart) have no test named for them. Path 3 was verified only for the restart flows above, not for every trigger; no test was found for a sleep that lands between a hotplug restart's synchronous `.stopping` and its relaunch other than the settings-restart case. Action item 5 (Option B) is deferred until more intent flags appear. Nothing here was checked against real sleep or USB hardware.

## Review record

An independent Grok Build 4.7 review (Subscription Squad, read-only, 806 s) rejected the first draft, which recommended Option A. It confirmed path 1, corrected path 2 and path 3, and pointed out that an `async post` would be a test-only member, that a superseded refresh returns before the winner applies its list, and that an ungated fake lets the superseded-wake test pass on `30707e6`. This version adopts those corrections.
