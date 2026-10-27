import XCTest
@testable import APM44Bridge

final class ResumeIntentTests: XCTestCase {
    private static let requestedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let window = ResumeIntent.updateResumeWindow

    private static let none = ResumeIntent()
    private static let all = ResumeIntent(
        resumesOnWake: true,
        resumesWhenOutputReturns: true,
        updateRequestedAt: requestedAt
    )
    private static let wakeOnly = ResumeIntent(resumesOnWake: true)
    private static let outputOnly = ResumeIntent(resumesWhenOutputReturns: true)
    private static let updateOnly = ResumeIntent(updateRequestedAt: requestedAt)

    private struct EventCase {
        let name: String
        let before: ResumeIntent
        let event: (inout ResumeIntent) -> Void
        let after: ResumeIntent
    }

    private func check(_ cases: [EventCase], file: StaticString = #filePath, line: UInt = #line) {
        for item in cases {
            var intent = item.before
            item.event(&intent)
            XCTAssertEqual(intent, item.after, item.name, file: file, line: line)
        }
    }

    func testUserStopCancelsEveryIntent() {
        check([
            EventCase(name: "all three intents", before: Self.all,
                      event: { $0.userStop() }, after: Self.none),
            EventCase(name: "wake intent", before: Self.wakeOnly,
                      event: { $0.userStop() }, after: Self.none),
            EventCase(name: "output-return intent", before: Self.outputOnly,
                      event: { $0.userStop() }, after: Self.none),
            EventCase(name: "update request", before: Self.updateOnly,
                      event: { $0.userStop() }, after: Self.none),
            EventCase(name: "nothing pending", before: Self.none,
                      event: { $0.userStop() }, after: Self.none),
        ])
    }

    func testSleepRecordsOrKeepsTheWakeIntent() {
        check([
            EventCase(name: "active sleep records a wake resume and drops a park",
                      before: Self.outputOnly,
                      event: { $0.systemWillSleep(bridgeActive: true) },
                      after: Self.wakeOnly),
            EventCase(name: "active sleep keeps the update request",
                      before: Self.updateOnly,
                      event: { $0.systemWillSleep(bridgeActive: true) },
                      after: ResumeIntent(resumesOnWake: true, updateRequestedAt: Self.requestedAt)),
            EventCase(name: "a sleep that lands during a wake keeps the unconsumed intent",
                      before: Self.wakeOnly,
                      event: { $0.systemWillSleep(bridgeActive: false) },
                      after: Self.wakeOnly),
            EventCase(name: "inactive sleep records nothing",
                      before: Self.none,
                      event: { $0.systemWillSleep(bridgeActive: false) },
                      after: Self.none),
            EventCase(name: "inactive sleep keeps a park",
                      before: Self.outputOnly,
                      event: { $0.systemWillSleep(bridgeActive: false) },
                      after: Self.outputOnly),
            EventCase(name: "sleep during a restart records a wake resume",
                      before: Self.none,
                      event: { $0.sleepDuringRestart() },
                      after: Self.wakeOnly),
            EventCase(name: "sleep during a restart keeps a park",
                      before: Self.outputOnly,
                      event: { $0.sleepDuringRestart() },
                      after: ResumeIntent(resumesOnWake: true, resumesWhenOutputReturns: true)),
        ])
    }

    func testSleepDuringWakeKeepsIntentForTheWakeToConsume() {
        var intent = ResumeIntent()
        intent.systemWillSleep(bridgeActive: true)
        // The wake has not consumed the intent when the second sleep lands.
        intent.systemWillSleep(bridgeActive: false)
        XCTAssertTrue(intent.consumeWakeResume())
        XCTAssertFalse(intent.consumeWakeResume(), "a second wake must not resume again")
    }

