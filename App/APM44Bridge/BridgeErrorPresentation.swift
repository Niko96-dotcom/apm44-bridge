import Foundation

/// F2: maps a raw `.error(String)` payload to a short localized headline,
/// mapped recovery guidance, and an optional full diagnostic for a
/// details disclosure.
///
/// The manager can store the final non-SHM stderr line (helper jargon) as
/// the error string. Showing that line truncated as the status headline
/// hides its useful ending and gives no recovery path. Instead the status
/// shows a short headline, the detail area shows recovery, and the full
/// diagnostic stays selectable under Details.
enum BridgeErrorPresentation {
    struct Presentation: Equatable {
        let headline: String
        let recovery: String?
        let diagnostic: String?
    }

    static func presentation(for message: String) -> Presentation {
        // Known short, user-facing messages stay as the headline.
        if message == AppStrings.bridgeNotFound {
            return Presentation(headline: message, recovery: nil, diagnostic: nil)
        }
        if message == AppStrings.selectOutputDevice {
            return Presentation(
                headline: message,
                recovery: AppStrings.chooseOutputToStart,
                diagnostic: nil
            )
        }
        if message == AppStrings.selectedOutputGone {
            return Presentation(
                headline: message,
                recovery: AppStrings.chooseOutputToStart,
                diagnostic: nil
            )
        }
        if message == AppStrings.outputDeviceDisconnected {
            return Presentation(
                headline: message,
                recovery: AppStrings.outputDisconnectedSelect,
                diagnostic: nil
            )
        }
        if message == AppStrings.bridgeDidNotStop {
            return Presentation(
                headline: message,
                recovery: AppStrings.genericFailureRecovery,
                diagnostic: nil
            )
        }
        if message == AppStrings.ipcFailed() {
            // Already contains recovery ("reinstall driver and reload…").
            return Presentation(headline: message, recovery: nil, diagnostic: nil)
        }
        if message == AppStrings.couldNotStart {
            return Presentation(
                headline: message,
                recovery: AppStrings.genericFailureRecovery,
                diagnostic: nil
            )
        }
        if isSelectedOutputIncompatible(message) {
            return Presentation(
                headline: message,
                recovery: AppStrings.incompatibleOutputRecovery,
                diagnostic: nil
            )
        }
        // Generic path: helper failure, bridgeCouldNotStart(detail:), or
        // unstable-launch summary with embedded stderr. Short headline plus
        // recovery, full text kept for Details.
        return Presentation(
            headline: AppStrings.couldNotStart,
            recovery: AppStrings.genericFailureRecovery,
            diagnostic: message
        )
    }

    static func headline(for message: String) -> String {
        presentation(for: message).headline
    }

    /// Detects `selectedOutputIncompatible(issue:)` across locales by
    /// splitting the localized template around a marker detail.
    private static func isSelectedOutputIncompatible(_ message: String) -> Bool {
        let marker = "__APM44_ISSUE__"
        let template = AppStrings.selectedOutputIncompatible(issue: marker)
        let parts = template.components(separatedBy: marker)
        guard parts.count == 2 else {
            return message.hasPrefix("Selected output is not compatible")
                || message.hasPrefix("Gewählte Ausgabe ist nicht kompatibel")
        }
        let prefix = parts[0]
        let suffix = parts[1]
        guard message.hasPrefix(prefix) else { return false }
        if suffix.isEmpty { return true }
        return message.hasSuffix(suffix)
    }
}
