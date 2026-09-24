import AppKit
import Foundation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.niko.apm44.menu",
    category: "Lifecycle"
)

final class SystemLifecycleMonitor {
    private let notificationCenter: NotificationCenter
    private let onWillSleep: () -> Void
    private let onDidWake: () -> Void
    private var tokens: [NSObjectProtocol] = []

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        onWillSleep: @escaping () -> Void,
        onDidWake: @escaping () -> Void
    ) {
        self.notificationCenter = notificationCenter
        self.onWillSleep = onWillSleep
        self.onDidWake = onDidWake
    }

    func start() {
        guard tokens.isEmpty else { return }
        tokens.append(notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            logger.info("System will sleep")
            self?.onWillSleep()
        })
        tokens.append(notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            logger.info("System did wake")
            self?.onDidWake()
        })
    }

    func stop() {
        for token in tokens {
            notificationCenter.removeObserver(token)
        }
        tokens.removeAll()
    }

    deinit {
        stop()
    }
}
