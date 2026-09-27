import Foundation

struct DaemonStdoutLineBuffer {
    private var buffer = Data()
    private let cap = 64 * 1024

    mutating func append(_ chunk: Data) -> [String] {
        buffer.append(chunk)
        if buffer.count > cap {
            buffer.removeFirst(buffer.count - cap)
        }
        guard let text = String(data: buffer, encoding: .utf8) else { return [] }
        var lines = text.components(separatedBy: "\n")
        if !text.hasSuffix("\n"), let last = lines.popLast() {
            buffer = Data(last.utf8)
        } else {
            buffer = Data()
        }
        return lines.filter { !$0.isEmpty }
    }

    mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
    }
}

struct DaemonStderrTail {
    private var lines: [String] = []
    private let cap = 20

    mutating func append(_ text: String) {
        for line in text.split(separator: "\n") {
            lines.append(String(line))
            if lines.count > cap {
                lines.removeFirst()
            }
        }
    }

    var joined: String {
        lines.joined(separator: "\n")
    }

    var lastLine: String? {
        lines.last
    }

    mutating func removeAll() {
        lines.removeAll()
    }

    func failureMessage(default defaultMessage: String) -> String {
        if joined.localizedCaseInsensitiveContains("shm") {
            return AppStrings.ipcFailed()
        }
        if let last = lines.last, !last.isEmpty {
            return last
        }
        return defaultMessage
    }
}

enum BridgeDiagnostics {
    static func sanitized(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let printableScalars = normalized.unicodeScalars.filter {
            $0.value >= 0x20 && $0.value != 0x7f
        }
        let singleLine = String(String.UnicodeScalarView(printableScalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if singleLine.isEmpty { return AppStrings.noDiagnostic }
        return String(singleLine.prefix(240))
    }
}

enum BridgeLaunchArguments {
    static func make(outputUid: String, targetFillMs: Double, srcQuality: String, halMode: Bool) -> [String] {
        var args: [String] = [
            "--output-device", outputUid,
            "--target-fill-ms", String(format: "%.0f", targetFillMs),
            "--src-quality", srcQuality,
            "--metrics-json",
            "--parent-watch-stdin",
        ]
        if halMode {
            args.insert("--virtual-device", at: 0)
        }
        return args
    }
}

extension BridgeConnectionPhase {
    static func derive(state: BridgeRunState, halMode: Bool, metrics: BridgeMetricsSnapshot?) -> BridgeConnectionPhase {
        switch state {
        case .idle, .stopping, .reconnecting:
            return .stopped
        case .starting:
            return halMode ? .waitingForDAW : .connected
        case .error:
            return .stopped
        case .running:
            guard let metrics else {
                return halMode ? .waitingForDAW : .running
            }
            let target = max(metrics.targetFillMs, 1.0)
            if metrics.fillMs < 2.0 {
                return .waitingForDAW
            } else if metrics.fillMs < target * 0.5 {
                return .connected
            } else {
                return .running
            }
        }
    }
}

/// Exit codes the helper uses to say why it stopped. Mirrors
/// BridgeDaemon/src/DaemonExitCodes.h; change both together.
enum DaemonExitCode: Int32 {
    case staleShmRing = 42
    case singletonBusy = 43
    case loadedDriverBuildMismatch = 44
}

enum BridgeTerminationOutcome: Equatable {
    case loadedDriverMismatch
    case helperAlreadyRunning
    case autoRetry
    case failWhileRunning
    case cleanExitWhileRunning
    case failWhileStarting
    case ignore
}

enum BridgeTerminationPolicy {
    /// Classifies an unexpected exit. A `.stopping` termination never gets
    /// here: the manager finishes the stop before reading the exit status.
    /// Classification uses the exit code only.
    static func classify(
        state: BridgeRunState,
        exitStatus: Int32,
        lastStopReason: StopReason?
    ) -> BridgeTerminationOutcome {
        if state == .running || state == .starting, let code = DaemonExitCode(rawValue: exitStatus) {
            switch code {
            case .loadedDriverBuildMismatch: return .loadedDriverMismatch
            case .singletonBusy: return .helperAlreadyRunning
            case .staleShmRing: break
            }
        }
        if exitStatus != 0, case .running = state {
            return lastStopReason != .user ? .autoRetry : .failWhileRunning
        }
        if exitStatus == 0, case .running = state {
            return .cleanExitWhileRunning
        }
        if case .starting = state {
            return .failWhileStarting
        }
        return .ignore
    }
}

struct BridgeRetryBudget: Equatable {
    enum Decision: Equatable {
        case exhausted(message: String)
        case retry(delay: TimeInterval)
    }

    static let maxUnhealthyLaunches = 4

    private(set) var attempt = 0
    private(set) var lastExitStatus: Int32?
    private(set) var lastStderr: String?

    var exhaustedMessage: String {
        var detail = ""
        if let status = lastExitStatus {
            detail = AppStrings.lastExit(Int(status))
        }
        if let stderr = lastStderr, !stderr.isEmpty {
            detail += ": \(stderr)"
        }
        return AppStrings.stoppedAfterUnstableLaunches(Self.maxUnhealthyLaunches, detail: detail)
    }

    func bannerMessage(for state: BridgeRunState) -> String? {
        guard attempt > 0 else { return nil }
        switch state {
        case .idle, .stopping: return nil
        default: break
        }
        if attempt >= Self.maxUnhealthyLaunches { return exhaustedMessage }
        return AppStrings.reconnectingAttempt(current: attempt, max: Self.maxUnhealthyLaunches)
    }

    /// A fresh user start or a launch that stayed up for the stability
    /// window: forget the attempt and its diagnostics.
    mutating func reset() {
        attempt = 0
        lastExitStatus = nil
        lastStderr = nil
    }

    mutating func clearAttemptKeepingDiagnostics() {
        attempt = 0
    }

    mutating func recordUnexpectedExit(status: Int32, stderr: String) {
        lastExitStatus = status
        lastStderr = stderr
    }

    mutating func recordRetryLaunchFailure(detail: String) {
        lastStderr = detail
    }

    mutating func consumeAttempt(delays: [TimeInterval]) -> Decision {
        attempt += 1
        if attempt >= Self.maxUnhealthyLaunches {
            return .exhausted(message: exhaustedMessage)
        }
        return .retry(delay: delays[min(attempt - 1, delays.count - 1)])
    }
}
