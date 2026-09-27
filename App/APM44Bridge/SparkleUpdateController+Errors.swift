import Foundation
import Sparkle

extension SparkleUpdateController {
    // Sparkle reports a successful "no update" result as an error-shaped
    // completion with SUNoUpdateError (1001). Keep that result distinct from
    // feed, network, and installation failures so the musician-facing surface
    // returns to its quiet idle state instead of showing a false failure.
    nonisolated private static var noUpdateErrorCode: Int { 1001 }

    // Network-layer codes that mean "interrupted, check connection and retry".
    nonisolated private static var networkInterruptionCodes: Set<Int> {
        [-1001, -1003, -1004, -1005, -1009, -1018, -1020]
    }

    nonisolated private static func errorChain(_ error: Error) -> [NSError] {
        var chain: [NSError] = []
        var current: Error? = error
        var depth = 0
        while depth < 10, let candidate = current {
            let nsCandidate = candidate as NSError
            chain.append(nsCandidate)
            guard let underlying = nsCandidate.userInfo[NSUnderlyingErrorKey] as? Error else { break }
            current = underlying
            depth += 1
        }
        return chain
    }

    nonisolated private static func sharedErrorPrefix(_ error: Error) -> String? {
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
        return nil
    }

    nonisolated static func isNoUpdateError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SUSparkleErrorDomain && nsError.code == noUpdateErrorCode
    }

    enum UpdateCycleErrorOutcome: Equatable {
        case alreadyInstalled
        case noUpdate
        case cancelled
        case failed
    }

    // Sparkle's SUInstallationCanceledError.
    nonisolated private static var installationCanceledErrorCode: Int { 4007 }

    /// The one decision for an error that ends an update cycle. Sparkle
    /// usually reports the same error to `didAbortWithError` and then to
    /// `didFinishUpdateCycleFor`, so both callbacks must classify it alike.
    nonisolated static func classifyUpdateCycleError(
        state: AppUpdateState,
        error: Error,
        currentVersion: String
    ) -> UpdateCycleErrorOutcome {
        if shouldTreatInstallationErrorAsSuccess(
            state: state,
            error: error,
            currentVersion: currentVersion
        ) {
            return .alreadyInstalled
        }
        if isNoUpdateError(error) {
            return .noUpdate
        }
        let nsError = error as NSError
        if nsError.domain == SUSparkleErrorDomain, nsError.code == installationCanceledErrorCode {
            return .cancelled
        }
        return .failed
    }

    /// True for errors that come from the download phase: an explicit
    /// SUDownloadError, any NSURLErrorDomain error, or a Sparkle error whose
    /// NSUnderlyingError chain contains NSURLErrorDomain.
    nonisolated static func isDownloadFailure(_ error: Error) -> Bool {
        let top = error as NSError
        if top.domain == SUSparkleErrorDomain && top.code == 2001 {
            return true
        }
        return errorChain(error).contains { $0.domain == NSURLErrorDomain }
    }

    /// True when the error (or its underlying chain) is a network-layer
    /// interruption that should prompt a connection check and retry.
    nonisolated static func isNetworkInterruptionError(_ error: Error) -> Bool {
        errorChain(error).contains {
            $0.domain == NSURLErrorDomain && networkInterruptionCodes.contains($0.code)
        }
    }

    /// Download-phase message: network interruptions get the actionable
    /// "check connection and try again" copy; other download failures keep
    /// the underlying detail. Signature and cancellation wording is kept.
    nonisolated static func downloadErrorMessage(_ error: Error) -> String {
        if let shared = sharedErrorPrefix(error) {
            return shared
        }
        if isNetworkInterruptionError(error) {
            return AppStrings.updateDownloadInterrupted
        }
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
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
        return errorChain(error).contains { nsCandidate in
            if nsCandidate.localizedDescription.lowercased().contains(needle) {
                return true
            }
            if let reason = nsCandidate.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
               reason.lowercased().contains(needle) {
                return true
            }
            return false
        }
    }

    nonisolated static func userFacingErrorMessage(_ error: Error) -> String {
        if let shared = sharedErrorPrefix(error) {
            return shared
        }
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty { return AppStrings.updateCheckFailedRetry }
        return AppStrings.updateCheckFailed(detail: description)
    }
}
