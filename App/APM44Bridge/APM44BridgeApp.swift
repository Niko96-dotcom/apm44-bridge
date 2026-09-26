import AppKit
import OSLog
import SwiftUI

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.niko.apm44.menu",
    category: "App"
)

/// Resolves the Help submenu without using `mainMenu.items.last`, which can
/// rewrite Window when the menu bar extra's Help item is missing.
enum AppKitMainMenu {
    static func helpSubmenu(in mainMenu: NSMenu, applicationHelpMenu: NSMenu?) -> NSMenu? {
        if let item = mainMenu.item(withTitle: "Hilfe") ?? mainMenu.item(withTitle: "Help") {
            return item.submenu
        }
        return applicationHelpMenu
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var controlsPresenter: ControlsPresenting = ControlsWindowPresenter.shared
    private var becomeActiveMenuObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        becomeActiveMenuObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.configureMainMenu()
            }
        }
        Task { @MainActor in
            for _ in 0..<15 {
                self.configureMainMenu()
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        if UserDefaults.standard.bool(forKey: "APM44AutomationCheckForUpdates") {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                logger.info("Checking for updates (automation)")
                SparkleUpdateController.shared.checkForUpdates()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let becomeActiveMenuObserver {
            NotificationCenter.default.removeObserver(becomeActiveMenuObserver)
            self.becomeActiveMenuObserver = nil
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        controlsPresenter.showControls()
        return true
    }

    private func configureMainMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }

        if let appMenu = mainMenu.items.first?.submenu {
            if appMenu.item(withTitle: AppStrings.checkForUpdates) == nil {
                let check = NSMenuItem(
                    title: AppStrings.checkForUpdates,
                    action: #selector(checkForUpdates),
                    keyEquivalent: ""
                )
                check.target = self
                let insertIndex = min(1, appMenu.items.count)
                appMenu.insertItem(check, at: insertIndex)
            }
            if appMenu.item(withTitle: AppStrings.settingsMenu) == nil {
                let settings = NSMenuItem(
                    title: AppStrings.settingsMenu,
                    action: #selector(showSettings),
                    keyEquivalent: ","
                )
                settings.target = self
                if let checkIndex = appMenu.items.firstIndex(where: { $0.title == AppStrings.checkForUpdates }) {
                    appMenu.insertItem(settings, at: min(checkIndex + 1, appMenu.items.count))
                } else {
                    let insertIndex = min(1, appMenu.items.count)
                    appMenu.insertItem(settings, at: insertIndex)
                }
            }
        }

        let wantedHelp = [AppStrings.helpMenuSetup, AppStrings.cubaseSetupGuide]
        if let helpMenu = AppKitMainMenu.helpSubmenu(
            in: mainMenu,
            applicationHelpMenu: NSApp.helpMenu
        ) {
            if helpMenu.items.map(\.title) != wantedHelp {
                replaceHelpItems(on: helpMenu)
            }
            NSApp.helpMenu = helpMenu
        } else {
            let helpMenu = NSMenu(title: "Hilfe")
            replaceHelpItems(on: helpMenu)
            NSApp.helpMenu = helpMenu
        }
    }

    private func replaceHelpItems(on helpMenu: NSMenu) {
        helpMenu.removeAllItems()
        let setup = NSMenuItem(
            title: AppStrings.helpMenuSetup,
            action: #selector(showSetup),
            keyEquivalent: ""
        )
        setup.target = self
        let cubase = NSMenuItem(
            title: AppStrings.cubaseSetupGuide,
            action: #selector(openCubaseGuide),
            keyEquivalent: ""
        )
        cubase.target = self
        helpMenu.addItem(setup)
        helpMenu.addItem(cubase)
    }

    @objc
    private func showSettings() {
        controlsPresenter.showControls()
    }

    @objc
    private func checkForUpdates() {
        SparkleUpdateController.shared.checkForUpdates()
    }

    @objc
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates) {
            return SparkleUpdateController.shared.canStartManualCheck
        }
        return true
    }

    @objc
    private func showSetup() {
        controlsPresenter.showSetup()
    }

    @objc
    private func openCubaseGuide() {
        NSWorkspace.shared.open(HelpLinks.cubaseSetup)
    }
}

@main
struct APM44BridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = BridgeSettings()
    @StateObject private var manager: BridgeProcessManager
    @StateObject private var updater: SparkleUpdateController
    private let hotplug: HotplugMonitor
    private let systemLifecycle: SystemLifecycleMonitor

    init() {
        let settings = BridgeSettings()
        _settings = StateObject(wrappedValue: settings)
        let manager = BridgeProcessManager(settings: settings)
        _manager = StateObject(wrappedValue: manager)
        let updater = SparkleUpdateController.shared
        _updater = StateObject(wrappedValue: updater)
        ControlsWindowPresenter.shared.configure(
            manager: manager,
            settings: settings,
            updater: updater
        )
        hotplug = HotplugMonitor(selectedUid: settings.outputDeviceUid) {
            Task { @MainActor in
                await manager.handleHotplug()
            }
        }
        systemLifecycle = SystemLifecycleMonitor(
            onWillSleep: {
                Task { @MainActor in
                    await manager.handleSystemWillSleep()
                }
            },
            onDidWake: {
                Task { @MainActor in
                    await manager.handleSystemDidWake()
                }
            }
        )
        hotplug.start()
        systemLifecycle.start()
        Task { @MainActor in
            await manager.refreshDevices()
            manager.resumeAfterUpdateIfRequested(now: Date())
            if UserDefaults.standard.bool(forKey: "APM44AutomationStartBridge"),
               BridgeProcessManager.shouldAutomationStart(
                   state: manager.state,
                   blockedReason: manager.startBlockedReason
               ) {
                logger.info("Bridge starting (automation)")
                manager.start()
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(manager: manager, settings: settings)
                .environmentObject(updater)
                .onAppear {
                    manager.refreshRoutingMode()
                }
        } label: {
            Label {
                Text(menuBarAccessibility)
            } icon: {
                Image(systemName: menuBarSymbol)
                    .renderingMode(.template)
            }
            .labelStyle(.iconOnly)
            .accessibilityLabel(menuBarAccessibility)
        }
        .menuBarExtraStyle(.window)
        Settings {
            MenuContentView(manager: manager, settings: settings)
                .environmentObject(updater)
        }
        .commands {
            CommandGroup(replacing: .help) {
                Button(AppStrings.helpMenuSetup) {
                    ControlsWindowPresenter.shared.showSetup()
                }
                Button(AppStrings.cubaseSetupGuide) {
                    NSWorkspace.shared.open(HelpLinks.cubaseSetup)
                }
            }
        }
    }

    private var menuBarSymbol: String {
        switch manager.state {
        case .running:
            return "waveform"
        case .reconnecting, .starting:
            return "arrow.triangle.2.circlepath"
        case .error:
            return "headphones.slash"
        case .idle, .stopping:
            return "headphones"
        }
    }

    private var menuBarAccessibility: String {
        AppStrings.menuBarStatus(status: statusText, device: String(manager.deviceDisplayName.prefix(40)))
    }

    private var statusText: String {
        switch manager.state {
        case .idle: return AppStrings.stopped
        case .starting: return AppStrings.starting
        case .running: return AppStrings.running
        case .stopping: return AppStrings.stopping
        case .reconnecting: return AppStrings.reconnecting
        case .error: return AppStrings.errorStatus
        }
    }
}
