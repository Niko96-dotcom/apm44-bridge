import AppKit

/// macOS 26 can hide the menu bar item when it is not allowed in System
/// Settings > Menu Bar. Control Center credits the item to the app that
/// launched this one (e.g. a coding tool running `open`), so that app's switch
/// counts too. AppKit then terminates the app ("terminating on removal")
/// without the app logging anything.
///
/// `MenuBarExtra(isInserted:)` would avoid the termination, but when Control
/// Center hides the item SwiftUI keeps resetting the binding and the main
/// thread spins (reproduced 2026-09-28 on macOS 26). So the app keeps the
/// default behavior and logs the reason while it quits.
enum MenuBarItemVisibility {
    static let hiddenTerminationReason =
        "Quitting because macOS hid the menu bar item. Allow APM44 Bridge in System Settings > Menu Bar. "
        + "If another app opened it (for example a terminal or coding tool), allow that app there too, "
        + "or open APM44 Bridge from Finder"

    /// The status items SwiftUI placed in the menu bar. `NSStatusItem` has no
    /// public list, so read each status bar window's `statusItem` defensively.
    static func statusItems(in windows: [NSWindow]) -> [NSStatusItem] {
        let selector = NSSelectorFromString("statusItem")
        return windows.compactMap { window in
            guard window.responds(to: selector) else { return nil }
            return window.value(forKey: "statusItem") as? NSStatusItem
        }
    }

    static func terminationReason(statusItemVisibility: [Bool]) -> String? {
        statusItemVisibility.contains(false) ? hiddenTerminationReason : nil
    }
}
