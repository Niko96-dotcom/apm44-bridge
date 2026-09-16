import Foundation

enum SrcQuality: String, CaseIterable, Identifiable {
    case medium
    case high
    case best

    var id: String { rawValue }

    var cliArgument: String { rawValue }

    var menuTitle: String {
        switch self {
        case .medium: return AppStrings.qualityStandard
        case .high: return AppStrings.qualityHigh
        case .best: return AppStrings.qualityBest
        }
    }
}
