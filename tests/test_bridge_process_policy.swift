import Foundation
import XCTest
@testable import APM44Bridge

private func makeMetrics(fillMs: Double = 10, targetFillMs: Double = 20) -> BridgeMetricsSnapshot {
    BridgeMetricsSnapshot(
        fillMs: fillMs,
        ratio: 1.0,
        ppm: 0,
        underruns: 0,
        overruns: 0,
        xruns: 0,
        estimatedRtMs: 15,
        targetFillMs: targetFillMs,
        srcQuality: "medium"
    )
}

final class DaemonStdoutLineBufferTests: XCTestCase {
    func testSplitAcrossChunks() {
        var buffer = DaemonStdoutLineBuffer()
        XCTAssertEqual(buffer.append(Data("a\nb".utf8)), ["a"])
        XCTAssertEqual(buffer.append(Data("c\n".utf8)), ["bc"])
    }

    func testEmptyLinesSkippedAndTrailingFragmentRetained() {
        var buffer = DaemonStdoutLineBuffer()
        XCTAssertEqual(buffer.append(Data("\n\nx\n\ny\n".utf8)), ["x", "y"])
        XCTAssertEqual(buffer.append(Data("frag".utf8)), [])
        XCTAssertEqual(buffer.append(Data("ment\n".utf8)), ["fragment"])
    }

    func testOverflowKeepsNewest64KiB() {
        var buffer = DaemonStdoutLineBuffer()
        let big = String(repeating: "a", count: 64 * 1024) + "\n"
        XCTAssertEqual(buffer.append(Data(big.utf8)), [String(repeating: "a", count: 64 * 1024 - 1)])
    }

    func testOverflowDropsOldestBytes() {
        var buffer = DaemonStdoutLineBuffer()
        XCTAssertEqual(buffer.append(Data("keep\n".utf8)), ["keep"])
        XCTAssertEqual(buffer.append(Data(String(repeating: "z", count: 70 * 1024).utf8)), [])
        XCTAssertEqual(buffer.append(Data("\n".utf8)), [String(repeating: "z", count: 64 * 1024 - 1)])
    }

    func testInvalidUTF8ReturnsEmptyAndKeepsBuffer() {
        // Matches the old consumeStdout: while the accumulated bytes do not
        // decode as UTF-8, append returns [] and the bytes are retained, so a
        // later completion only yields lines if the whole buffer decodes.
        var buffer = DaemonStdoutLineBuffer()
        XCTAssertEqual(buffer.append(Data([0xFF])), [])
        XCTAssertEqual(buffer.append(Data("a\n".utf8)), [])
    }

    func testSplitMultibyteSequenceCompletes() {
        var buffer = DaemonStdoutLineBuffer()
        let first = Data("é".utf8)
        XCTAssertEqual(buffer.append(first.prefix(1)), [])
        XCTAssertEqual(buffer.append(first.suffix(1) + Data("\n".utf8)), ["é"])
    }

    func testReset() {
        var buffer = DaemonStdoutLineBuffer()
        XCTAssertEqual(buffer.append(Data("frag".utf8)), [])
        buffer.reset()
        XCTAssertEqual(buffer.append(Data("next\n".utf8)), ["next"])
    }
}

final class DaemonStderrTailTests: XCTestCase {
    func testKeepsLast20Lines() {
        var tail = DaemonStderrTail()
        tail.append((0..<25).map { "line\($0)" }.joined(separator: "\n"))
        XCTAssertEqual(tail.joined, (5..<25).map { "line\($0)" }.joined(separator: "\n"))
        XCTAssertEqual(tail.lastLine, "line24")
    }

    func testEmptySegmentsDropped() {
        var tail = DaemonStderrTail()
        tail.append("a\n\nb\n")
        XCTAssertEqual(tail.joined, "a\nb")
    }

