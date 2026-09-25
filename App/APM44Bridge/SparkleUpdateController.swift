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

/// Sparkle's standard UI remains responsible for release notes, download
/// progress, administrator authorization, cancellation, installation, and
/// relaunch. This observable bridge supplies a small musician-facing status
/// surface for the menu-bar popover and deliberately keeps no persisted
/// "update available" flag, so a successful relaunch cannot show stale state.
@MainActor
final class SparkleUpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = SparkleUpdateController()

    // Sparkle reports a successful "no update" result as an error-shaped
    // completion with SUNoUpdateError (1001). Keep that result distinct from
    // feed, network, and installation failures so the musician-facing surface
    // returns to its quiet idle state instead of showing a false failure.
    private static let noUpdateErrorCode = 1001

    @Published private(set) var state: AppUpdateState = .idle
    @Published private(set) var canCheckForUpdates = false

    private(set) var updaterController: SPUStandardUpdaterController!
    private let currentVersion: String
    private let launchDate: Date
    private var didEvaluateLaunchCheck = false

    init(
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0"
    ) {
        self.currentVersion = currentVersion
        self.launchDate = Date()
        super.init()

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        // Mirror Sparkle's readiness so manual UI can disable itself.
        // Assigned on the main thread; Sparkle mutates this KVO property
        // on the main thread.
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    var updater: SPUUpdater { updaterController.updater }

    /// False while Sparkle is busy or while an update is being checked,
    /// is downloaded and waiting, or is installing: a new check would
    /// overwrite that status.
    var canStartManualCheck: Bool {
        Self.canStartManualCheck(canCheckForUpdates: canCheckForUpdates, state: state)
    }

    nonisolated static func canStartManualCheck(canCheckForUpdates: Bool, state: AppUpdateState) -> Bool {
        guard canCheckForUpdates else { return false }
        switch state {
        case .checking, .readyToInstall, .installing: return false
        case .idle, .available, .cancelled, .failed: return true
        }
    }

    func checkForUpdates() {
        guard updater.canCheckForUpdates, canStartManualCheck else { return }
        logger.info("Checking for updates")
        state = .checking
        updaterController.checkForUpdates(nil)
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
        state = .available(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        if Self.isNoUpdateError(error) {
            logger.info("No update available")
            state = .idle
        } else {
            fail(error)
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        logger.info("No update available")
        state = .idle
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        logger.info("Update downloaded version=\(item.displayVersionString, privacy: .public)")
        state = .readyToInstall(version: item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        fail(error)
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        logger.info("Update cancelled")
        state = .cancelled
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        logger.info("Installing update version=\(item.displayVersionString, privacy: .public)")
        state = .installing(version: item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        if Self.isNoUpdateError(error) {
            state = .idle
        } else if nsError.domain == SUSparkleErrorDomain,
                  nsError.code == 4007 { // Sparkle's SUInstallationCanceledError.
            logger.info("Update cancelled")
            state = .cancelled
        } else {
            fail(error)
        }
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        if let error, Self.isNoUpdateError(error) {
            state = .idle
        } else if let error {
            fail(error)
        } else if case .checking = state {
            state = .idle
        }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        // The standard Sparkle UI owns the install-on-quit decision. Returning
        // false lets it request admin authorization and relaunch safely.
        logger.info("Installing update on quit version=\(item.displayVersionString, privacy: .public)")
        state = .installing(version: item.displayVersionString)
        return false
    }

    private func fail(_ error: Error) {
        let nsError = error as NSError
        logger.error("Update failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code)")
        state = .failed(message: Self.userFacingErrorMessage(error))
    }

    nonisolated static func isNoUpdateError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SUSparkleErrorDomain && nsError.code == noUpdateErrorCode
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
