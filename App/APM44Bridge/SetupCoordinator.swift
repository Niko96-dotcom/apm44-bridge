import Foundation

/// Single presentation owner for the Setup sheet.
///
/// `MenuContentView` exists in up to three hosts at once (menu-bar popover,
/// Settings scene, Controls window). Broadcasting a presentation boolean to
/// every instance creates duplicate modal sheets (F3). This coordinator holds
/// a persistent request flag so only the designated owner — the Controls
/// window — presents Setup, and so a request posted before the Controls view
/// subscribes is still honoured on appear.
@MainActor
final class SetupCoordinator: ObservableObject {
    static let shared = SetupCoordinator()

    @Published private(set) var isSetupRequested = false
    private(set) var didClaimFirstRunAuto = false

    func requestSetup() {
        isSetupRequested = true
    }

    func consumeSetupRequest() {
        isSetupRequested = false
    }

    /// First-run auto-presentation is first-come-wins across hosts so the
    /// initial Setup appears once even when several windows exist.
    /// Help requests remain single-owner (Controls) via `isSetupRequested`.
    func claimFirstRunAuto() -> Bool {
        guard !didClaimFirstRunAuto else { return false }
        didClaimFirstRunAuto = true
        return true
    }

    internal func resetForTesting() {
        isSetupRequested = false
        didClaimFirstRunAuto = false
    }
}
