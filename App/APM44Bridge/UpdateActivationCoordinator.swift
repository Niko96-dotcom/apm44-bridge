import AppKit
import Foundation

/// Isolates NSApp side effects behind injected closures so unit tests can
/// verify the accessory -> regular -> accessory transitions without touching
/// NSApp, starting a real SPUUpdater, or hitting the network.
@MainActor
final class UpdateActivationCoordinator {
    var activationPolicySetter: @MainActor (NSApplication.ActivationPolicy) -> Bool
    var appActivator: @MainActor () -> Void
    var panelDismisser: @MainActor () -> Void
    var deferredRunner: @MainActor (@escaping @MainActor () -> Void) -> Void
    var isAppActive: @MainActor () -> Bool
    var attentionRequester: @MainActor () -> Int
    var attentionCanceller: @MainActor (Int) -> Void
    private var didElevateActivationPolicy = false
    private var outstandingAttentionRequest: Int?
    private var activeObserver: NSObjectProtocol?

    init(
        activationPolicySetter: @escaping @MainActor (NSApplication.ActivationPolicy) -> Bool,
        appActivator: @escaping @MainActor () -> Void,
        panelDismisser: @escaping @MainActor () -> Void,
        deferredRunner: @escaping @MainActor (@escaping @MainActor () -> Void) -> Void = { work in
            DispatchQueue.main.async {
                Task { @MainActor in work() }
            }
        },
        isAppActive: @escaping @MainActor () -> Bool = { NSApp.isActive },
        attentionRequester: @escaping @MainActor () -> Int = { NSApp.requestUserAttention(.criticalRequest) },
        attentionCanceller: @escaping @MainActor (Int) -> Void = { NSApp.cancelUserAttentionRequest($0) }
    ) {
        self.activationPolicySetter = activationPolicySetter
        self.appActivator = appActivator
        self.panelDismisser = panelDismisser
        self.deferredRunner = deferredRunner
        self.isAppActive = isAppActive
        self.attentionRequester = attentionRequester
        self.attentionCanceller = attentionCanceller
        self.activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleAppDidBecomeActive()
            }
        }
    }

    func bringUpdateUIToFront() {
        panelDismisser()
        _ = activationPolicySetter(.regular)
        didElevateActivationPolicy = true
        appActivator()
        if isAppActive() {
            cancelOutstandingAttentionRequest()
        } else if outstandingAttentionRequest == nil {
            outstandingAttentionRequest = attentionRequester()
        }
    }

    func handleAppDidBecomeActive() {
        cancelOutstandingAttentionRequest()
    }

    private func cancelOutstandingAttentionRequest() {
        guard let requestId = outstandingAttentionRequest else { return }
        outstandingAttentionRequest = nil
        attentionCanceller(requestId)
    }

    /// Schedules one more activation on the next main-queue turn, so the
    /// post-authorization "Install and Relaunch" status window is ordered
    /// after Sparkle shows it.
    func scheduleDeferredBringToFront() {
        deferredRunner { [weak self] in
            self?.bringUpdateUIToFront()
        }
    }

    /// Post-extraction activation: immediately, plus once more on the next
    /// main-queue turn so it also happens after Sparkle orders its window.
    func bringUpdateUIToFrontAfterExtraction() {
        bringUpdateUIToFront()
        scheduleDeferredBringToFront()
    }

    func willFinishUpdateSession() {
        cancelOutstandingAttentionRequest()
        guard didElevateActivationPolicy else { return }
        didElevateActivationPolicy = false
        let restored = activationPolicySetter(.accessory)
        if !restored {
            deferredRunner { [weak self] in
                guard let self else { return }
                _ = self.activationPolicySetter(.accessory)
            }
        }
    }
}
