import Foundation

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