    func testConsumeWakeResumeReturnsAndClearsTheWakeIntent() {
        let cases: [(name: String, before: ResumeIntent, resumes: Bool, after: ResumeIntent)] = [
            ("pending wake intent", Self.wakeOnly, true, Self.none),
            ("no wake intent", Self.none, false, Self.none),
            ("other intents stay", Self.all, true,
             ResumeIntent(resumesWhenOutputReturns: true, updateRequestedAt: Self.requestedAt)),
            ("park alone does not resume a wake", Self.outputOnly, false, Self.outputOnly),
        ]
        for item in cases {
            var intent = item.before
            XCTAssertEqual(intent.consumeWakeResume(), item.resumes, item.name)
            XCTAssertEqual(intent, item.after, item.name)
        }
    }

    func testOutputAndLaunchEventsSetOrClearThePark() {
        check([
            EventCase(name: "a wake park waits for the output",
                      before: Self.none, event: { $0.parkAfterWake() }, after: Self.outputOnly),
            EventCase(name: "a lost output while running waits for the output",
                      before: Self.none, event: { $0.outputLostWhileRunning() }, after: Self.outputOnly),
            EventCase(name: "a cleared selection leaves nothing to wait for",
                      before: Self.outputOnly,
                      event: { $0.outputSelectionClearedWhileRunning() },
                      after: Self.none),
            EventCase(name: "a returned output finishes the park",
                      before: Self.outputOnly, event: { $0.outputReturned() }, after: Self.none),
            EventCase(name: "a launched helper finishes the park",
                      before: Self.outputOnly, event: { $0.helperLaunched() }, after: Self.none),
            EventCase(name: "a launched helper keeps the wake intent and update request",
                      before: Self.all, event: { $0.helperLaunched() },
                      after: ResumeIntent(resumesOnWake: true, updateRequestedAt: Self.requestedAt)),
        ])
    }

    func testWakeParkedOverSleepStopNeedsParkReconnectingAndInternalStop() {
        let cases: [(name: String, intent: ResumeIntent, state: BridgeRunState, reason: StopReason?, expected: Bool)] = [
            ("wake parked over its sleep stop", Self.outputOnly, .reconnecting, .internal, true),
            ("a failed hotplug stop is not a wake park", Self.outputOnly, .reconnecting, .hotplug, false),
            ("no park", Self.none, .reconnecting, .internal, false),
            ("not reconnecting", Self.outputOnly, .stopping, .internal, false),
            ("no stop reason", Self.outputOnly, .reconnecting, nil, false),
            ("wake intent alone is not a park", Self.wakeOnly, .reconnecting, .internal, false),
        ]
        for item in cases {
            XCTAssertEqual(
                item.intent.isWakeParkedOverSleepStop(state: item.state, lastStopReason: item.reason),
                item.expected,
                item.name
            )
        }
    }

    func testUpdateInstallRecordsOrDropsTheRequest() {
        let at = Self.requestedAt
        check([
            EventCase(name: "install while running records the time",
                      before: Self.none,
                      event: { $0.updateInstallStarted(at: at, bridgeRunning: true) },
                      after: Self.updateOnly),
            EventCase(name: "install while not running records nothing",
                      before: Self.none,
                      event: { $0.updateInstallStarted(at: at, bridgeRunning: false) },
                      after: Self.none),
            EventCase(name: "abandoned install drops the request",
                      before: Self.updateOnly, event: { $0.updateInstallAbandoned() }, after: Self.none),
            EventCase(name: "abandoned install keeps the other intents",
                      before: Self.all, event: { $0.updateInstallAbandoned() },
                      after: ResumeIntent(resumesOnWake: true, resumesWhenOutputReturns: true)),
            EventCase(name: "loading the persisted request replaces the in-memory one",
                      before: Self.wakeOnly,
                      event: { $0.loadPersistedUpdateRequest(at) },
                      after: ResumeIntent(resumesOnWake: true, updateRequestedAt: at)),
            EventCase(name: "loading no persisted request clears it",
                      before: Self.updateOnly,
                      event: { $0.loadPersistedUpdateRequest(nil) },
                      after: Self.none),
        ])
    }

    private struct UpdateCheckCase {
        let name: String
        var requestedAt: Date? = ResumeIntentTests.requestedAt
        var age: TimeInterval = 60
        var state: BridgeRunState = .idle
        var outputListed = true
        var blocked = false
        let starts: Bool
        let keepsRequest: Bool
    }

