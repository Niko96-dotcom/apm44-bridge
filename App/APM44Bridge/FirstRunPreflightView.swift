import SwiftUI

/// First-run checks: driver loaded, rates, Cubase Control Room ports.
struct FirstRunPreflightView: View {
    @ObservedObject var manager: BridgeProcessManager
    @Binding var isPresented: Bool

    @State private var driverStatus: DriverStatus = .notInstalled
    @State private var isReloading = false
    @State private var didAttemptReload = false

    var body: some View {
        let checklist = makeChecklist()
        VStack(alignment: .leading, spacing: 14) {
            Text(AppStrings.setupTitle)
                .font(.title3.weight(.semibold))

            driverCheckRow(checklist)

            checkRow(
                title: AppStrings.halRateTitle,
                ok: checklist.halRateOk,
                detail: checklist.halRateDetail
            )
            checkRow(
                title: AppStrings.airPodsRateTitle,
                ok: checklist.airPodsRateOk,
                detail: checklist.airPodsRateDetail
            )

            Text(AppStrings.cubaseControlRoom)
                .font(.headline)
            Text(AppStrings.cubaseControlRoomHint)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Link(AppStrings.cubaseSetupGuide, destination: HelpLinks.cubaseSetup)
                    .accessibilityLabel(AppStrings.cubaseSetupGuide)
                Spacer()
                if checklist.setupComplete {
                    Button(AppStrings.done) {
                        finishSetup()
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel(AppStrings.done)
                } else {
                    Button(AppStrings.skipSetup) {
                        finishSetup()
                    }
                    .accessibilityLabel(AppStrings.skipSetup)
                }
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { refreshDriverStatus() }
    }

    /// Built once per body: `halNominalRate()` enumerates Core Audio
    /// devices, and the build IDs (two plist reads) only matter for the
    /// mismatch detail.
    private func makeChecklist() -> FirstRunChecklist {
        let mismatch = driverStatus == .buildMismatch
        return FirstRunChecklist(
            driverStatus: driverStatus,
            didAttemptReload: didAttemptReload,
            halNominalRate: HalDriverDetector.halNominalRate(),
            devices: manager.devices,
            appBuildID: mismatch ? HalDriverDetector.appBuildID() : nil,
            driverBuildID: mismatch ? HalDriverDetector.driverBuildID() : nil
        )
    }

    @ViewBuilder
    private func driverCheckRow(_ checklist: FirstRunChecklist) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            checkRow(title: AppStrings.halDriver, ok: checklist.driverReady, detail: checklist.driverDetail)

            switch checklist.driverAction {
            case .none:
                EmptyView()
            case .downloadInstaller:
                Link(AppStrings.downloadInstaller, destination: HelpLinks.releases)
                    .font(.caption)
                    .padding(.leading, 24)
                    .accessibilityLabel(AppStrings.downloadInstaller)
            case .reloadDriver:
                HStack(spacing: 8) {
                    Button(action: reloadDriver) {
                        if isReloading {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(AppStrings.reloadAudioDriver)
                        }
                    }
                    .disabled(isReloading)
                    .accessibilityLabel(AppStrings.reloadAudioDriver)
                    Text(AppStrings.enterAdminPassword)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 24)
            }
        }
    }

    private func reloadDriver() {
        isReloading = true
        didAttemptReload = true
        Task {
            let reloaded = await Task.detached(priority: .userInitiated) {
                DriverMaintenance.reloadCoreAudioWithPrivileges()
            }.value
            if reloaded {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
            await manager.refreshDevices()
            driverStatus = HalDriverDetector.status()
            isReloading = false
        }
    }

    private func refreshDriverStatus() {
        driverStatus = HalDriverDetector.status()
    }

    private func finishSetup() {
        UserDefaults.standard.set(true, forKey: FirstRunKeys.completed)
        isPresented = false
    }

    private func checkRow(title: String, ok: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

enum FirstRunKeys {
    static let completed = "apm44.firstRunCompleted"
}

extension Notification.Name {
    static let showAPM44Setup = Notification.Name("com.niko.apm44.showSetup")
}
