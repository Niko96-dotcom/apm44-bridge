import Foundation

protocol ProcessLaunching: AnyObject {
    func makeProcess() -> Process
    func launch(_ process: Process) throws
    func isProcessRunning(_ process: Process) -> Bool
    func terminationStatus(of process: Process) -> Int32
}

final class LiveProcessLauncher: ProcessLaunching {
    func makeProcess() -> Process { Process() }

    func launch(_ process: Process) throws {
        try process.run()
    }

    func isProcessRunning(_ process: Process) -> Bool {
        process.isRunning
    }

    func terminationStatus(of process: Process) -> Int32 {
        process.terminationStatus
    }
}
