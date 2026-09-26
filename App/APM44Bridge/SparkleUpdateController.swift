import AppKit
import Combine
import Foundation
import OSLog
import Sparkle

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.niko.apm44.menu",
    category: "Updates"
)

enum AppUpdateState: Equatable {
    case idle
    case checking
    case available(version: String)
    case readyToInstall(version: String)
    case installing(version: String)
    case cancelled
    case failed(message: String)
}

enum UpdateVersionComparison: Equatable {
    case older
    case same
    case newer
    case invalid
}

/// A small, deterministic comparator used by the app-facing state machine and
/// its tests. Sparkle still performs the authoritative appcast comparison and
/// signature validation; this guard prevents a stale or malformed delegate
/// callback from ever surfacing a downgrade as an update button.
struct AppUpdateVersionComparator {
    static func compare(_ lhs: String, to rhs: String) -> UpdateVersionComparison {
        guard let left = components(lhs), let right = components(rhs) else {
            return .invalid
        }

        for index in 0..<max(left.count, right.count) {
            let leftComponent = index < left.count ? left[index] : 0
            let rightComponent = index < right.count ? right[index] : 0
            if leftComponent < rightComponent { return .older }
            if leftComponent > rightComponent { return .newer }
        }
        return .same
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, to: current) == .newer
    }

    private static func components(_ value: String) -> [Int]? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let pieces = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard !pieces.isEmpty else { return nil }
        var result: [Int] = []
        result.reserveCapacity(pieces.count)
        for piece in pieces {
            guard !piece.isEmpty, piece.allSatisfy(\.isNumber),
                  let number = Int(piece) else { return nil }
            result.append(number)
        }
        return result
    }
}

extension Notification.Name {
    static let apm44WillInstallUpdate = Notification.Name("apm44.willInstallUpdate")
}

/// Orders out SwiftUI's MenuBarExtra panel without touching the Controls
/// window or the Settings window, which host the same MenuContentView.
@MainActor
func dismissMenuBarPanel() {
    let panels = NSApp.windows.filter { window in
        let className = NSStringFromClass(type(of: window))
        let isMenuBarExtraWindow = className.contains("MenuBarExtraWindow")
        let isStatusBarPanel = (window.level == .statusBar || window.level == .popUpMenu) && window is NSPanel
        return window.isVisible && (isMenuBarExtraWindow || isStatusBarPanel)
    }
    guard !panels.isEmpty else { return }
    // Toggle through the status item like a user click so SwiftUI's
    // MenuBarExtra state stays in sync. Ordering the panel out behind its
    // back leaves the next status-item click as a no-op.
    if let button = menuBarExtraStatusButton() {
        logger.debug("Dismissing menu bar panel via status item")
        button.performClick(nil)
    }
    for panel in panels where panel.isVisible {
        logger.debug("Dismissing menu bar panel class=\(NSStringFromClass(type(of: panel)), privacy: .public)")
        panel.orderOut(nil)
    }
}

@MainActor
private func menuBarExtraStatusButton() -> NSStatusBarButton? {
    for window in NSApp.windows where NSStringFromClass(type(of: window)).contains("NSStatusBarWindow") {
        if let button = findStatusBarButton(in: window.contentView) {
            return button
        }
    }
    return nil
}

@MainActor
private func findStatusBarButton(in view: NSView?) -> NSStatusBarButton? {
    guard let view else { return nil }
    if let button = view as? NSStatusBarButton { return button }
    for subview in view.subviews {
        if let button = findStatusBarButton(in: subview) { return button }
    }
    return nil
}

/// Isolates NSApp side effects behind injected closures so unit tests can
/// verify the accessory -> regular -> accessory transitions without touching
/// NSApp, starting a real SPUUpdater, or hitting the network.
@MainActor
final class UpdateActivationCoordinator {
    var activationPolicySetter: @MainActor (NSApplication.ActivationPolicy) -> Bool
    var appActivator: @MainActor () -> Void
    var panelDismisser: @MainActor () -> Void
    var deferredRunner: @MainActor (@escaping @MainActor () -> Void) -> Void
    private var didElevateActivationPolicy = false

    init(
        activationPolicySetter: @escaping @MainActor (NSApplication.ActivationPolicy) -> Bool,
        appActivator: @escaping @MainActor () -> Void,
        panelDismisser: @escaping @MainActor () -> Void,
        deferredRunner: @escaping @MainActor (@escaping @MainActor () -> Void) -> Void = { work in
            DispatchQueue.main.async {
                Task { @MainActor in work() }
            }
        }
    ) {
        self.activationPolicySetter = activationPolicySetter
        self.appActivator = appActivator
        self.panelDismisser = panelDismisser
        self.deferredRunner = deferredRunner
    }