    func testFailureIsIPCWhenStderrMentionsShm() {
        var tail = DaemonStderrTail()
        tail.append("boom\nshm attach failed")
        XCTAssertEqual(tail.failure(exitStatus: 1), .driverIPCFailed)
    }

    func testFailureIsIPCForStaleRingExitCodeWithoutShmStderr() {
        var tail = DaemonStderrTail()
        tail.append("something unrelated")
        XCTAssertEqual(tail.failure(exitStatus: DaemonExitCode.staleShmRing.rawValue), .driverIPCFailed)
    }

    func testFailureKeepsLastLineVerbatimThenNothing() {
        var tail = DaemonStderrTail()
        XCTAssertEqual(tail.failure(exitStatus: 1), .helperFailed(stderr: nil))
        tail.append("first\nlast\twith \u{01}control")
        XCTAssertEqual(tail.failure(exitStatus: 1), .helperFailed(stderr: "last\twith \u{01}control"))
    }

    func testRemoveAll() {
        var tail = DaemonStderrTail()
        tail.append("x")
        tail.removeAll()
        XCTAssertEqual(tail.joined, "")
        XCTAssertNil(tail.lastLine)
    }
}

final class BridgeDiagnosticsTests: XCTestCase {
    func testSanitizedControlCharsAndNewlines() {
        XCTAssertEqual(BridgeDiagnostics.sanitized("a\rb\nc\u{01}\u{7f}d"), "a b cd")
        XCTAssertEqual(BridgeDiagnostics.sanitized("a\rb\nc"), "a b c")
        XCTAssertEqual(BridgeDiagnostics.sanitized("a\u{01}b\u{7f}c"), "abc")
    }

    func testSanitizedEmptyFallsBack() {
        XCTAssertEqual(BridgeDiagnostics.sanitized(""), AppStrings.noDiagnostic)
        XCTAssertEqual(BridgeDiagnostics.sanitized(" \n\r "), AppStrings.noDiagnostic)
        XCTAssertEqual(BridgeDiagnostics.sanitized("\u{01}\u{7f}"), AppStrings.noDiagnostic)
    }

    func testSanitizedTruncatesTo240() {
        XCTAssertEqual(BridgeDiagnostics.sanitized(String(repeating: "a", count: 300)), String(repeating: "a", count: 240))
    }
}

final class BridgeLaunchArgumentsTests: XCTestCase {
    func testNonHAL() {
        XCTAssertEqual(
            BridgeLaunchArguments.make(outputUid: "uid", targetFillMs: 15, srcQuality: "high", halMode: false),
            ["--output-device", "uid", "--target-fill-ms", "15", "--src-quality", "high", "--metrics-json", "--parent-watch-stdin"]
        )
    }

    func testHALInsertsVirtualDeviceFirst() {
        XCTAssertEqual(
            BridgeLaunchArguments.make(outputUid: "uid", targetFillMs: 20, srcQuality: "medium", halMode: true),
            ["--virtual-device", "--output-device", "uid", "--target-fill-ms", "20", "--src-quality", "medium", "--metrics-json", "--parent-watch-stdin"]
        )
    }

    func testFillMsRounded() {
        XCTAssertEqual(
            BridgeLaunchArguments.make(outputUid: "u", targetFillMs: 14.6, srcQuality: "best", halMode: false)[3],
            "15"
        )
    }
}

final class BridgeConnectionPhaseDeriveTests: XCTestCase {
    func testStoppedStates() {
        for state in [BridgeRunState.idle, .stopping, .reconnecting, .error(.helperFailed(stderr: "x"))] {
            XCTAssertEqual(BridgeConnectionPhase.derive(state: state, halMode: true, metrics: makeMetrics()), .stopped, "\(state)")
            XCTAssertEqual(BridgeConnectionPhase.derive(state: state, halMode: false, metrics: nil), .stopped, "\(state)")
        }
    }

