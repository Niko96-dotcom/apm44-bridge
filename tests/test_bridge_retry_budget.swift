import Foundation
import XCTest
@testable import APM44Bridge

final class BridgeRetryBudgetTests: XCTestCase {
    func testInitialState() {
        let budget = BridgeRetryBudget()
        XCTAssertEqual(BridgeRetryBudget.maxUnhealthyLaunches, 4)
        XCTAssertEqual(budget.attempt, 0)
        XCTAssertNil(budget.lastExitStatus)
        XCTAssertNil(budget.lastStderr)
    }

    func testResetClearsAttemptAndDiagnostics() {
        var budget = BridgeRetryBudget()
        budget.recordUnexpectedExit(status: 1, stderr: "boom")
        XCTAssertEqual(budget.consumeAttempt(delays: [1]), .retry(delay: 1))
        budget.reset()
        XCTAssertEqual(budget, BridgeRetryBudget())
    }

    func testClearAttemptKeepingDiagnostics() {
        var budget = BridgeRetryBudget()
        budget.recordUnexpectedExit(status: 3, stderr: "tail")
        XCTAssertEqual(budget.consumeAttempt(delays: [1]), .retry(delay: 1))
        budget.clearAttemptKeepingDiagnostics()
        XCTAssertEqual(budget.attempt, 0)
        XCTAssertEqual(budget.lastExitStatus, 3)
        XCTAssertEqual(budget.lastStderr, "tail")
    }

    func testRecordUnexpectedExitSetsBothDiagnostics() {
        var budget = BridgeRetryBudget()
        budget.recordUnexpectedExit(status: 9, stderr: "snap")
        XCTAssertEqual(budget.lastExitStatus, 9)
        XCTAssertEqual(budget.lastStderr, "snap")
    }

    func testRecordRetryLaunchFailureSetsStderrOnly() {
        var budget = BridgeRetryBudget()
        budget.recordRetryLaunchFailure(detail: "launch boom")
        XCTAssertNil(budget.lastExitStatus)
        XCTAssertEqual(budget.lastStderr, "launch boom")
        budget.recordUnexpectedExit(status: 9, stderr: "old")
        budget.recordRetryLaunchFailure(detail: "launch boom")
        XCTAssertEqual(budget.lastExitStatus, 9)
        XCTAssertEqual(budget.lastStderr, "launch boom")
    }

    func testConsumeAttemptDelaySequenceAndExhaustion() {
        var budget = BridgeRetryBudget()
        XCTAssertEqual(budget.consumeAttempt(delays: [1, 2, 4]), .retry(delay: 1))
        XCTAssertEqual(budget.consumeAttempt(delays: [1, 2, 4]), .retry(delay: 2))
        XCTAssertEqual(budget.consumeAttempt(delays: [1, 2, 4]), .retry(delay: 4))
        XCTAssertEqual(budget.attempt, 3)
        budget.recordUnexpectedExit(status: 9, stderr: "boom")
        if case .exhausted(let message) = budget.consumeAttempt(delays: [1, 2, 4]) {
            XCTAssertEqual(message, AppStrings.stoppedAfterUnstableLaunches(
                BridgeRetryBudget.maxUnhealthyLaunches,
                detail: AppStrings.lastExit(9) + ": boom"
            ))
        } else {
            XCTFail("expected exhaustion on the 4th attempt")
        }
        XCTAssertEqual(budget.attempt, 4)
    }

    func testConsumeAttemptClampsShortDelaysToLastElement() {
        var budget = BridgeRetryBudget()
        XCTAssertEqual(budget.consumeAttempt(delays: [7]), .retry(delay: 7))
        XCTAssertEqual(budget.consumeAttempt(delays: [7]), .retry(delay: 7))
        XCTAssertEqual(budget.consumeAttempt(delays: [7]), .retry(delay: 7))
        if case .exhausted = budget.consumeAttempt(delays: [7]) {
        } else {
            XCTFail("expected exhaustion on the 4th attempt")
        }
    }

    func testExhaustedMessageNeither() {
        let budget = BridgeRetryBudget()
        XCTAssertEqual(
            budget.exhaustedMessage,
            AppStrings.stoppedAfterUnstableLaunches(BridgeRetryBudget.maxUnhealthyLaunches, detail: "")
        )
    }

