import Foundation
import Darwin

/// Owns process handle, pipe teardown, termination waiters, and auto-retry scheduling.
/// `BridgeProcessManager` keeps published UI state and high-level start/stop/hotplug policy.
@MainActor
final class BridgeLifecycleController {
    private let processLauncher: ProcessLaunching
    private let maxRetryAttempts = 4

    private(set) var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var terminationContinuations: [CheckedContinuation<Void, Never>] = []
    private var retryTask: Task<Void, Never>?

    private(set) var retryAttempt = 0
    private(set) var retryGeneration = 0
    var testRetryDelays: [TimeInterval]?
    /// Test-only override for termination wait budgets (production uses 5s).
    var testTerminationWaitTimeout: Duration?

    private var retryDelays: [TimeInterval] {
        testRetryDelays ?? [1.0, 2.0, 4.0, 4.0]
    }

    private var terminationWaitTimeout: Duration {
        testTerminationWaitTimeout ?? .seconds(5)
    }

    init(processLauncher: ProcessLaunching) {
        self.processLauncher = processLauncher
    }

    var isProcessActive: Bool { process != nil }

    func setRetryAttemptForTesting(_ value: Int) {
        retryAttempt = value
    }

    func resetRetryAttempt() {
        retryAttempt = 0
    }

    func attachLaunchedProcess(
        _ proc: Process,
        stdout: Pipe,
        stderr: Pipe
    ) {
        process = proc
        stdoutPipe = stdout
        stderrPipe = stderr
    }

    func takeProcess() -> Process? {
        let current = process
        process = nil
        return current
    }

    func clearPipeHandlers() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    func resumeTerminationWaiters() {
        let pending = terminationContinuations
        terminationContinuations = []
        for continuation in pending {
            continuation.resume()
        }
    }

    func cancelRetryTask() {
        retryTask?.cancel()
        retryTask = nil
    }

    func isLauncherRunning(_ proc: Process) -> Bool {
        processLauncher.isProcessRunning(proc)
    }

    func makeProcess() -> Process {
        processLauncher.makeProcess()
    }

    func launch(_ proc: Process) throws {
        try processLauncher.launch(proc)
    }

    func waitForTermination(
        isIdle: @escaping () -> Bool,
        timeout: Duration? = nil
    ) async throws {
        if isIdle(), process == nil { return }
        let waitTimeout = timeout ?? terminationWaitTimeout

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    if isIdle(), self.process == nil {
                        continuation.resume()
                        return
                    }
                    self.terminationContinuations.append(continuation)
                }
            }
            group.addTask {
                try await Task.sleep(for: waitTimeout)
                throw TerminationWaitError.timedOut
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    @discardableResult
    func finishStopWithEscalation(isIdle: @escaping () -> Bool) async -> Bool {
        guard process != nil else {
            clearPipeHandlers()
            return true
        }
        do {
            try await waitForTermination(isIdle: isIdle)
            return true
        } catch {
            if let proc = process, processLauncher.isProcessRunning(proc), proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
            }
            do {
                try await waitForTermination(isIdle: isIdle)
                return true
            } catch {
                // Fail closed: drop the orphaned handle so the manager can leave `.stopping`.
                _ = takeProcess()
                clearPipeHandlers()
                resumeTerminationWaiters()
                return false
            }
        }
    }

    /// Schedules reconnect attempts. `attemptStart` should call the manager's start path
    /// without resetting the retry counter. Returns whether a running process was recovered.
    func scheduleAutoRetry(
        setReconnectingBanner: @escaping (_ attempt: Int, _ maxAttempts: Int) -> Void,
        setExhausted: @escaping (_ message: String) -> Void,
        isStillReconnecting: @escaping () -> Bool,
        attemptStart: @escaping () -> Bool
    ) {
        cancelRetryTask()
        retryGeneration += 1
        retryAttempt += 1
        if retryAttempt > maxRetryAttempts {
            let message = "Bridge stopped after \(maxRetryAttempts) retries — click Start to try again"
            setExhausted(message)
            return
        }

        setReconnectingBanner(retryAttempt, maxRetryAttempts)

        retryTask = Task { @MainActor in
            while !Task.isCancelled {
                let delayIndex = min(self.retryAttempt - 1, self.retryDelays.count - 1)
                let delay = self.retryDelays[delayIndex]
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                guard isStillReconnecting() else { return }

                if attemptStart() {
                    self.retryAttempt = 0
                    return
                }

                self.retryAttempt += 1
                if self.retryAttempt > self.maxRetryAttempts {
                    let message =
                        "Bridge stopped after \(self.maxRetryAttempts) retries — click Start to try again"
                    setExhausted(message)
                    return
                }

                setReconnectingBanner(self.retryAttempt, self.maxRetryAttempts)
            }
        }
    }

    private enum TerminationWaitError: Error {
        case timedOut
    }
}
