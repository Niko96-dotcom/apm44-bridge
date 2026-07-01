import SwiftUI

/// First-run checks: HAL loaded, rates, Cubase Control Room ports.
struct FirstRunPreflightView: View {
    @ObservedObject var manager: BridgeProcessManager
    @Binding var isPresented: Bool

    @State private var driverStatus: DriverStatus = .notInstalled
    @State private var isReloading = false
    @State private var didAttemptReload = false

    private let releasesURL = URL(string: "https://github.com/Niko96-dotcom/apm44-bridge/releases/latest")!

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("APM44 Bridge setup")
                .font(.title3.weight(.semibold))

            driverCheckRow

            checkRow(
                title: "APM44 Bridge @ 44.1 kHz",
                ok: halRateOk,
                detail: halRateDetail
            )
            checkRow(
                title: "AirPods USB @ 48 kHz",
                ok: airPodsRateOk,
                detail: airPodsRateDetail
            )

            Text("Cubase Control Room")
                .font(.headline)
            Text("Assign Monitor 1 device ports to APM44 Bridge left and right (German UI: Geräteanschlüsse). For click-free monitoring, use Safe latency and USB-C AirPods.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Link("Cubase setup guide", destination: URL(string: "https://github.com/Niko96-dotcom/apm44-bridge/blob/master/docs/first-run-cubase.md")!)
                Spacer()
                Button("Continue") {
                    UserDefaults.standard.set(true, forKey: FirstRunKeys.completed)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { refreshDriverStatus() }
    }

    // MARK: - Driver check row

    /// The HAL driver row plus the state-specific recovery action. Unlike the
    /// other rows, this one can act on the problem instead of only describing it.
    @ViewBuilder
    private var driverCheckRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            checkRow(title: "HAL driver", ok: driverStatus == .ready, detail: driverDetail)

            switch driverStatus {
            case .ready:
                EmptyView()
            case .installedNotLoaded:
                HStack(spacing: 8) {
                    Button(action: reloadDriver) {
                        if isReloading {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Reload audio driver")
                        }
                    }
                    .disabled(isReloading)
                    Text("Enter your admin password when asked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 24)
            case .notInstalled:
                Link("Download the installer", destination: releasesURL)
                    .font(.caption)
                    .padding(.leading, 24)
            }
        }
    }

    private var driverDetail: String {
        switch driverStatus {
        case .ready:
            return "APM44 Bridge visible in Audio MIDI Setup"
        case .installedNotLoaded:
            return didAttemptReload
                ? "Installed. If it is still not detected, restart your Mac once — only needed the first time."
                : "Installed but not loaded yet. Reload Core Audio to finish (usually no restart needed)."
        case .notInstalled:
            return "Driver not installed. Open the APM44 Bridge installer (.pkg) to install it."
        }
    }

    /// Reload Core Audio via an admin prompt, then re-check whether the device
    /// enumerated. The blocking privileged call runs off the main thread.
    private func reloadDriver() {
        isReloading = true
        didAttemptReload = true
        Task {
            let reloaded = await Task.detached(priority: .userInitiated) {
                DriverMaintenance.reloadCoreAudioWithPrivileges()
            }.value
            if reloaded {
                // Give coreaudiod time to respawn and enumerate the device.
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

    // MARK: - Rate checks

    private var halRateOk: Bool {
        guard let rate = HalDriverDetector.halNominalRate() else { return false }
        return abs(rate - 44100) < 1
    }

    private var halRateDetail: String {
        if let rate = HalDriverDetector.halNominalRate() {
            return "Nominal \(Int(rate)) Hz — set 44100 in Audio MIDI Setup"
        }
        return "Driver not detected"
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
            return "\(row.name) @ \(Int(row.nominalRate)) Hz"
        }
        return "Connect AirPods Max with USB-C cable"
    }

    private func checkRow(title: String, ok: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

enum FirstRunKeys {
    static let completed = "apm44.firstRunCompleted"
}
