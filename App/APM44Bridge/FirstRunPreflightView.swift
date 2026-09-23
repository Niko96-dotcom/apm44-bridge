import SwiftUI

/// First-run checks: driver loaded, rates, Cubase Control Room ports.
struct FirstRunPreflightView: View {
    @ObservedObject var manager: BridgeProcessManager
    @Binding var isPresented: Bool

    @State private var driverStatus: DriverStatus = .notInstalled
    @State private var isReloading = false
    @State private var didAttemptReload = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppStrings.setupTitle)
                .font(.title3.weight(.semibold))

            driverCheckRow

            checkRow(
                title: AppStrings.halRateTitle,
                ok: halRateOk,
                detail: halRateDetail
            )
            checkRow(
                title: AppStrings.airPodsRateTitle,
                ok: airPodsRateOk,
                detail: airPodsRateDetail
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
                if setupComplete {
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

    private var setupComplete: Bool {
        driverStatus == .ready && halRateOk && airPodsRateOk
    }

    @ViewBuilder
    private var driverCheckRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            checkRow(title: AppStrings.halDriver, ok: driverStatus == .ready, detail: driverDetail)

            switch driverStatus {
            case .ready:
                EmptyView()
            case .buildMismatch:
                Link(AppStrings.downloadInstaller, destination: HelpLinks.releases)
                    .font(.caption)
                    .padding(.leading, 24)
                    .accessibilityLabel(AppStrings.downloadInstaller)
            case .installedNotLoaded:
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
            case .notInstalled:
                Link(AppStrings.downloadInstaller, destination: HelpLinks.releases)
                    .font(.caption)
                    .padding(.leading, 24)
                    .accessibilityLabel(AppStrings.downloadInstaller)
            }
        }
    }

    private var driverDetail: String {
        switch driverStatus {
        case .ready:
            return AppStrings.driverReadyDetail
        case .buildMismatch:
            return buildMismatchDetail
        case .installedNotLoaded:
            return didAttemptReload ? AppStrings.driverRestartHint : AppStrings.driverReloadHint
        case .notInstalled:
            return AppStrings.driverMissingDetail
        }
    }

    private var buildMismatchDetail: String {
        let appID = HalDriverDetector.normalizedBuildID(HalDriverDetector.appBuildID())
            ?? AppStrings.buildIDMissingPlaceholder
        let driverID = HalDriverDetector.normalizedBuildID(HalDriverDetector.driverBuildID())
            ?? AppStrings.buildIDMissingPlaceholder
        return AppStrings.driverBuildMismatchDetail(app: appID, driver: driverID)
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

    private var halRateOk: Bool {
        guard let rate = HalDriverDetector.halNominalRate() else { return false }
        return abs(rate - 44100) < 1
    }

    private var halRateDetail: String {
        if let rate = HalDriverDetector.halNominalRate() {
            if abs(rate - 44100) < 1 {
                return ""
            }
            return AppStrings.nominalRateHint(Int(rate))
        }
        return AppStrings.driverNotDetected
    }

    private var airPodsRow: AudioDeviceRow? {
        manager.devices.first { $0.name.localizedCaseInsensitiveContains("AirPods") }
    }

    private var airPodsRateOk: Bool {
        guard let row = airPodsRow else { return false }
        return abs(row.nominalRate - 48000) < 1
    }

    private var airPodsRateDetail: String {
        if let row = airPodsRow {
            return AppStrings.deviceRate(row.name, rate: Int(row.nominalRate))
        }
        return AppStrings.connectAirPods
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
