import SwiftUI

struct MenuContentView: View {
    @ObservedObject var manager: BridgeProcessManager
    @ObservedObject var settings: BridgeSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusHero
            routingChain
            controlCard
            primaryButtons
            Divider()
            statusDetail
            if let banner = manager.bannerMessage {
                bannerView(banner)
            }
            Divider()
            footerSection
        }
        .padding(16)
        .frame(width: 340)
    }

    // MARK: - Status hero

    private var statusHero: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusTint.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: statusSymbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(statusTint)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.headline)
                Text(manager.routingMode.menuLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if manager.isRunning, let metrics = manager.latestMetrics {
                latencyBadge(metrics)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bridge status")
        .accessibilityValue(statusText)
    }

    private func latencyBadge(_ metrics: BridgeMetricsSnapshot) -> some View {
        Text(shortLatency(metrics))
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(statusTint.opacity(0.18)))
            .foregroundStyle(statusTint)
            .accessibilityLabel(metrics.latencyLabel)
    }

    private var routingChain: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(manager.routingMode.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .accessibilityLabel("Signal path")
        .accessibilityValue(manager.routingMode.detail)
    }

    // MARK: - Controls

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            outputControl
            latencyControl
            qualityControl
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }

    private func controlHeader(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
                .font(.subheadline.weight(.medium))
        }
    }

    private var outputControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            controlHeader("hifispeaker.fill", "Output")
            if manager.devices.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "speaker.slash")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No output devices")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("Connect headphones or an audio interface, then choose an output here.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Picker("Output", selection: outputSelection) {
                    if settings.outputDeviceUid == nil {
                        Text("Choose output…").tag(String?.none)
                    }
                    ForEach(manager.devices) { device in
                        Text("\(device.name) (\(Int(device.nominalRate)) Hz)")
                            .tag(Optional(device.uid))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var latencyControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            controlHeader("speedometer", "Latency")
            Picker("Latency", selection: $settings.latencyPreset) {
                ForEach(LatencyPreset.allCases) { preset in
                    Text(preset.shortTitle).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: settings.latencyPreset) { _, _ in
                Task { await manager.restartForSettingsChange() }
            }
            Text(settings.latencyPreset.targetDescription(halMode: manager.routingMode == .halVirtualDevice))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var qualityControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            controlHeader("waveform.path", "Quality")
            Picker("SRC quality", selection: srcQualityBinding) {
                ForEach(SrcQuality.allCases) { quality in
                    Text(quality.menuTitle).tag(quality)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var primaryButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if showsStartButton {
                    Button {
                        manager.start()
                    } label: {
                        Label("Start Bridge", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canStart || manager.isTransitioning)
                }

                if showsStopButton {
                    Button(role: .destructive) {
                        manager.stop()
                    } label: {
                        Label("Stop Bridge", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(manager.isTransitioning)
                }
            }

            if showsRestartButton {
                Button {
                    Task { await manager.restart(reason: .user) }
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(manager.isTransitioning || !canStart)
            }

            Button {
                Task { await manager.quitApplication() }
            } label: {
                Label("Quit APM44 Bridge", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(manager.isTransitioning)
        }
        .controlSize(.large)
        .accessibilityHint("Controls bridge process lifecycle")
    }

    private var showsStartButton: Bool {
        switch manager.state {
        case .idle, .error: return true
        default: return false
        }
    }

    private var showsStopButton: Bool {
        switch manager.state {
        case .running, .reconnecting: return true
        default: return false
        }
    }

    private var showsRestartButton: Bool {
        switch manager.state {
        case .running, .error: return true
        default: return false
        }
    }

    // MARK: - Running metrics / idle hint

    private var statusDetail: some View {
        Group {
            if manager.isRunning, let metrics = manager.latestMetrics {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Buffer fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f ms", metrics.fillMs))
                                .font(.caption)
                                .monospacedDigit()
                        }
                        ProgressView(value: metrics.fillProgress)
                            .accessibilityLabel("Buffer fill")
                            .accessibilityValue("\(String(format: "%.1f", metrics.fillMs)) milliseconds")
                    }

                    HStack(alignment: .top) {
                        metricStat("Hard xruns", "\(metrics.xruns)", flashing: manager.glitchFlash)
                        Spacer()
                        metricStat("Recoveries", "\(metrics.underruns)", alignment: .trailing)
                    }

                    HStack(alignment: .top) {
                        metricStat("Drift ratio", String(format: "%.4f", metrics.ratio))
                        Spacer()
                    }

                    if manager.metricsStale {
                        Label("Metrics stale", systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Monitoring adds latency")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(settings.latencyPreset.stoppedLatencyHint(halMode: manager.routingMode == .halVirtualDevice))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricStat(
        _ title: String,
        _ value: String,
        flashing: Bool = false,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if flashing {
                    Image(systemName: "waveform.badge.exclamationmark")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                }
            }
            Text(value)
                .font(.callout.weight(.medium))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Open at login", isOn: openAtLoginBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.caption)
            HStack {
                Text("APM44 Bridge \(Bundle.main.shortVersion)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Link("Cubase setup", destination: URL(string: "https://github.com/Niko96-dotcom/apm44-bridge/blob/master/docs/first-run-cubase.md")!)
                    .font(.caption2)
            }
        }
    }

    private func bannerView(_ message: String) -> some View {
        let isReconnecting = message.localizedCaseInsensitiveContains("reconnecting")
            || message.localizedCaseInsensitiveContains("attempt")
            || message.localizedCaseInsensitiveContains("waiting for")
        let tint: Color = isReconnecting ? .orange : .red
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(tint)
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.1))
        )
        .transition(.opacity)
    }

    // MARK: - Bindings

    private var openAtLoginBinding: Binding<Bool> {
        Binding(
            get: { LaunchAtLogin.isEnabled },
            set: { enabled, _ in
                do {
                    try LaunchAtLogin.setEnabled(enabled)
                } catch {
                    manager.bannerMessage = "Could not update Open at login"
                }
            }
        )
    }

    private var canStart: Bool {
        manager.binaryURL != nil && settings.outputDeviceUid != nil && !manager.devices.isEmpty
    }

    private var outputSelection: Binding<String?> {
        Binding(
            get: { settings.outputDeviceUid },
            set: { newValue in
                settings.outputDeviceUid = newValue
                Task { await manager.restartForSettingsChange() }
            }
        )
    }

    private var srcQualityBinding: Binding<SrcQuality> {
        Binding(
            get: { settings.effectiveSrcQuality },
            set: { newValue in
                settings.srcQualityOverride = newValue
                Task { await manager.restartForSettingsChange() }
            }
        )
    }

    // MARK: - Derived presentation

    private var statusText: String {
        if manager.isRunning {
            return manager.connectionPhase.label
        }
        switch manager.state {
        case .idle: return "Stopped"
        case .starting: return "Starting…"
        case .running: return manager.connectionPhase.label
        case .stopping: return "Stopping…"
        case .reconnecting:
            if let banner = manager.bannerMessage,
               banner.localizedCaseInsensitiveContains("attempt") {
                return banner
            }
            return "Reconnecting…"
        case .error(let message):
            if message.count > 60 {
                return String(message.prefix(57)) + "…"
            }
            return message
        }
    }

    private var statusSymbol: String {
        switch manager.state {
        case .error: return "exclamationmark.triangle.fill"
        case .reconnecting: return "arrow.triangle.2.circlepath"
        case .running: return "waveform"
        default: return "headphones"
        }
    }

    private var statusTint: Color {
        switch manager.state {
        case .error: return .red
        case .reconnecting: return .orange
        case .running: return manager.connectionPhase == .waitingForDAW ? .orange : .green
        case .starting: return .orange
        default: return .secondary
        }
    }

    private func shortLatency(_ metrics: BridgeMetricsSnapshot) -> String {
        "~\(Int(max(1, metrics.estimatedRtMs.rounded()))) ms"
    }
}

private extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.11.0"
    }
}
