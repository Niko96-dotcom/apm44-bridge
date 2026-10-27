import Foundation

enum BridgeStartReadiness {
    /// The Start gate: the first condition that blocks a launch, or nil when
    /// the bridge may start. Pure, so both callers share one rule set:
    /// `BridgeProcessManager.start()` passes the live HAL build check and
    /// stores the returned error; `startBlockedReason` passes cached inputs
    /// and renders the error with `BridgeError.startBlockedText(outputName:)`.
    static func blocker(
        binaryMissing: Bool,
        selectedUid: String?,
        devices: [AudioDeviceRow],
        halDevicePresent: Bool,
        appBuildID: String?,
        driverBuildID: String?
    ) -> BridgeError? {
        if binaryMissing {
            return .bridgeNotFound
        }
        guard let selectedUid, !selectedUid.isEmpty else {
            return .selectOutputDevice
        }
        // In HAL mode the installed driver build ID must match the app's
        // full build ID before Start. Missing/malformed IDs fail closed.
        // When the HAL device is absent (BlackHole fallback) a missing
        // driver must not block.
        if halDevicePresent,
           !HalDriverDetector.buildIDsMatch(appBuildID: appBuildID, driverBuildID: driverBuildID) {
            return .driverBuildMismatch(
                appBuildID: HalDriverDetector.normalizedBuildID(appBuildID),
                driverBuildID: HalDriverDetector.normalizedBuildID(driverBuildID)
            )
        }
        guard let selected = devices.first(where: { $0.uid == selectedUid }) else {
            return .selectedOutputGone
        }
        if let issue = selected.compatibilityIssue {
            return .selectedOutputIncompatible(issue: issue)
        }
        return nil
    }
}
