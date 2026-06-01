import SwiftUI

@main
struct APM44BridgeApp: App {
    @StateObject private var settings = BridgeSettings()
    @StateObject private var manager: BridgeProcessManager
    private let hotplug: HotplugMonitor

    init() {
        let settings = BridgeSettings()
        _settings = StateObject(wrappedValue: settings)
        let manager = BridgeProcessManager(settings: settings)
        _manager = StateObject(wrappedValue: manager)
        hotplug = HotplugMonitor {
            Task { @MainActor in
                await manager.handleHotplug()
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(manager: manager, settings: settings)
                .onAppear {
                    hotplug.start()
                    Task { await manager.refreshDevices() }
                }
                .onDisappear {
                    hotplug.stop()
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
        case .running: return .green
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
        case .error: return "error"
        }
    }
}
