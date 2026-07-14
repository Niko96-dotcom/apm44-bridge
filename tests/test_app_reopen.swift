import AppKit
import XCTest
@testable import APM44Bridge

@MainActor
private final class MockControlsPresenter: ControlsPresenting {
    private(set) var showCount = 0

    func showControls() {
        showCount += 1
    }
}

@MainActor
final class AppReopenTests: XCTestCase {
    func testReopeningRunningAppShowsFallbackControls() {
        let presenter = MockControlsPresenter()
        let delegate = AppDelegate()
        delegate.controlsPresenter = presenter

        let handled = delegate.applicationShouldHandleReopen(
            NSApplication.shared,
            hasVisibleWindows: false
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(presenter.showCount, 1)
    }
}
