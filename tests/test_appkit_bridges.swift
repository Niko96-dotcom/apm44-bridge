import AppKit
import XCTest
@testable import APM44Bridge

final class AppKitMainMenuTests: XCTestCase {
    func testHelpTitledSubmenuWinsOverLaterWindowMenu() {
        let main = NSMenu()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(NSMenuItem(title: "Existing", action: nil, keyEquivalent: ""))
        let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        helpItem.submenu = helpMenu
        main.addItem(helpItem)
        main.addItem(windowMenuItem())

        let resolved = AppKitMainMenu.helpSubmenu(in: main, applicationHelpMenu: nil)
        XCTAssertTrue(resolved === helpMenu)
    }

    func testHilfeTitledSubmenuWins() {
        let main = NSMenu()
        let helpMenu = NSMenu(title: "Hilfe")
        helpMenu.addItem(NSMenuItem(title: "Existing", action: nil, keyEquivalent: ""))
        let helpItem = NSMenuItem(title: "Hilfe", action: nil, keyEquivalent: "")
        helpItem.submenu = helpMenu
        main.addItem(helpItem)

        let resolved = AppKitMainMenu.helpSubmenu(in: main, applicationHelpMenu: nil)
        XCTAssertTrue(resolved === helpMenu)
    }

    func testDoesNotFallBackToLastMainMenuItem() {
        let main = NSMenu()
        let windowItem = windowMenuItem()
        let windowMenu = windowItem.submenu
        main.addItem(windowItem)

        XCTAssertNil(AppKitMainMenu.helpSubmenu(in: main, applicationHelpMenu: nil))
        XCTAssertEqual(windowMenu?.items.map(\.title), ["Minimize"])
    }

    func testApplicationHelpMenuUsedWhenHelpItemMissing() {
        let main = NSMenu()
        main.addItem(windowMenuItem())
        let appHelp = NSMenu(title: "Help")

        let resolved = AppKitMainMenu.helpSubmenu(in: main, applicationHelpMenu: appHelp)
        XCTAssertTrue(resolved === appHelp)
    }

    private func windowMenuItem() -> NSMenuItem {
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: nil, keyEquivalent: ""))
        let item = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        item.submenu = windowMenu
        return item
    }
}

@MainActor
final class ControlsWindowPresenterBridgeTests: XCTestCase {
    override func tearDown() async throws {
        SetupCoordinator.shared.resetForTesting()
        try await super.tearDown()
    }

    func testUnconfiguredShowControlsDoesNotCreateWindow() {
        let presenter = ControlsWindowPresenter()
        presenter.showControls()
        XCTAssertFalse(presenter.hasWindowForTesting)
    }

    func testShowSetupRecordsRequestWithoutCreatingWindowWhenUnconfigured() {
        SetupCoordinator.shared.resetForTesting()
        let presenter = ControlsWindowPresenter()
        presenter.showSetup()
        XCTAssertFalse(presenter.hasWindowForTesting)
        XCTAssertTrue(SetupCoordinator.shared.isSetupRequested)
    }
}

final class FullWidthPopUpButtonBridgeTests: XCTestCase {
    func testCoordinatorReportsRepresentedObjectNotTitle() {
        let coordinator = FullWidthPopUpButton.Coordinator()
        var selected: String?
        coordinator.onSelect = { selected = $0 }
        let popUp = NSPopUpButton()
        popUp.addItem(withTitle: "Studio Speakers")
        popUp.lastItem?.representedObject = "uid-1"
        popUp.selectItem(at: 0)
        coordinator.chose(popUp)
        XCTAssertEqual(selected, "uid-1")
    }

    func testDismantleClearsTargetActionAndCallback() {
        let coordinator = FullWidthPopUpButton.Coordinator()
        coordinator.onSelect = { _ in }
        let popUp = FixedWidthPopUpButton()
        popUp.target = coordinator
        popUp.action = #selector(FullWidthPopUpButton.Coordinator.chose(_:))
        FullWidthPopUpButton.dismantleNSView(popUp, coordinator: coordinator)
        XCTAssertNil(popUp.target)
        XCTAssertNil(popUp.action)
        XCTAssertNil(coordinator.onSelect)
    }

    func testInPlaceTitleChangeReselectsSoBezelMatchesPickerLabel() {
        let popUp = SelectTrackingPopUp()
        let uid = "uid-1"
        makeButton(
            options: [
                FullWidthPopUpButton.Option(id: "", title: "Choose output", isEnabled: true),
                FullWidthPopUpButton.Option(id: uid, title: "Studio Speakers — USB", isEnabled: true),
            ],
            selectedId: uid
        ).apply(to: popUp)
        XCTAssertEqual(popUp.selectedItem?.representedObject as? String, uid)
        XCTAssertEqual(popUp.title, "Studio Speakers — USB")
        let selectsAfterInitial = popUp.selectCalls

        makeButton(
            options: [
                FullWidthPopUpButton.Option(id: "", title: "Choose output", isEnabled: true),
                FullWidthPopUpButton.Option(id: uid, title: "Studio Speakers — USB", isEnabled: true),
            ],
            selectedId: uid
        ).apply(to: popUp)
        XCTAssertEqual(popUp.selectCalls, selectsAfterInitial)

        let incompatible = "Studio Speakers — Unsupported: Stereo output unavailable"
        makeButton(
            options: [
                FullWidthPopUpButton.Option(id: "", title: "Choose output", isEnabled: true),
                FullWidthPopUpButton.Option(id: uid, title: incompatible, isEnabled: false),
            ],
            selectedId: uid
        ).apply(to: popUp)
        XCTAssertGreaterThan(popUp.selectCalls, selectsAfterInitial)
        XCTAssertEqual(popUp.selectedItem?.representedObject as? String, uid)
        XCTAssertEqual(popUp.selectedItem?.title, incompatible)
        XCTAssertEqual(popUp.title, incompatible)
        XCTAssertFalse(popUp.selectedItem?.isEnabled ?? true)
    }

    private func makeButton(
        options: [FullWidthPopUpButton.Option],
        selectedId: String
    ) -> FullWidthPopUpButton {
        FullWidthPopUpButton(
            width: 200,
            options: options,
            selectedId: selectedId,
            accessibilityLabelText: "Output",
            onSelect: { _ in }
        )
    }
}

private final class SelectTrackingPopUp: FixedWidthPopUpButton {
    private(set) var selectCalls = 0

    override func select(_ item: NSMenuItem?) {
        selectCalls += 1
        super.select(item)
    }
}
