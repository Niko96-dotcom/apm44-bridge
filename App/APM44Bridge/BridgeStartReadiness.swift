import Foundation

enum BridgeStartReadiness {
    static func blockedReason(
        binaryMissing: Bool,
        selectedUid: String?,
        devices: [AudioDeviceRow],
        lastKnownName: String
    ) -> String? {
        if binaryMissing {
            return AppStrings.bridgeNotFound
        }
        guard let selectedUid else {
            return AppStrings.chooseOutputToStart
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
