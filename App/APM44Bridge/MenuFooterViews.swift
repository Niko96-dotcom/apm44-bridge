import SwiftUI

struct MenuPrimaryButtons: View {
    @ObservedObject var manager: BridgeProcessManager
    let presentation: MenuPresentation

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if presentation.showsStartButton {
                    startButton
                }

                if presentation.showsStopButton {
                    Button {
                        manager.stop()
                    } label: {
                        Label(AppStrings.stopBridge, systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(presentation.stopDisabled)
                    .accessibilityLabel(AppStrings.stopBridge)
                    .accessibilityIdentifier("stop-bridge")
                }
            }

            if presentation.showsRestartButton {
                Button {
                    Task { await manager.restart(reason: .user) }
                } label: {
                    Label(AppStrings.restart, systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(presentation.restartDisabled)
                .accessibilityLabel(AppStrings.restart)
                .accessibilityIdentifier("restart-bridge")
            }

            Button {
                Task { await manager.quitApplication() }
            } label: {
                Label(AppStrings.quitApp, systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(presentation.quitDisabled)
            .accessibilityLabel(AppStrings.quitApp)
            .accessibilityIdentifier("quit-app")
        }
        .controlSize(.regular)
    }

    @ViewBuilder
    private var startButton: some View {
        let enabled = presentation.startEnabled
        if enabled {
            Button {
                manager.start()
            } label: {
                Label(AppStrings.startBridge, systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(AppStrings.startBridge)
            .accessibilityIdentifier("start-bridge")
        } else {
            Button {
                manager.start()
            } label: {
                Label(AppStrings.startBridge, systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(true)
            .accessibilityLabel(AppStrings.startBridge)
            .accessibilityHint(presentation.startBlockedReason ?? "")
            .accessibilityIdentifier("start-bridge")
        }
    }
}

struct MenuFooterSection: View {
    @ObservedObject var manager: BridgeProcessManager
    @ObservedObject var launchAtLogin: LaunchAtLoginController
    @Binding var showFirstRun: Bool
    @EnvironmentObject private var updater: SparkleUpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(AppStrings.openAtLogin, isOn: openAtLoginBinding)
                .toggleStyle(.checkbox)
                .controlSize(.regular)
                .font(.body)
                .accessibilityLabel(AppStrings.openAtLogin)
                .accessibilityIdentifier("open-at-login")
            if launchAtLogin.requiresApproval {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Label(AppStrings.loginItemsApproval, systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Spacer(minLength: 4)
                    Button(AppStrings.openSettings) {
                        launchAtLogin.openApprovalSettings()
                    }
                    .font(.caption2)
                    .buttonStyle(.link)
                    .accessibilityLabel(AppStrings.openSettings)
                }
            }
            HStack {
                Text(AppStrings.versionLabel(Bundle.main.shortVersion))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(AppStrings.setup) {
                    showFirstRun = true
                }
                .font(.caption2)
                .buttonStyle(.link)
                .accessibilityLabel(AppStrings.setup)
            }
            // Own row: the German title does not fit beside the version and
            // Setup at the fixed popover width.
            Button(AppStrings.checkForUpdates) {
                dismissMenuBarPanel()
                updater.checkForUpdates()
            }
            .font(.caption2)
            .buttonStyle(.link)
            .accessibilityIdentifier("check-for-updates")
            .accessibilityLabel(AppStrings.checkForUpdates)
            .disabled(!updater.canStartManualCheck)
            Link(AppStrings.cubaseSetupGuide, destination: HelpLinks.cubaseSetup)
                .font(.caption2)
                .accessibilityLabel(AppStrings.cubaseSetupGuide)
        }
    }

    private var openAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { enabled, _ in
                do {
                    try launchAtLogin.setEnabled(enabled)
                } catch {
                    manager.bannerMessage = AppStrings.couldNotUpdateOpenAtLogin
                    launchAtLogin.refresh()
                }
            }
        )
    }
}

private extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
    }
}
