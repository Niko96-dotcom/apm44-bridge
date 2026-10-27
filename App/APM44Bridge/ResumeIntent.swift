import Foundation

/// The three reasons to start the bridge again once a condition clears, and
/// every rule for recording, cancelling, consuming and expiring them.
///
/// This is the model half of Option B in
/// `docs/adr/0001-wake-resume-intent.md`. It does no I/O, never awaits and
/// reads no clock: the caller passes the time in. `BridgeProcessManager`
/// builds one value through its `resumeIntent` accessor, calls the operation
/// that names each event, and keeps all scheduling, generation counters and
/// the run state itself. The manager stores the wake and output-return
/// intents; `BridgeSettings` stores the update request.
struct ResumeIntent: Equatable {
    /// A request older than this when the relaunched app checks it is stale.
    static let updateResumeWindow: TimeInterval = 10 * 60

    /// Sleep stopped an active bridge; the next wake starts it again.
    private(set) var resumesOnWake = false
    /// The bridge waits in `.reconnecting` for its output; the next hotplug
    /// that lists the output starts it again.
    private(set) var resumesWhenOutputReturns = false
    /// An in-app update started installing while the bridge ran; the
    /// relaunched app starts it again. `BridgeSettings` persists this one.
    private(set) var updateRequestedAt: Date?

    init(
        resumesOnWake: Bool = false,
        resumesWhenOutputReturns: Bool = false,
        updateRequestedAt: Date? = nil
    ) {
        self.resumesOnWake = resumesOnWake
        self.resumesWhenOutputReturns = resumesWhenOutputReturns
        self.updateRequestedAt = updateRequestedAt
    }

    // MARK: - User

    /// A user stop outranks every pending resume, or a later wake, hotplug
    /// or relaunch would start the bridge again.
    mutating func userStop() {
        resumesOnWake = false
        resumesWhenOutputReturns = false
        updateRequestedAt = nil
    }

    // MARK: - Helper

    /// A helper launched, so no park waits for the output any more.
    mutating func helperLaunched() {
        resumesWhenOutputReturns = false
    }

    // MARK: - Sleep and wake

    /// Sleep while the bridge is running, starting or reconnecting records a
    /// wake resume and drops a park, because the wake re-reads the devices.
    /// Sleep while the bridge is inactive keeps an intent that a wake has not
    /// consumed yet: a sleep that lands during that wake finds the bridge
    /// already stopped.
    mutating func systemWillSleep(bridgeActive: Bool) {
        guard bridgeActive else { return }
        resumesOnWake = true
        resumesWhenOutputReturns = false
    }

    /// Sleep while a restart replaces the helper: the bridge is logically
    /// running, and the restart leaves its relaunch to the wake.
    mutating func sleepDuringRestart() {
        resumesOnWake = true
    }

    /// The wake took over the resume. Returns whether it should start the
    /// bridge, and clears the intent so a second wake does not.
    mutating func consumeWakeResume() -> Bool {
        defer { resumesOnWake = false }
        return resumesOnWake
    }

    /// The wake could not start the bridge (a stop still in flight, no
    /// device list, or the output unavailable) and parks it, so the next
    /// hotplug with the output present finishes the resume.
    mutating func parkAfterWake() {
        resumesWhenOutputReturns = true
    }

    /// A helper exit while parked finishes a wake resume only when the wake
    /// parked over its own unfinished sleep stop (stop reason `.internal`).
    /// A failed hotplug stop can also leave a tracked helper in
    /// `.reconnecting`, but its reason is `.hotplug`.
    func isWakeParkedOverSleepStop(state: BridgeRunState, lastStopReason: StopReason?) -> Bool {
        guard case .reconnecting = state else { return false }
        return resumesWhenOutputReturns && lastStopReason == .internal
    }

    // MARK: - Output

    /// The selected output vanished while the bridge ran; the bridge stops
    /// and resumes when the output comes back.
    mutating func outputLostWhileRunning() {
        resumesWhenOutputReturns = true
    }

    /// The output selection was cleared while the bridge ran; there is no
    /// output to wait for.
    mutating func outputSelectionClearedWhileRunning() {
        resumesWhenOutputReturns = false
    }

    /// The output came back and the bridge started (or is starting) again.
    mutating func outputReturned() {
        resumesWhenOutputReturns = false
    }

    // MARK: - Update

    /// An in-app update started installing. Only a running bridge resumes
    /// after the relaunch.
    mutating func updateInstallStarted(at now: Date, bridgeRunning: Bool) {
        guard bridgeRunning else { return }
        updateRequestedAt = now
    }

    /// The install failed or was cancelled, so this app keeps running and no
    /// relaunch will resume.
    mutating func updateInstallAbandoned() {
        updateRequestedAt = nil
    }

    /// Loads the request that `BridgeSettings` persisted across the relaunch.
    mutating func loadPersistedUpdateRequest(_ requestedAt: Date?) {
        updateRequestedAt = requestedAt
    }

    /// Decides a pending post-update resume and returns whether to start the
    /// bridge now.
    ///
    /// The request is kept while the only blocker is a selected output that
    /// Core Audio has not listed yet (postinstall restarts coreaudiod, so the
    /// first refresh may miss it). It is cleared when it is consumed, when it
    /// is stale or dated in the future, when the bridge is not idle, in error
    /// or reconnecting, and for any other start blocker.
    mutating func checkUpdateResume(
        at now: Date,
        state: BridgeRunState,
        selectedOutputListed: Bool,
        startBlocked: @autoclosure () -> Bool
    ) -> Bool {
        guard let requestedAt = updateRequestedAt else { return false }
        let age = now.timeIntervalSince(requestedAt)
        guard age >= 0, age < Self.updateResumeWindow else {
            updateRequestedAt = nil
            return false
        }
        switch state {
        case .idle, .error, .reconnecting: break
        default:
            updateRequestedAt = nil
            return false
        }
        guard selectedOutputListed else { return false }
        updateRequestedAt = nil
        return !startBlocked()
    }
}
