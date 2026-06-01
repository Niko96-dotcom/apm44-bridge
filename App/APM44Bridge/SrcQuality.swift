import Foundation

enum SrcQuality: String, CaseIterable, Identifiable {
    case medium
    case high
    case best

    var id: String { rawValue }

    var cliArgument: String { rawValue }

    var menuTitle: String {
        switch self {
        case .medium: return "Standard"
        case .high: return "High"
        case .best: return "Best (higher CPU)"
        }
    }
}
