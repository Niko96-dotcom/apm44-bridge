import Foundation

/// Privileged maintenance actions for the installed HAL driver.
///
/// The menu bar app is not sandboxed, so it can present the standard macOS
/// authorization prompt and reload Core Audio directly. This lets a freshly
/// installed driver load without asking the user to open Terminal or reboot in
/// the common case.
enum DriverMaintenance {
    /// Reload Core Audio behind a one-shot admin prompt so a just-installed HAL
    /// driver is enumerated. `coreaudiod` respawns automatically after it is
    /// killed. Returns `true` when the reload was authorized and ran, `false`
    /// when the user cancelled the prompt or it otherwise failed.
    ///
    /// Runs `osascript` (which the app already relies on for process launching)
    /// rather than `NSAppleScript`, so it is safe to call from a background
    /// task. Blocking; call off the main thread.
    @discardableResult
    static func reloadCoreAudioWithPrivileges() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \"/usr/bin/killall coreaudiod\" with administrator privileges",
        ]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
