import Foundation

/// Menu-bar status tint without touching SwiftUI. The view maps this to
/// `Color` exactly as `statusTint` does today.
enum MenuStatusTone: Equatable {
    case secondary
    case orange
    case green
    case red
}

/// Tint for the update-status rows. Kept separate because installing uses
/// `.accentColor`, which the bridge status tint never uses.
enum MenuUpdateTone: Equatable {
    case secondary
    case accent
    case orange
}

enum MenuUpdateActionKind: Equatable {
    case checkForUpdates
    case showPendingUpdate
}

enum MenuUpdateSection: Equatable {
    case hidden
    case status(message: String, systemImage: String, tone: MenuUpdateTone)
    case action(title: String, kind: MenuUpdateActionKind, accessibilityIdentifier: String?)
    case failed(message: String, retryVersionText: String?)
}

/// Pure, synchronous presentation model for `MenuContentView`.
///
/// Built from plain values (never a `BridgeProcessManager`) so it is
/// unit-testable. The view keeps its layout and just reads from this type.
struct MenuPresentation {
    let state: BridgeRunState
    let isApplyingSettings: Bool
    let connectionPhase: BridgeConnectionPhase
    let bannerMessage: String?
    let metricsStale: Bool
    let startBlockedReason: String?
    let latestMetrics: BridgeMetricsSnapshot?
    let heldMetrics: BridgeMetricsSnapshot?


    var isRunning: Bool { state.isRunning }
    var isTransitioning: Bool { state.isTransitioning }

    var showsStartButton: Bool {
        if isApplyingSettings { return false }
        switch state {
        case .idle, .error: return true
        case .starting, .running, .stopping, .reconnecting: return false
        }
    }

    var showsStopButton: Bool {
        if isApplyingSettings { return true }
        switch state {
        case .running, .reconnecting: return true
        case .idle, .starting, .stopping, .error: return false
        }
    }

    var showsRestartButton: Bool {
        if isApplyingSettings { return true }
        switch state {
        case .running, .error: return true
        case .idle, .starting, .stopping, .reconnecting: return false
        }
    }

    var startEnabled: Bool {
        startBlockedReason == nil && !isTransitioning
    }

    var stopDisabled: Bool {
        isTransitioning || isApplyingSettings
    }

    var restartDisabled: Bool {
        isTransitioning || isApplyingSettings || startBlockedReason != nil
    }

    var quitDisabled: Bool {
        isTransitioning
    }

    /// The blocked reason only when the start button is visible and settings
    /// are not being applied (mirrors the body's `if let` conditions).
    var visibleStartBlockedReason: String? {
        guard showsStartButton, !isApplyingSettings else { return nil }
        return startBlockedReason
    }

    var statusText: String {
        if isApplyingSettings {
            return AppStrings.applyingSettings
        }
        if isRunning {
            return connectionPhase.label
        }
        switch state {
        case .idle: return AppStrings.stopped
        case .starting: return AppStrings.starting
        case .running: return connectionPhase.label
        case .stopping: return AppStrings.stopping
        case .reconnecting:
            if let banner = bannerMessage {
                return banner
            }
            return AppStrings.reconnecting
        case .error(let message):
            // Never truncate helper jargon into the headline. Use a short
            // localized headline; the full diagnostic lives under Details.
            return BridgeErrorPresentation.headline(for: message)
        }
    }

    /// Banner that duplicates the raw error diagnostic is suppressed — the
    /// error section already shows headline + recovery + Details.
    var visibleBanner: String? {
        guard let banner = bannerMessage else { return nil }
        if case .error(let message) = state,
           banner == message,
           BridgeErrorPresentation.presentation(for: message).diagnostic != nil {
            return nil
        }
        return banner
    }

    var statusSymbol: String {
        if isApplyingSettings { return "arrow.triangle.2.circlepath" }
        switch state {
        case .error: return "exclamationmark.triangle.fill"
        case .reconnecting: return "arrow.triangle.2.circlepath"
        case .running: return "waveform"
        case .idle, .starting, .stopping: return "headphones"
        }
    }

    var statusTone: MenuStatusTone {
        if isApplyingSettings { return .orange }
        switch state {
        case .error: return .red
        case .reconnecting, .starting: return .orange
        case .running:
            return metricsStale || connectionPhase == .waitingForDAW ? .orange : .green
        case .idle, .stopping: return .secondary
        }
    }

    /// While settings apply, and until the relaunched daemon's first tick,
    /// the last snapshot stays visible (dimmed) so the layout never jumps.
    var effectiveDetailMetrics: BridgeMetricsSnapshot? {
        if isApplyingSettings || isRunning {
            return latestMetrics ?? heldMetrics
        }
        return nil
    }

    var showsHeldMetrics: Bool {
        latestMetrics == nil && effectiveDetailMetrics != nil
    }

    /// True exactly when `clearHeldMetricsIfSettled` would assign
    /// `heldMetrics = nil`.
    var shouldClearHeldMetrics: Bool {
        guard !isApplyingSettings else { return false }
        switch state {
        case .idle, .error: return true
        default: return false
        }
    }

    /// The details section only exists when it holds content: live metrics,
    /// or an error with recovery guidance/a diagnostic. No empty chrome.
    /// While settings are being applied the last seen snapshot stays visible
    /// (dimmed) so the popover height does not jump.
    var showsStatusDetail: Bool {
        if effectiveDetailMetrics != nil { return true }
        if case .error(let message) = state { return Self.errorHasContent(message) }
        return false
    }

    static func errorHasContent(_ message: String) -> Bool {
        let presentation = BridgeErrorPresentation.presentation(for: message)
        return presentation.recovery != nil || presentation.diagnostic != nil
    }

    // MARK: - Update section

    static func updateSection(
        for state: AppUpdateState,
        lastOfferedVersion: String?
    ) -> MenuUpdateSection {
        switch state {
        case .idle:
            return .hidden
        case .checking:
            return .status(
                message: AppStrings.checkingUpdates,
                systemImage: "arrow.triangle.2.circlepath",
                tone: .secondary
            )
        case let .available(version):
            return .action(
                title: AppStrings.updateAvailable(version),
                kind: .checkForUpdates,
                accessibilityIdentifier: nil
            )
        case let .readyToInstall(version):
            return .action(
                title: AppStrings.installUpdateAndRelaunch(version),
                kind: .showPendingUpdate,
                accessibilityIdentifier: "install-update"
            )
        case let .installing(version):
            return .status(
                message: AppStrings.installingUpdate(version),
                systemImage: "gearshape",
                tone: .accent
            )
        case .cancelled:
            return .status(
                message: AppStrings.updateCancelled,
                systemImage: "xmark.circle",
                tone: .secondary
            )
        case let .failed(message):
            return .failed(
                message: message,
                retryVersionText: lastOfferedVersion.map { AppStrings.updateAvailable($0) }
            )
        }
    }
}
