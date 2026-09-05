import AppKit
import SwiftUI

@MainActor
protocol ControlsPresenting: AnyObject {
    func showControls()
}

/// AppKit supplies the lifecycle hook SwiftUI's MenuBarExtra does not expose:
/// presenting controls when Launch Services reopens an already-running app.
/// The hosted SwiftUI view uses the same manager and settings as the menu extra.
@MainActor
final class ControlsWindowPresenter: NSObject, ControlsPresenting, NSWindowDelegate {
    static let shared = ControlsWindowPresenter()

    private weak var manager: BridgeProcessManager?
    private weak var settings: BridgeSettings?
    private weak var updater: SparkleUpdateController?
    private var window: NSWindow?

    func configure(manager: BridgeProcessManager, settings: BridgeSettings,
                   updater: SparkleUpdateController? = nil) {
        self.manager = manager
        self.settings = settings
        self.updater = updater ?? .shared
    }

    func showControls() {
        guard let manager, let settings else { return }

        let controlsWindow: NSWindow
        if let window {
            controlsWindow = window
        } else {
            let rootView = MenuContentView(manager: manager, settings: settings)
                .environmentObject(updater ?? .shared)
            let hostingController = NSHostingController(rootView: rootView)
            let created = NSWindow(contentViewController: hostingController)
            created.title = "APM44 Bridge"
            created.setContentSize(NSSize(width: 372, height: 700))
            created.minSize = NSSize(width: 372, height: 560)
            created.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            created.isReleasedWhenClosed = false
            created.delegate = self
            created.center()
            window = created
            controlsWindow = created
        }

        NSApp.activate(ignoringOtherApps: true)
        controlsWindow.makeKeyAndOrderFront(nil)
    }
}