    func bringUpdateUIToFront() {
        panelDismisser()
        _ = activationPolicySetter(.regular)
        didElevateActivationPolicy = true
        appActivator()
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

/// Sparkle's standard UI remains responsible for release notes, download
/// progress, administrator authorization, cancellation, installation, and
/// relaunch. This observable bridge supplies a small musician-facing status
/// surface for the menu-bar popover and deliberately keeps no persisted
/// "update available" flag, so a successful relaunch cannot show stale state.
@MainActor
final class SparkleUpdateController: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = SparkleUpdateController()

    // Sparkle reports a successful "no update" result as an error-shaped
    // completion with SUNoUpdateError (1001). Keep that result distinct from
    // feed, network, and installation failures so the musician-facing surface
    // returns to its quiet idle state instead of showing a false failure.
    nonisolated private static let noUpdateErrorCode = 1001

    // Network-layer codes that mean "interrupted, check connection and retry".
    nonisolated private static let networkInterruptionCodes: Set<Int> = [-1001, -1003, -1004, -1005, -1009, -1018, -1020]

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
        startUpdater: Bool = true
    ) {
        self.currentVersion = currentVersion
        self.launchDate = Date()
        self.activation = UpdateActivationCoordinator(
            activationPolicySetter: activationPolicySetter,
            appActivator: appActivator,
            panelDismisser: menuPanelDismisser,
            deferredRunner: deferredRunner
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
            logger.info("Update already installed")
            state = .idle
            lastOfferedVersion = nil
            return
        }
        let nsError = error as NSError
        if Self.shouldTreatInstallationErrorAsSuccess(
            state: state,
            error: error,
            currentVersion: currentVersion
        ) {
            benignInstallationSuccessLatched = true
            logger.info("Update already installed")
            state = .idle
            lastOfferedVersion = nil
        } else if Self.isNoUpdateError(error) {
            state = .idle
            lastOfferedVersion = nil
        } else if nsError.domain == SUSparkleErrorDomain,
                  nsError.code == 4007 { // Sparkle's SUInstallationCanceledError.
            logger.info("Update cancelled")
            state = .cancelled
        } else if Self.isDownloadFailure(error) {
            failDownload(error)
        } else {
            failCheck(error)
        }
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
            logger.info("Update already installed")
            state = .idle
            lastOfferedVersion = nil
            return
        }
        if let error, Self.shouldTreatInstallationErrorAsSuccess(
            state: state,
            error: error,
            currentVersion: currentVersion
        ) {
            logger.info("Update already installed")
            state = .idle
            lastOfferedVersion = nil
        } else if let error, Self.isNoUpdateError(error) {
            state = .idle
            lastOfferedVersion = nil
        } else if let error {
            if Self.isDownloadFailure(error) {
                failDownload(error)
            } else {
                failCheck(error)
            }
        } else if case .checking = state {
            state = .idle
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

    private func failCheck(_ error: Error) {
        if Self.shouldTreatInstallationErrorAsSuccess(
            state: state,
            error: error,
            currentVersion: currentVersion
        ) {
            logger.info("Update already installed")
            state = .idle
            lastOfferedVersion = nil
            return
        }
        let nsError = error as NSError
        logger.error("Update failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code)")
        state = .failed(message: Self.userFacingErrorMessage(error))
    }

    private func failDownload(_ error: Error) {
        if Self.shouldTreatInstallationErrorAsSuccess(
            state: state,
            error: error,
            currentVersion: currentVersion
        ) {
            logger.info("Update already installed")
            state = .idle
            lastOfferedVersion = nil
            return
        }
        let nsError = error as NSError
        logger.error("Update failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code)")
        state = .failed(message: Self.downloadErrorMessage(error))
    }

    private func fail(_ error: Error) {
        if Self.isDownloadFailure(error) {
            failDownload(error)
        } else {
            failCheck(error)
        }
    }

    nonisolated static func isNoUpdateError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SUSparkleErrorDomain && nsError.code == noUpdateErrorCode
    }

