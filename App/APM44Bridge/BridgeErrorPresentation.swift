import Foundation

/// Why the bridge is in the `.error` state. The case is the error's identity:
/// recovery guidance, the headline and the Details disclosure are chosen from
/// it, never from rendered (localized) text. Payloads carry raw facts (build
/// IDs, exit status, stderr), not localized wording.
enum BridgeError: Equatable {
    case bridgeNotFound
    case selectOutputDevice
    case selectedOutputGone
    /// `issue` is the English compatibility key from `AudioDeviceRow`.
    case selectedOutputIncompatible(issue: String?)
    case outputDeviceDisconnected
    case bridgeDidNotStop
    /// A nil build ID is a missing or malformed one.
    case driverBuildMismatch(appBuildID: String?, driverBuildID: String?)
    case loadedDriverBuildMismatch
    case helperAlreadyRunning
    case driverIPCFailed
    /// The helper could not be launched; `detail` is already sanitized.
    case launchFailed(detail: String)
    /// Retries ran out; `lastStderr` is already sanitized.
    case unstableLaunches(maxAttempts: Int, lastExitStatus: Int32?, lastStderr: String?)
    /// The helper failed for a reason the app does not classify. `stderr` is
    /// the helper's last line, verbatim; nil when it printed nothing.
    case helperFailed(stderr: String?)

    /// The full localized sentence for banners and the Details disclosure.
    var message: String {
        switch self {
        case .bridgeNotFound:
            return AppStrings.bridgeNotFound
        case .selectOutputDevice:
            return AppStrings.selectOutputDevice
        case .selectedOutputGone:
            return AppStrings.selectedOutputGone
        case .selectedOutputIncompatible(let issue):
            return AppStrings.selectedOutputIncompatible(issue: Self.compatibilityText(issue))
        case .outputDeviceDisconnected:
            return AppStrings.outputDeviceDisconnected
        case .bridgeDidNotStop:
            return AppStrings.bridgeDidNotStop
        case .driverBuildMismatch(let appBuildID, let driverBuildID):
            return AppStrings.driverBuildMismatchDetail(
                app: appBuildID ?? AppStrings.buildIDMissingPlaceholder,
                driver: driverBuildID ?? AppStrings.buildIDMissingPlaceholder
            )
        case .loadedDriverBuildMismatch:
            return AppStrings.loadedDriverBuildMismatch
        case .helperAlreadyRunning:
            return AppStrings.helperAlreadyRunning
        case .driverIPCFailed:
            return AppStrings.ipcFailed()
        case .launchFailed(let detail):
            return AppStrings.bridgeCouldNotStart(detail: detail)
        case .unstableLaunches(let maxAttempts, let lastExitStatus, let lastStderr):
            var detail = ""
            if let lastExitStatus {
                detail = AppStrings.lastExit(Int(lastExitStatus))
            }
            if let lastStderr, !lastStderr.isEmpty {
                detail += ": \(lastStderr)"
            }
            return AppStrings.stoppedAfterUnstableLaunches(maxAttempts, detail: detail)
        case .helperFailed(let stderr):
            return stderr ?? AppStrings.couldNotStart
        }
    }

    /// The short status headline. Known conditions read as their own
    /// sentence; everything else is the generic "could not start".
    var headline: String {
        switch self {
        case .driverBuildMismatch:
            return AppStrings.driverBuildMismatch
        case .launchFailed, .unstableLaunches, .helperFailed:
            return AppStrings.couldNotStart
        default:
            return message
        }
    }

    /// What the user should do next; nil when the headline already says it.
    var recovery: BridgeErrorRecovery? {
        switch self {
        case .bridgeNotFound, .driverIPCFailed:
            return nil
        case .selectOutputDevice, .selectedOutputGone:
            return .chooseOutput
        case .outputDeviceDisconnected:
            return .selectDisconnectedOutput
        case .bridgeDidNotStop, .launchFailed, .unstableLaunches, .helperFailed:
            return .tryAgain
        case .driverBuildMismatch:
            return .reinstallDriver
        case .loadedDriverBuildMismatch:
            return .reloadCoreAudio
        case .helperAlreadyRunning:
            return .quitOtherHelper
        case .selectedOutputIncompatible:
            return .chooseCompatibleOutput
        }
    }

    /// Text for the selectable Details disclosure: what the headline leaves
    /// out. Helper stderr is kept verbatim.
    var diagnostic: String? {
        switch self {
        case .driverBuildMismatch, .launchFailed, .unstableLaunches:
            return message
        case .helperFailed(let stderr):
            return stderr
        default:
            return nil
        }
    }

    /// The compatibility key is the English text; `compatibility` looks up
    /// its localization.
    static func compatibilityText(_ issue: String?) -> String {
        issue.map(AppStrings.compatibility) ?? AppStrings.unsupportedPrefix
    }
}

/// Recovery guidance, chosen by error kind and rendered separately.
enum BridgeErrorRecovery: Equatable {
    case chooseOutput
    case selectDisconnectedOutput
    case tryAgain
    case reinstallDriver
    case reloadCoreAudio
    case quitOtherHelper
    case chooseCompatibleOutput

    var text: String {
        switch self {
        case .chooseOutput: return AppStrings.chooseOutputToStart
        case .selectDisconnectedOutput: return AppStrings.outputDisconnectedSelect
        case .tryAgain: return AppStrings.genericFailureRecovery
        case .reinstallDriver: return AppStrings.driverBuildMismatchRecovery
        case .reloadCoreAudio: return AppStrings.loadedDriverBuildMismatchRecovery
        case .quitOtherHelper: return AppStrings.helperAlreadyRunningRecovery
        case .chooseCompatibleOutput: return AppStrings.incompatibleOutputRecovery
        }
    }
}

/// F2: turns a `BridgeError` into a short localized headline, mapped
/// recovery guidance, and an optional full diagnostic for a details
/// disclosure.
///
/// Helper jargon (the last stderr line) is never the status headline: showing
/// it truncated hides its useful ending and gives no recovery path. The
/// status shows a short headline, the detail area shows recovery, and the full
/// diagnostic stays selectable under Details.
enum BridgeErrorPresentation {
    struct Presentation: Equatable {
        let headline: String
        let recovery: String?
        let diagnostic: String?
    }

    static func presentation(for error: BridgeError) -> Presentation {
        Presentation(
            headline: error.headline,
            recovery: error.recovery?.text,
            diagnostic: error.diagnostic
        )
    }

    static func headline(for error: BridgeError) -> String {
        error.headline
    }
}
