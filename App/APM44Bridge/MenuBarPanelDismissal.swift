import AppKit
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.niko.apm44.menu",
    category: "Updates"
)

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