    func testExhaustedMessageStatusOnly() {
        var budget = BridgeRetryBudget()
        budget.recordUnexpectedExit(status: 9, stderr: "")
        XCTAssertEqual(
            budget.exhaustedMessage,
            AppStrings.stoppedAfterUnstableLaunches(
                BridgeRetryBudget.maxUnhealthyLaunches,
                detail: AppStrings.lastExit(9)
            )
        )
    }

    func testExhaustedMessageStderrOnly() {
        var budget = BridgeRetryBudget()
        budget.recordRetryLaunchFailure(detail: "cable unplugged")
        XCTAssertEqual(
            budget.exhaustedMessage,
            AppStrings.stoppedAfterUnstableLaunches(
                BridgeRetryBudget.maxUnhealthyLaunches,
                detail: ": cable unplugged"
            )
        )
    }

    func testExhaustedMessageBoth() {
        var budget = BridgeRetryBudget()
        budget.recordUnexpectedExit(status: 2, stderr: "boom")
        XCTAssertEqual(
            budget.exhaustedMessage,
            AppStrings.stoppedAfterUnstableLaunches(
                BridgeRetryBudget.maxUnhealthyLaunches,
                detail: "\(AppStrings.lastExit(2)): boom"
            )
        )
    }

    func testBannerAttemptZeroIsNil() {
        let budget = BridgeRetryBudget()
        for state in [BridgeRunState.idle, .starting, .running, .stopping, .reconnecting, .error("x")] {
            XCTAssertNil(budget.bannerMessage(for: state), "\(state)")
        }
    }

    func testBannerAttemptTwoWhileReconnecting() {
        var budget = BridgeRetryBudget()
        XCTAssertEqual(budget.consumeAttempt(delays: [1]), .retry(delay: 1))
        XCTAssertEqual(budget.consumeAttempt(delays: [1]), .retry(delay: 1))
        XCTAssertEqual(
            budget.bannerMessage(for: .reconnecting),
            AppStrings.reconnectingAttempt(current: 2, max: BridgeRetryBudget.maxUnhealthyLaunches)
        )
    }

    func testBannerAttemptTwoWhileIdleAndStoppingIsNil() {
        var budget = BridgeRetryBudget()
        XCTAssertEqual(budget.consumeAttempt(delays: [1]), .retry(delay: 1))
        XCTAssertEqual(budget.consumeAttempt(delays: [1]), .retry(delay: 1))
        XCTAssertNil(budget.bannerMessage(for: .idle))
        XCTAssertNil(budget.bannerMessage(for: .stopping))
    }

    func testBannerAttemptTwoWhileStartingRunningAndErrorShowsAttempt() {
        var budget = BridgeRetryBudget()
        XCTAssertEqual(budget.consumeAttempt(delays: [1]), .retry(delay: 1))
        XCTAssertEqual(budget.consumeAttempt(delays: [1]), .retry(delay: 1))
        let expected = AppStrings.reconnectingAttempt(current: 2, max: BridgeRetryBudget.maxUnhealthyLaunches)
        for state in [BridgeRunState.starting, .running, .error("x")] {
            XCTAssertEqual(budget.bannerMessage(for: state), expected, "\(state)")
        }
    }

    func testBannerWhenExhaustedIsNilWhileIdleAndStopping() {
        var budget = BridgeRetryBudget()
        for _ in 0..<BridgeRetryBudget.maxUnhealthyLaunches {
            _ = budget.consumeAttempt(delays: [1])
        }
        XCTAssertNil(budget.bannerMessage(for: .idle))
        XCTAssertNil(budget.bannerMessage(for: .stopping))
    }

    func testBannerAttemptFourWhileErrorIsExhaustedMessage() {
        var budget = BridgeRetryBudget()
        budget.recordUnexpectedExit(status: 1, stderr: "tail")
        XCTAssertEqual(budget.consumeAttempt(delays: [1]), .retry(delay: 1))
        XCTAssertEqual(budget.consumeAttempt(delays: [1]), .retry(delay: 1))
        XCTAssertEqual(budget.consumeAttempt(delays: [1]), .retry(delay: 1))
        guard case .exhausted(let message) = budget.consumeAttempt(delays: [1]) else {
            XCTFail("expected exhaustion on the 4th attempt")
            return
        }
        XCTAssertEqual(message, budget.exhaustedMessage)
        XCTAssertEqual(budget.bannerMessage(for: .error("x")), budget.exhaustedMessage)
    }
}