    func testStarting() {
        XCTAssertEqual(BridgeConnectionPhase.derive(state: .starting, halMode: true, metrics: nil), .waitingForDAW)
        XCTAssertEqual(BridgeConnectionPhase.derive(state: .starting, halMode: false, metrics: nil), .connected)
    }

    func testRunningWithoutMetrics() {
        XCTAssertEqual(BridgeConnectionPhase.derive(state: .running, halMode: true, metrics: nil), .waitingForDAW)
        XCTAssertEqual(BridgeConnectionPhase.derive(state: .running, halMode: false, metrics: nil), .running)
    }

    func testRunningWithMetrics() {
        XCTAssertEqual(BridgeConnectionPhase.derive(state: .running, halMode: false, metrics: makeMetrics(fillMs: 1.9)), .waitingForDAW)
        XCTAssertEqual(BridgeConnectionPhase.derive(state: .running, halMode: false, metrics: makeMetrics(fillMs: 2.0, targetFillMs: 20)), .connected)
        XCTAssertEqual(BridgeConnectionPhase.derive(state: .running, halMode: false, metrics: makeMetrics(fillMs: 5, targetFillMs: 20)), .connected)
        XCTAssertEqual(BridgeConnectionPhase.derive(state: .running, halMode: false, metrics: makeMetrics(fillMs: 10, targetFillMs: 20)), .running)
        XCTAssertEqual(BridgeConnectionPhase.derive(state: .running, halMode: false, metrics: makeMetrics(fillMs: 15, targetFillMs: 20)), .running)
        XCTAssertEqual(BridgeConnectionPhase.derive(state: .running, halMode: false, metrics: makeMetrics(fillMs: 10, targetFillMs: 0)), .running)
    }
}

final class BridgeTerminationPolicyTests: XCTestCase {
    func testTable() {
        let rows: [(BridgeRunState, Int32, StopReason?, BridgeTerminationOutcome)] = [
            (.running, 44, nil, .loadedDriverMismatch),
            (.starting, 44, .user, .loadedDriverMismatch),
            (.error(.helperFailed(stderr: "x")), 44, nil, .ignore),
            (.running, 43, nil, .helperAlreadyRunning),
            (.running, 43, .internal, .helperAlreadyRunning),
            (.running, 43, .user, .helperAlreadyRunning),
            (.starting, 43, nil, .helperAlreadyRunning),
            (.reconnecting, 43, nil, .ignore),
            (.running, 42, nil, .autoRetry),
            (.running, 42, .user, .failWhileRunning),
            (.starting, 42, nil, .failWhileStarting),
            (.running, 1, nil, .autoRetry),
            (.running, 1, .internal, .autoRetry),
            (.running, 1, .user, .failWhileRunning),
            (.running, 0, nil, .cleanExitWhileRunning),
            (.running, 0, .user, .cleanExitWhileRunning),
            (.starting, 1, nil, .failWhileStarting),
            (.starting, 0, nil, .failWhileStarting),
            (.reconnecting, 1, nil, .ignore),
            (.reconnecting, 0, nil, .ignore),
            (.idle, 1, nil, .ignore),
            (.error(.helperFailed(stderr: "x")), 1, nil, .ignore),
        ]
        for (state, status, reason, expected) in rows {
            XCTAssertEqual(
                BridgeTerminationPolicy.classify(state: state, exitStatus: status, lastStopReason: reason),
                expected,
                "state=\(state) status=\(status) reason=\(String(describing: reason))"
            )
        }
    }

    func testDaemonExitCodesMatchHelper() {
        XCTAssertEqual(DaemonExitCode.staleShmRing.rawValue, 42)
        XCTAssertEqual(DaemonExitCode.singletonBusy.rawValue, 43)
        XCTAssertEqual(DaemonExitCode.loadedDriverBuildMismatch.rawValue, 44)
        XCTAssertNil(DaemonExitCode(rawValue: 1))
        XCTAssertNil(DaemonExitCode(rawValue: 0))
    }
}
