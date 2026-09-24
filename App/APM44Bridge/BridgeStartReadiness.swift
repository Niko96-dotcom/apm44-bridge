import Foundation

enum BridgeStartReadiness {
    static func blockedReason(
        binaryMissing: Bool,
        selectedUid: String?,
        devices: [AudioDeviceRow],
        lastKnownName: String,
        halDevicePresent: Bool = false,
        appBuildID: String? = nil,
        driverBuildID: String? = nil
    ) -> String? {
        if binaryMissing {
            return AppStrings.bridgeNotFound
        }
        guard let selectedUid else {
            return AppStrings.chooseOutputToStart
        }
        // In HAL mode the installed driver build ID must match the app's
        // full build ID before Start. Missing/malformed IDs fail closed.
        // When the HAL device is absent (BlackHole fallback) a missing
        // driver must not block.
        if halDevicePresent,
           !HalDriverDetector.buildIDsMatch(appBuildID: appBuildID, driverBuildID: driverBuildID) {
            return AppStrings.driverBuildMismatch
        }
        guard let selected = devices.first(where: { $0.uid == selectedUid }) else {
            return AppStrings.previousOutputUnavailable(name: lastKnownName)
        }
        if let issue = selected.compatibilityIssue {
            return AppStrings.selectedOutputIncompatible(issue: AppStrings.compatibility(issue))
        }
        return nil
    }
}
