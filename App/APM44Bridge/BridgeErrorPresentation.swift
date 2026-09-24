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
        if message == AppStrings.driverBuildMismatch {
            return Presentation(
                headline: message,
                recovery: AppStrings.driverBuildMismatchRecovery,
                diagnostic: nil
            )
        }
        if isDriverBuildMismatchDetail(message) {
            return Presentation(
                headline: AppStrings.driverBuildMismatch,
                recovery: AppStrings.driverBuildMismatchRecovery,
                diagnostic: message
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

    /// Detects `driverBuildMismatchDetail(app:driver:)` across locales by
    /// splitting the localized template around two marker IDs. The template
    /// order is driver then app.
    private static func isDriverBuildMismatchDetail(_ message: String) -> Bool {
        let appMarker = "__APM44_APP__"
        let driverMarker = "__APM44_DRIVER__"
        let template = AppStrings.driverBuildMismatchDetail(app: appMarker, driver: driverMarker)
        guard let driverRange = template.range(of: driverMarker),
              let appRange = template.range(of: appMarker) else {
            return message.hasPrefix("Driver build")
                || message.hasPrefix("Treiber-Build")
        }
        // Supports either marker order across locales.
        let firstRange: Range<String.Index>
        let secondMarker: String
        let firstMarker: String
        if driverRange.lowerBound < appRange.lowerBound {
            firstRange = driverRange
            firstMarker = driverMarker
            secondMarker = appMarker
        } else {
            firstRange = appRange
            firstMarker = appMarker
            secondMarker = driverMarker
        }
        let parts = template.components(separatedBy: firstMarker)
        guard parts.count == 2 else { return false }
        let prefix = parts[0]
        let rest = parts[1]
        let middleAndSuffix = rest.components(separatedBy: secondMarker)
        guard middleAndSuffix.count == 2 else { return false }
        let middle = middleAndSuffix[0]
        let suffix = middleAndSuffix[1]
        _ = firstRange
        guard message.hasPrefix(prefix) else { return false }
        if !suffix.isEmpty, !message.hasSuffix(suffix) { return false }
        let withoutPrefix = String(message.dropFirst(prefix.count))
        let core: String
        if suffix.isEmpty {
            core = withoutPrefix
        } else {
            core = String(withoutPrefix.dropLast(suffix.count))
        }
        return core.contains(middle)
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
