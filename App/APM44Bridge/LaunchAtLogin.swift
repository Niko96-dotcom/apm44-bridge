import Foundation
import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var state: LaunchAtLoginState
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
        state = Self.map(service.status)
    }

    var isEnabled: Bool { state == .enabled }
    var requiresApproval: Bool { state == .requiresApproval }

    func refresh() {
        state = Self.map(service.status)
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
        refresh()
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func map(_ status: SMAppService.Status) -> LaunchAtLoginState {
        switch status {
        case .notRegistered: return .disabled
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }
}
