import AppKit
import XCTest
@testable import APM44Bridge

final class MenuBarItemVisibilityTests: XCTestCase {
    func testHiddenItemExplainsTheQuit() {
        let reason = MenuBarItemVisibility.terminationReason(statusItemVisibility: [false])

        XCTAssertEqual(reason, MenuBarItemVisibility.hiddenTerminationReason)
        XCTAssertTrue(reason?.contains("System Settings > Menu Bar") == true)
        XCTAssertTrue(reason?.contains("If another app opened it") == true)
    }

    func testVisibleOrMissingItemGivesNoReason() {
        XCTAssertNil(MenuBarItemVisibility.terminationReason(statusItemVisibility: [true]))
        XCTAssertNil(MenuBarItemVisibility.terminationReason(statusItemVisibility: []))
    }

    @MainActor
    func testOrdinaryWindowsAreSkipped() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )

        XCTAssertTrue(MenuBarItemVisibility.statusItems(in: [window]).isEmpty)
    }
}
