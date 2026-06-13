# Pitfalls Research

**Domain:** APM44 Bridge public-release safety fixes
**Researched:** 2026-06-13
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: Rollover Exception Becomes Universal Mismatch Acceptance

**What goes wrong:** Left and right mono lanes with unrelated timestamps can be
paired into stereo output after the search-ahead logic finds no match.

**Why it happens:** `flushPendingLanes()` falls through to `pushLanePair()` even
after detecting a mismatch. The rollover test makes this appear intentional, but
the implementation does not distinguish rollover from arbitrary mismatch.

**How to avoid:** Store `zeroTimestamp`, add `SameLogicalLaneBlock()`, and drop
the older logical lane when no exact queued match or permitted rollover relation
exists.

**Regression:** left@100/right@300 must not push paired stereo; left@300/right@300
must pair; the rollover case must pair only through the named predicate.

---

### Pitfall 2: Lifecycle Flag Exists But Hot Path Ignores It

**What goes wrong:** A callback after `OnStopIO()` can still push frames if the
ring is mapped.

**Why it happens:** `ioRunning_` is written by start/stop but not checked by
`OnProcessMixedOutput()`.

**How to avoid:** Add `!ioRunning_` to the early return guard before stream
processing or ring writes.

**Regression:** stop IO, call `OnProcessMixedOutput()`, verify the consumer sees
zero frames.

---

### Pitfall 3: AudioConverter Input Callback Writes Into Unknown Storage

**What goes wrong:** `InputDataProc` casts `ioData->mBuffers[0].mData` to
`float*` and writes interleaved input into it.

**Why it happens:** `inputInterleaved_` is allocated but not used as callback
source storage. Converter input callbacks should provide data from owned input,
not assume writable Core Audio-provided memory.

**How to avoid:** Pre-interleave into `inputInterleaved_` and set
`ioData->mBuffers[0].mData` to the owned slice, or remove the legacy converter
path from public CLI/docs/build.

**Regression:** source guard that `InputDataProc` assigns `mData` from user-owned
input and does not write through `ioData` as destination storage.

---

### Pitfall 4: Data-Race-Safe Metrics Still May Not Be Realtime-Safe

**What goes wrong:** `std::atomic<double>` may be implemented with a lock on a
target the project later supports.

**Why it happens:** Standard C++ does not guarantee every atomic floating type is
always lock-free.

**How to avoid:** Store floating payloads as `std::atomic<uint64_t>` bit patterns
and assert `uint64_t` lock-freedom at compile time. Preserve the existing
`PublishMetrics()` / `ReadMetrics()` API.

**Regression:** compile-time assertion and source/test guard that
`MetricsPublisherState` no longer contains `std::atomic<double>`.

---

### Pitfall 5: Pipe Deadlock Fix Only Covers stdout

**What goes wrong:** `DeviceCatalog.refresh()` can still hang if
`apm44-bridge --list-devices` writes enough stderr.

**Why it happens:** stdout is drained before `waitUntilExit()`, but stderr is set
to an undrained `Pipe()`.

**How to avoid:** Set `process.standardError = FileHandle.nullDevice` unless
diagnostics are required. If diagnostics become useful later, drain stdout and
stderr concurrently.

**Regression:** Swift/source guard for `FileHandle.nullDevice` or concurrent
stderr drain.

---

### Pitfall 6: Stale Metrics Timestamp Survives Across Runs

**What goes wrong:** A new start or idle transition can briefly inherit an old
`lastMetricsAt`, causing stale metrics UI to appear immediately or incorrectly.

**Why it happens:** start resets `latestMetrics`, `lastXrunCount`, and
`metricsStale`, but not `lastMetricsAt`; idle cleanup also leaves it untouched.

**How to avoid:** Reset `lastMetricsAt = nil` alongside `latestMetrics = nil` on
start and idle transitions.

**Regression:** Swift lifecycle test or narrow testing hook proving restart/idle
clears the timestamp.

---

### Pitfall 7: Release Tests Are Local-Only

**What goes wrong:** Release-script hardening can regress while GitHub CI stays
green.

**Why it happens:** `scripts/ci.sh` runs `bash tests/test_release_scripts.sh`,
but `.github/workflows/ci.yml` does not.

**How to avoid:** Add a GitHub CI step after native tests. Add a source guard to
`tests/test_release_scripts.sh` so the workflow omission is caught locally too.

**Regression:** release script test checks `.github/workflows/ci.yml` contains
`bash tests/test_release_scripts.sh`.

---

### Pitfall 8: Installer Bundle Copy Can Merge or Partially Overwrite

**What goes wrong:** `cp -R` into `/Applications` can fail on permissions, merge
with an old bundle, or leave stale files.

**Why it happens:** The generated DMG command uses privileged deterministic HAL
driver install, then switches to unprivileged app copy.

**How to avoid:** Remove the existing app bundle with sudo, copy with sudo
`ditto`, and chown to `root:wheel`.

**Regression:** release script source test checks the generated command contains
the deterministic app install sequence.

---

### Pitfall 9: Comments Contradict Realtime Drop Policy

**What goes wrong:** Future maintainers can reintroduce producer-side drop-old
logic because a comment says the oldest frame is skipped.

**Why it happens:** `pushInterleaved()` kept an old comment after the project
standardized on drop-new input behavior.

**How to avoid:** Update the comment to say the bounded shm ring accepted only
the prefix and dropped the incoming tail.

**Regression:** simple source guard or direct review as part of HAL phase.

---
*Pitfalls research for: APM44 Bridge v0.6 Public Release Safety Fixes*
*Researched: 2026-06-13*
