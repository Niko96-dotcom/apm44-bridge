import AppKit
import Foundation

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
            self?.onWillSleep()
        })
        tokens.append(notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
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