    func testUpdateResumeCheckStartsKeepsOrClears() {
        let cases = [
            UpdateCheckCase(name: "no request", requestedAt: nil, starts: false, keepsRequest: false),
            UpdateCheckCase(name: "fresh request while idle starts", starts: true, keepsRequest: false),
            UpdateCheckCase(name: "fresh request in error starts",
                            state: .error(.outputDeviceDisconnected), starts: true, keepsRequest: false),
            UpdateCheckCase(name: "fresh request while reconnecting starts",
                            state: .reconnecting, starts: true, keepsRequest: false),
            UpdateCheckCase(name: "a request made just now starts", age: 0, starts: true, keepsRequest: false),
            UpdateCheckCase(name: "just inside the 10-minute window starts",
                            age: ResumeIntentTests.window - 1, starts: true, keepsRequest: false),
            UpdateCheckCase(name: "exactly 10 minutes old is stale",
                            age: ResumeIntentTests.window, starts: false, keepsRequest: false),
            UpdateCheckCase(name: "11 minutes old is stale",
                            age: 11 * 60, starts: false, keepsRequest: false),
            UpdateCheckCase(name: "a request dated in the future is dropped",
                            age: -1, starts: false, keepsRequest: false),
            UpdateCheckCase(name: "a stale request is dropped even with the output missing",
                            age: 11 * 60, outputListed: false, starts: false, keepsRequest: false),
            UpdateCheckCase(name: "already running drops the request",
                            state: .running, starts: false, keepsRequest: false),
            UpdateCheckCase(name: "starting drops the request",
                            state: .starting, starts: false, keepsRequest: false),
            UpdateCheckCase(name: "stopping drops the request",
                            state: .stopping, starts: false, keepsRequest: false),
            UpdateCheckCase(name: "an unlisted output keeps the request",
                            outputListed: false, starts: false, keepsRequest: true),
            UpdateCheckCase(name: "an unlisted output keeps the request even when blocked",
                            outputListed: false, blocked: true, starts: false, keepsRequest: true),
            UpdateCheckCase(name: "another blocker drops the request without starting",
                            blocked: true, starts: false, keepsRequest: false),
        ]
        let now = Self.requestedAt.addingTimeInterval(3_600)
        for item in cases {
            var intent = ResumeIntent(
                resumesOnWake: true,
                resumesWhenOutputReturns: true,
                updateRequestedAt: item.requestedAt == nil ? nil : now.addingTimeInterval(-item.age)
            )
            let before = intent
            let starts = intent.checkUpdateResume(
                at: now,
                state: item.state,
                selectedOutputListed: item.outputListed,
                startBlocked: item.blocked
            )
            XCTAssertEqual(starts, item.starts, item.name)
            XCTAssertEqual(
                intent.updateRequestedAt,
                item.keepsRequest ? before.updateRequestedAt : nil,
                item.name
            )
            XCTAssertTrue(intent.resumesOnWake, "\(item.name): the wake intent stays")
            XCTAssertTrue(intent.resumesWhenOutputReturns, "\(item.name): the park stays")
        }
    }

    func testUpdateResumeCheckReadsTheBlockerOnlyWhenItWouldStart() {
        let now = Self.requestedAt.addingTimeInterval(60)
        var stale = ResumeIntent(updateRequestedAt: now.addingTimeInterval(-Self.window - 1))
        var asked = false
        func blocked() -> Bool { asked = true; return false }
        XCTAssertFalse(stale.checkUpdateResume(at: now, state: .idle, selectedOutputListed: true,
                                               startBlocked: blocked()))
        XCTAssertFalse(asked, "a stale request never computes the start gate")

        var fresh = ResumeIntent(updateRequestedAt: Self.requestedAt)
        XCTAssertTrue(fresh.checkUpdateResume(at: now, state: .idle, selectedOutputListed: true,
                                              startBlocked: blocked()))
        XCTAssertTrue(asked)
        XCTAssertFalse(fresh.checkUpdateResume(at: now, state: .idle, selectedOutputListed: true,
                                               startBlocked: false),
                       "a consumed request does not start twice")
    }
}
