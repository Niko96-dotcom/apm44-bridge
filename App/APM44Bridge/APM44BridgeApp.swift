import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var controlsPresenter: ControlsPresenting = ControlsWindowPresenter.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
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

        if let appMenu = mainMenu.items.first?.submenu,
           appMenu.item(withTitle: AppStrings.settingsMenu) == nil {
            let settings = NSMenuItem(
                title: AppStrings.settingsMenu,
                action: #selector(showSettings),
                keyEquivalent: ","
            )
            settings.target = self
            let insertIndex = min(1, appMenu.items.count)
            appMenu.insertItem(settings, at: insertIndex)
        }

        let helpItem = mainMenu.item(withTitle: "Hilfe")
            ?? mainMenu.item(withTitle: "Help")
            ?? mainMenu.items.last
        let wantedHelp = [AppStrings.helpMenuSetup, AppStrings.cubaseSetupGuide]
        if let helpMenu = helpItem?.submenu {
            let existing = helpMenu.items.map(\.title)
            if existing != wantedHelp {
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
            NSApp.helpMenu = helpMenu
        } else {
            let helpMenu = NSMenu(title: "Hilfe")
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
            NSApp.helpMenu = helpMenu
        }
    }

    @objc
    private func showSettings() {
        controlsPresenter.showControls()
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
    @StateObject private var updater = SparkleUpdateController.shared
    private let hotplug: HotplugMonitor
    private let systemLifecycle: SystemLifecycleMonitor

    init() {
        let settings = BridgeSettings()
        _settings = StateObject(wrappedValue: settings)
        let manager = BridgeProcessManager(settings: settings)
        _manager = StateObject(wrappedValue: manager)
        ControlsWindowPresenter.shared.configure(manager: manager, settings: settings)
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
