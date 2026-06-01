import SwiftUI

/// First-run checks: HAL loaded, rates, Cubase Control Room ports.
struct FirstRunPreflightView: View {
    @ObservedObject var manager: BridgeProcessManager
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("APM44 Bridge setup")
                .font(.title3.weight(.semibold))

            checkRow(
                title: "HAL driver",
                ok: HalDriverDetector.isHalInstalled(),
                detail: halDetail
            )
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
    }

    private var halDetail: String {
        HalDriverDetector.isHalInstalled()
            ? "APM44 Bridge visible in Audio MIDI Setup"
            : "Install driver from release pkg or scripts/install-driver.sh"
    }

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
