import Foundation
import Darwin

protocol ProcessLaunching: AnyObject {
    func makeProcess() -> Process
    func launch(_ process: Process) throws
    func isProcessRunning(_ process: Process) -> Bool
    /// Best-effort hard stop used after escalation timeouts / orphan recovery.
    func forceStop(_ process: Process)
}

final class LiveProcessLauncher: ProcessLaunching {
    func makeProcess() -> Process { Process() }

    func launch(_ process: Process) throws {
        try process.run()
    }

    func isProcessRunning(_ process: Process) -> Bool {
        process.isRunning
    }

    func forceStop(_ process: Process) {
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}
