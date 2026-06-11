import Foundation

protocol ProcessLaunching: AnyObject {
    func makeProcess() -> Process
    func launch(_ process: Process) throws
    func isProcessRunning(_ process: Process) -> Bool
}

final class LiveProcessLauncher: ProcessLaunching {
    func makeProcess() -> Process { Process() }

    func launch(_ process: Process) throws {
        try process.run()
    }

    func isProcessRunning(_ process: Process) -> Bool {
        process.isRunning
    }
}
