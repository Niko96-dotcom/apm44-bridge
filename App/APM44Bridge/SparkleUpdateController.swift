import AppKit
import Combine
import Foundation
import OSLog
import Sparkle

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.niko.apm44.menu",
    category: "Updates"
)

/// Sparkle's standard UI remains responsible for release notes, download
/// progress, administrator authorization, cancellation, installation, and
/// relaunch. This observable bridge supplies a small musician-facing status
/// surface for the menu-bar popover and deliberately keeps no persisted
/// "update available" flag, so a successful relaunch cannot show stale state.
@MainActor
final class SparkleUpdateController: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = SparkleUpdateController()

    @Published private(set) var state: AppUpdateState = .idle
    @Published private(set) var canCheckForUpdates = false
    /// Last version Sparkle offered, kept across download failures so the
    /// panel still shows that an update exists and can retry it.
    @Published private(set) var lastOfferedVersion: String?

    private(set) var updaterController: SPUStandardUpdaterController!
    private let currentVersion: String
    private let launchDate: Date
    private var didEvaluateLaunchCheck = false
    private let activation: UpdateActivationCoordinator
    /// Latched when `didAbortWithError` accepts an installation error as
    /// "already installed", so the following `didFinishUpdateCycleFor` with
    /// the same error does not fail. Reset at the start of the next check
    /// and in `didFinishUpdateCycleFor` after handling.
    var benignInstallationSuccessLatched = false

    init(
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0",
        activationPolicySetter: @escaping @MainActor (NSApplication.ActivationPolicy) -> Bool = { NSApp.setActivationPolicy($0) },
        appActivator: @escaping @MainActor () -> Void = {
            if #available(macOS 14, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        },
        menuPanelDismisser: @escaping @MainActor () -> Void = { dismissMenuBarPanel() },
        deferredRunner: @escaping @MainActor (@escaping @MainActor () -> Void) -> Void = { work in
            DispatchQueue.main.async {
                Task { @MainActor in work() }
            }
        },
        isAppActive: @escaping @MainActor () -> Bool = { NSApp.isActive },
        attentionRequester: @escaping @MainActor () -> Int = { NSApp.requestUserAttention(.criticalRequest) },
        attentionCanceller: @escaping @MainActor (Int) -> Void = { NSApp.cancelUserAttentionRequest($0) },
        startUpdater: Bool = true
    ) {
        self.currentVersion = currentVersion
        self.launchDate = Date()
        self.activation = UpdateActivationCoordinator(
            activationPolicySetter: activationPolicySetter,
            appActivator: appActivator,
            panelDismisser: menuPanelDismisser,
            deferredRunner: deferredRunner,
            isAppActive: isAppActive,
            attentionRequester: attentionRequester,
            attentionCanceller: attentionCanceller
        )
        super.init()

        guard startUpdater else { return }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )

        // Mirror Sparkle's readiness so manual UI can disable itself.
        // Assigned on the main thread; Sparkle mutates this KVO property
        // on the main thread.
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    var updater: SPUUpdater { updaterController.updater }

    /// True while the generic manual check is allowed. Available and
    /// ready-to-install stay allowed even when `canCheckForUpdates` is false
    /// (a deferred scheduled update keeps Sparkle's session open), so the
    /// footer link and the panel can reach showPendingUpdate; checking and
    /// installing stay blocked because a new check would overwrite status.
    var canStartManualCheck: Bool {
        Self.canStartManualCheck(canCheckForUpdates: canCheckForUpdates, state: state)
    }

    nonisolated static func canStartManualCheck(canCheckForUpdates: Bool, state: AppUpdateState) -> Bool {
        switch state {
        case .available, .readyToInstall:
            return true
        case .checking, .installing:
            return false
        case .idle, .cancelled, .failed:
            return canCheckForUpdates
        }
    }

    /// The available (possibly deferred scheduled update) and the
    /// downloaded, ready-to-install states may bring Sparkle's pending UI
    /// back into focus.
    nonisolated static func canShowPendingUpdate(state: AppUpdateState) -> Bool {
        switch state {
        case .available, .readyToInstall:
            return true
        default:
            return false
        }
    }

    func checkForUpdates() {
        switch state {
        case .available, .readyToInstall:
            showPendingUpdate()
            return
        default:
            break
        }
        guard updater.canCheckForUpdates, canStartManualCheck else { return }
        benignInstallationSuccessLatched = false
        logger.info("Checking for updates")
        state = .checking
        updaterController.checkForUpdates(nil)
    }

    /// Brings Sparkle's pending or deferred update back into focus. Sparkle's
    /// `checkForUpdates` shows an in-progress or deferred update in focus
    /// instead of failing, so this intentionally consults no
    /// `canCheckForUpdates` guard.
    func showPendingUpdate() {
        guard Self.canShowPendingUpdate(state: state) else { return }
        guard updaterController != nil else { return }
        bringUpdateUIToFront()
        updaterController.checkForUpdates(nil)
    }

    func bringUpdateUIToFront() {
        activation.bringUpdateUIToFront()
    }

    /// Test hook: seeds the state machine without involving Sparkle.
    func seedStateForTests(_ newState: AppUpdateState) {
        state = newState
    }

    // MARK: SPUStandardUserDriverDelegate (gentle reminders for accessory app)

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if handleShowingUpdate {
            bringUpdateUIToFront()
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        bringUpdateUIToFront()
    }

    func standardUserDriverWillShowModalAlert() {
        bringUpdateUIToFront()
    }

    func standardUserDriverWillFinishUpdateSession() {
        activation.willFinishUpdateSession()
    }

    // MARK: SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        guard !didEvaluateLaunchCheck else { return }
        didEvaluateLaunchCheck = true
        guard Self.shouldRunLaunchCheck(
            automaticallyChecks: updater.automaticallyChecksForUpdates,
            lastCheckDate: updater.lastUpdateCheckDate,
            launchDate: launchDate
        ) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let liveUpdater = self.updaterController.updater
            guard !liveUpdater.sessionInProgress, liveUpdater.canCheckForUpdates else { return }
            self.benignInstallationSuccessLatched = false
            logger.info("Checking for updates")
            self.state = .checking
            liveUpdater.checkForUpdatesInBackground()
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard AppUpdateVersionComparator.isNewer(item.versionString, than: currentVersion) else {
            logger.info("Ignored non-newer update")
            state = .idle
            return
        }
        logger.info("Update available version=\(item.displayVersionString, privacy: .public)")
        lastOfferedVersion = item.displayVersionString
        state = .available(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        if Self.isNoUpdateError(error) {
            logger.info("No update available")
            state = .idle
            lastOfferedVersion = nil
        } else {
            failCheck(error)
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        logger.info("No update available")
        state = .idle
        lastOfferedVersion = nil
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        logger.info("Update downloaded version=\(item.displayVersionString, privacy: .public)")
        lastOfferedVersion = item.displayVersionString
        state = .readyToInstall(version: item.displayVersionString)
        bringUpdateUIToFront()
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        lastOfferedVersion = item.displayVersionString
        failDownload(error)
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        logger.info("Update cancelled")
        state = .cancelled
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        NotificationCenter.default.post(name: .apm44WillInstallUpdate, object: nil)
        logger.info("Installing update version=\(item.displayVersionString, privacy: .public)")
        lastOfferedVersion = item.displayVersionString
        state = .installing(version: item.displayVersionString)
        bringUpdateUIToFront()
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        handleDidExtract()
    }

    /// Post-authorization activation: immediately, plus once more on the next
    /// main-queue turn so it also happens after Sparkle orders its
    /// "Ready to Install / Install and Relaunch" status window.
    func handleDidExtract() {
        bringUpdateUIToFront()
        activation.scheduleDeferredBringToFront()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        handleAbort(error: error)
    }

    func handleAbort(error: Error) {
        if benignInstallationSuccessLatched {
            markAlreadyInstalled()
            return
        }
        let outcome = Self.classifyUpdateCycleError(
            state: state,
            error: error,
            currentVersion: currentVersion
        )
        if outcome == .alreadyInstalled {
            benignInstallationSuccessLatched = true
        }
        applyUpdateCycleOutcome(outcome, error: error)
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        handleFinish(error: error)
    }

    func handleFinish(error: Error?) {
        defer { benignInstallationSuccessLatched = false }
        if benignInstallationSuccessLatched {
            markAlreadyInstalled()
            return
        }
        guard let error else {
            if case .checking = state { state = .idle }
            return
        }
        applyUpdateCycleOutcome(
            Self.classifyUpdateCycleError(state: state, error: error, currentVersion: currentVersion),
            error: error
        )
    }

    private func applyUpdateCycleOutcome(_ outcome: UpdateCycleErrorOutcome, error: Error) {
        switch outcome {
        case .alreadyInstalled:
            markAlreadyInstalled()
        case .noUpdate:
            state = .idle
            lastOfferedVersion = nil
        case .cancelled:
            logger.info("Update cancelled")
            state = .cancelled
        case .failed:
            fail(error)
        }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        // The standard Sparkle UI owns the install-on-quit decision. Returning
        // false lets it request admin authorization and relaunch safely.
        // The update is waiting for quit, not installing yet, so only record
        // readiness here; `willInstallUpdate` alone posts the resume signal.
        handleWillInstallUpdateOnQuit(versionString: item.displayVersionString)
        return false
    }

    func handleWillInstallUpdateOnQuit(versionString: String) {
        logger.info("Update ready to install on quit version=\(versionString, privacy: .public)")
        lastOfferedVersion = versionString
        state = .readyToInstall(version: versionString)
    }

    private func markAlreadyInstalled() {
        logger.info("Update already installed")
        state = .idle
        lastOfferedVersion = nil
    }

    private func fail(_ error: Error, message: @autoclosure () -> String) {
        if Self.shouldTreatInstallationErrorAsSuccess(
            state: state,
            error: error,
            currentVersion: currentVersion
        ) {
            markAlreadyInstalled()
            return
        }
        let nsError = error as NSError
        logger.error("Update failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code)")
        state = .failed(message: message())
    }

    private func failCheck(_ error: Error) {
        fail(error, message: Self.userFacingErrorMessage(error))
    }

    private func failDownload(_ error: Error) {
        fail(error, message: Self.downloadErrorMessage(error))
    }

    private func fail(_ error: Error) {
        if Self.isDownloadFailure(error) {
            failDownload(error)
        } else {
            failCheck(error)
        }
    }

    nonisolated static func shouldRunLaunchCheck(
        automaticallyChecks: Bool,
        lastCheckDate: Date?,
        launchDate: Date
    ) -> Bool {
        guard automaticallyChecks else { return false }
        guard let lastCheckDate else { return true }
        return lastCheckDate < launchDate
    }
}