    /// True for errors that come from the download phase: an explicit
    /// SUDownloadError, any NSURLErrorDomain error, or a Sparkle error whose
    /// NSUnderlyingError chain contains NSURLErrorDomain.
    nonisolated static func isDownloadFailure(_ error: Error) -> Bool {
        let top = error as NSError
        if top.domain == SUSparkleErrorDomain && top.code == 2001 {
            return true
        }
        var current: Error? = error
        var depth = 0
        while depth < 10, let candidate = current {
            let nsCandidate = candidate as NSError
            if nsCandidate.domain == NSURLErrorDomain {
                return true
            }
            guard let underlying = nsCandidate.userInfo[NSUnderlyingErrorKey] as? Error else { break }
            current = underlying
            depth += 1
        }
        return false
    }

    /// True when the error (or its underlying chain) is a network-layer
    /// interruption that should prompt a connection check and retry.
    nonisolated static func isNetworkInterruptionError(_ error: Error) -> Bool {
        var current: Error? = error
        var depth = 0
        while depth < 10, let candidate = current {
            let nsCandidate = candidate as NSError
            if nsCandidate.domain == NSURLErrorDomain,
               networkInterruptionCodes.contains(nsCandidate.code) {
                return true
            }
            guard let underlying = nsCandidate.userInfo[NSUnderlyingErrorKey] as? Error else { break }
            current = underlying
            depth += 1
        }
        return false
    }

    /// Download-phase message: network interruptions get the actionable
    /// "check connection and try again" copy; other download failures keep
    /// the underlying detail. Signature and cancellation wording is kept.
    nonisolated static func downloadErrorMessage(_ error: Error) -> String {
        if isNoUpdateError(error) {
            return AppStrings.noUpdateAvailable
        }
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = description.lowercased()
        if lowered.contains("signature") || lowered.contains("appcast") || lowered.contains("secure") {
            return AppStrings.updateFeedUnverified
        }
        if lowered.contains("cancel") || lowered.contains("authorization") || lowered.contains("password") {
            return AppStrings.updateCancelledBeforeReplace
        }
        if isNetworkInterruptionError(error) {
            return AppStrings.updateDownloadInterrupted
        }
        if description.isEmpty {
            let nsError = error as NSError
            return AppStrings.updateDownloadFailed(detail: "\(nsError.domain) (\(nsError.code))")
        }
        return AppStrings.updateDownloadFailed(detail: description)
    }

    /// A post-relaunch installation error while installing a version that is
    /// not newer than the running app means the install already succeeded
    /// (e.g. the app was launched a moment too early). Accept 4010
    /// (SUAgentInvalidationError) as before, but accept the generic 4005
    /// (SUInstallationError) only when the error chain carries Sparkle's
    /// "remote port connection was invalidated" text, which it appends in
    /// English even in localized UIs.
    nonisolated static func shouldTreatInstallationErrorAsSuccess(
        state: AppUpdateState,
        error: Error,
        currentVersion: String
    ) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == SUSparkleErrorDomain else { return false }
        guard nsError.code == 4005 || nsError.code == 4010 else { return false }
        guard case let .installing(version: installingVersion) = state else { return false }
        guard !AppUpdateVersionComparator.isNewer(installingVersion, than: currentVersion) else { return false }
        if nsError.code == 4010 { return true }
        return containsRemotePortInvalidation(error)
    }

    /// True when the error or any NSUnderlyingError in its chain carries the
    /// remote-port invalidation text in its localized description or failure
    /// reason (case-insensitive).
    nonisolated static func containsRemotePortInvalidation(_ error: Error) -> Bool {
        let needle = "remote port connection was invalidated"
        var current: Error? = error
        var depth = 0
        while depth < 10, let candidate = current {
            let nsCandidate = candidate as NSError
            if nsCandidate.localizedDescription.lowercased().contains(needle) {
                return true
            }
            if let reason = nsCandidate.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
               reason.lowercased().contains(needle) {
                return true
            }
            guard let underlying = nsCandidate.userInfo[NSUnderlyingErrorKey] as? Error else { break }
            current = underlying
            depth += 1
        }
        return false
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

    nonisolated static func userFacingErrorMessage(_ error: Error) -> String {
        if isNoUpdateError(error) {
            return AppStrings.noUpdateAvailable
        }
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = description.lowercased()
        if lowered.contains("signature") || lowered.contains("appcast") || lowered.contains("secure") {
            return AppStrings.updateFeedUnverified
        }
        if lowered.contains("cancel") || lowered.contains("authorization") || lowered.contains("password") {
            return AppStrings.updateCancelledBeforeReplace
        }
        if description.isEmpty { return AppStrings.updateCheckFailedRetry }
        return AppStrings.updateCheckFailed(detail: description)
    }
}
