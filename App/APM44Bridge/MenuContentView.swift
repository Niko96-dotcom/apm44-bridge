import SwiftUI

struct MenuContentView: View {
    @ObservedObject var manager: BridgeProcessManager
    @ObservedObject var settings: BridgeSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusSection
            Divider()
            controlSection
            Divider()
            monitoringSection
            if let banner = manager.bannerMessage {
                bannerView(banner)
            }
            Divider()
            footerSection
        }
        .padding(16)
        .frame(width: 320)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusTint)
                    .accessibilityHidden(true)
                Text(statusText)
                    .font(.headline)
                    .accessibilityLabel("Bridge status")
                    .accessibilityValue(statusText)
            }
            Text(manager.routingMode.menuLabel)
                .font(.caption.weight(.semibold))
            Text(manager.routingMode.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if manager.devices.isEmpty {
                Text("No output devices")
                    .font(.headline)
                Text("Connect headphones or an audio interface, then choose an output here.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("Output", selection: outputSelection) {
                    ForEach(manager.devices) { device in
                        Text("\(device.name) (\(Int(device.nominalRate)) Hz)")
                            .tag(Optional(device.uid))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Picker("Latency", selection: $settings.latencyPreset) {
                ForEach(LatencyPreset.allCases) { preset in
                    Text(preset.menuTitle).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: settings.latencyPreset) { _, _ in
                settings.onPresetChanged()
                restartIfRunning()
            }

            Picker("SRC quality", selection: srcQualityBinding) {
                ForEach(SrcQuality.allCases) { quality in
                    Text(quality.menuTitle).tag(quality)
                }
            }
            .pickerStyle(.menu)

            primaryButton
        }
    }

    private var monitoringSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(latencyHeadline)
                .font(.title3.weight(.semibold))
                .accessibilityLabel(latencyAccessibilityLabel)

            if manager.isRunning, let metrics = manager.latestMetrics {
                ProgressView(value: metrics.fillProgress)
                    .accessibilityLabel("Buffer fill")
                    .accessibilityValue("\(String(format: "%.1f", metrics.fillMs)) milliseconds")

                HStack {
                    Text("Fill")
                    Spacer()
                    Text(String(format: "%.1f ms", metrics.fillMs))
                        .monospacedDigit()
                }
                .font(.caption)

                HStack {
                    Text(glitchLabel(metrics: metrics))
                    Spacer()
                    if manager.glitchFlash {
                        Image(systemName: "waveform.badge.exclamationmark")
                            .foregroundStyle(Color.accentColor)
                            .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                    }
                }
                .font(.caption)

                HStack {
                    Text("Ratio")
                    Spacer()
                    Text(String(format: "%.6f", metrics.ratio))
                        .monospacedDigit()
                }
                .font(.caption)

                if manager.metricsStale {
                    Text("Metrics stale")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(settings.latencyPreset.stoppedLatencyHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footerSection: some View {
        HStack {
            Text("APM44 Bridge \(Bundle.main.shortVersion)")
                .font(.caption)
            Spacer()
            Link("Routing help", destination: URL(string: "https://github.com/ExistentialAudio/BlackHole")!)
                .font(.caption)
        }
    }

    private func bannerView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
        }
        .transition(.opacity)
    }

    private var primaryButton: some View {
        Group {
            if manager.isRunning {
                Button("Stop Bridge") {
                    manager.stop()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .frame(maxWidth: .infinity, minHeight: 28)
            } else {
                Button("Start Bridge") {
                    manager.start()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart)
                .frame(maxWidth: .infinity, minHeight: 28)
            }
        }
        .accessibilityHint(manager.isRunning ? "Stops monitoring bridge" : "Starts bridge to selected output")
    }

    private var canStart: Bool {
        manager.binaryURL != nil && settings.outputDeviceUid != nil && !manager.devices.isEmpty
    }

    private var outputSelection: Binding<String?> {
        Binding(
            get: { settings.outputDeviceUid },
            set: { newValue in
                settings.outputDeviceUid = newValue
                restartIfRunning()
            }
        )
    }

    private var srcQualityBinding: Binding<SrcQuality> {
        Binding(
            get: { settings.effectiveSrcQuality },
            set: { newValue in
                settings.srcQualityOverride = newValue
                restartIfRunning()
            }
        )
    }

    private func restartIfRunning() {
        guard manager.isRunning else { return }
        manager.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            manager.start()
        }
    }

    private var statusText: String {
        if manager.isRunning {
            return manager.connectionPhase.label
        }
        switch manager.state {
        case .idle: return "Stopped"
        case .starting: return "Starting…"
        case .running: return manager.connectionPhase.label
        case .stopping: return "Stopping…"
        case .error: return "Error"
        }
    }

    private var statusSymbol: String {
        switch manager.state {
        case .error: return "headphones.circle.fill"
        default: return "headphones"
        }
    }

    private var statusTint: Color {
        switch manager.state {
        case .running: return .green
        case .error: return .red
        default: return .secondary
        }
    }

    private var latencyHeadline: String {
        if manager.isRunning, let metrics = manager.latestMetrics {
            return metrics.latencyLabel
        }
        return "Monitoring adds latency"
    }

    private var latencyAccessibilityLabel: String {
        if manager.isRunning, let metrics = manager.latestMetrics {
            return "Estimated round-trip monitoring latency, not zero. \(metrics.latencyLabel)"
        }
        return "Monitoring adds latency when bridge is running"
    }

    private func glitchLabel(metrics: BridgeMetricsSnapshot) -> String {
        var label = "Glitches: \(metrics.xruns)"
        if manager.glitchFlash {
            label += " (new)"
        }
        return label
    }
}

private extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1"
    }
}
