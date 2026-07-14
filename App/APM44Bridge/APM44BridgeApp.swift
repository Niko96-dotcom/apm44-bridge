import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var controlsPresenter: ControlsPresenting = ControlsWindowPresenter.shared

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        controlsPresenter.showControls()
        return true
    }
}

@main
struct APM44BridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = BridgeSettings()
    @StateObject private var manager: BridgeProcessManager
    @State private var showFirstRun = false
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
                .sheet(isPresented: $showFirstRun) {
                    FirstRunPreflightView(manager: manager, isPresented: $showFirstRun)
                }
                .onAppear {
                    manager.refreshRoutingMode()
                    if !UserDefaults.standard.bool(forKey: FirstRunKeys.completed) {
                        showFirstRun = true
                    }
                }
        } label: {
            Image(systemName: menuBarSymbol)
                .symbolRenderingMode(.palette)
                .foregroundStyle(menuBarTint, .secondary)
                .accessibilityLabel(menuBarAccessibility)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarSymbol: String {
        switch manager.state {
        case .error:
            return "headphones.circle.fill"
        default:
            return "headphones"
        }
    }

    private var menuBarTint: Color {
        switch manager.state {
        case .running: return manager.metricsStale ? .orange : .green
        case .reconnecting: return .orange
        case .error: return .red
        default: return .secondary
        }
    }

    private var menuBarAccessibility: String {
        let device = manager.deviceDisplayName.prefix(40)
        return "APM44 Bridge \(statusText), output \(device)"
    }

    private var statusText: String {
        switch manager.state {
        case .idle: return "stopped"
        case .starting: return "starting"
        case .running: return "running"
        case .stopping: return "stopping"
        case .reconnecting: return "reconnecting"
        case .error: return "error"
        }
    }
}
