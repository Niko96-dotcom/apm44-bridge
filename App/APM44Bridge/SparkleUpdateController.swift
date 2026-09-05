import AppKit
import Combine
import Foundation
import Sparkle

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

    private(set) var updaterController: SPUStandardUpdaterController!
    private let currentVersion: String
    private var backgroundCheckTask: Task<Void, Never>?

    init(
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0"
    ) {
        self.currentVersion = currentVersion
        super.init()

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        // Sparkle schedules subsequent checks itself using the Info.plist
        // interval. One explicit background check after launch makes the first
        // run deterministic without fighting Sparkle's scheduler later.
        backgroundCheckTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            guard self.updaterController.updater.automaticallyChecksForUpdates else { return }
            // SPUStandardUpdaterController starts its own first update cycle on
            // the next main-run-loop turn. If that cycle won the race, the
            // explicit launch check is a no-op; do not expose a permanent
            // "Checking" state for a check we did not start.
            guard !self.updaterController.updater.sessionInProgress else { return }
            guard self.updaterController.updater.canCheckForUpdates else { return }
            self.state = .checking
            self.updaterController.updater.checkForUpdatesInBackground()
        }
    }

    deinit {
        backgroundCheckTask?.cancel()
    }

    var updater: SPUUpdater { updaterController.updater }

    func checkForUpdates() {
        guard updater.canCheckForUpdates else { return }
        state = .checking
        updaterController.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard AppUpdateVersionComparator.isNewer(item.versionString, than: currentVersion) else {
            state = .idle
            return
        }
        state = .available(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        if Self.isNoUpdateError(error) {
            state = .idle
        } else {
            fail(error)
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        state = .idle
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        state = .readyToInstall(version: item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        fail(error)
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        state = .cancelled
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        state = .installing(version: item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        if Self.isNoUpdateError(error) {
            state = .idle
        } else if nsError.domain == SUSparkleErrorDomain,
                  nsError.code == 4007 { // Sparkle's SUInstallationCanceledError.
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
        state = .installing(version: item.displayVersionString)
        return false
    }

    private func fail(_ error: Error) {
        state = .failed(message: Self.userFacingErrorMessage(error))
    }

    nonisolated static func isNoUpdateError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SUSparkleErrorDomain && nsError.code == noUpdateErrorCode
    }

    nonisolated static func userFacingErrorMessage(_ error: Error) -> String {
        if isNoUpdateError(error) {
            return "No update is available."
        }
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = description.lowercased()
        if lowered.contains("signature") || lowered.contains("appcast") || lowered.contains("secure") {
            return "Update check blocked: the signed update feed could not be verified."
        }
        if lowered.contains("cancel") || lowered.contains("authorization") || lowered.contains("password") {
            return "Update installation was cancelled before APM44 Bridge could be replaced."
        }
        if description.isEmpty { return "Update check failed. Try again later." }
        return "Update check failed: \(description)"
    }
}
