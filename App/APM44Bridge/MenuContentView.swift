import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var manager: BridgeProcessManager
    @ObservedObject var settings: BridgeSettings
    @EnvironmentObject private var updater: SparkleUpdateController
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showFirstRun = false
    @State private var showMonitoringDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusHero
            routingChain
            controlCard
            updateSection
            primaryButtons
            if let reason = startBlockedReason, showsStartButton {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("start-blocked-reason")
                    .accessibilityLabel(reason)
            }
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
        .onAppear {
            launchAtLogin.refresh()
            if !UserDefaults.standard.bool(forKey: FirstRunKeys.completed) {
                showFirstRun = true
            }
        }
        .task {
            _ = await manager.refreshDevices()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
        .sheet(isPresented: $showFirstRun) {
            FirstRunPreflightView(manager: manager, isPresented: $showFirstRun)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAPM44Setup)) { _ in
            showFirstRun = true
        }
    }

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
        .accessibilityLabel(AppStrings.bridgeStatus)
        .accessibilityValue("\(statusText), \(manager.routingMode.menuLabel)")
    }

    private func latencyBadge(_ metrics: BridgeMetricsSnapshot) -> some View {
        Text(AppStrings.latencyBadge(Int(max(1, metrics.estimatedRtMs.rounded()))))
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(statusTint.opacity(0.18)))
            .foregroundStyle(statusTint)
            .accessibilityLabel(metrics.bridgeBufferingLabel)
    }

    private var routingChain: some View {
        let detail = manager.routingMode.detail(
            outputName: settings.outputDeviceUid == nil ? nil : manager.deviceDisplayName
        )
        return HStack(alignment: .center, spacing: 8) {
            Text(detail)
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
        .accessibilityLabel(AppStrings.signalPath)
        .accessibilityValue(detail)
    }

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
            controlHeader("hifispeaker.fill", AppStrings.output)
            if manager.devices.isEmpty, settings.outputDeviceUid == nil {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "speaker.slash")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppStrings.noOutputDevices)
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(AppStrings.noOutputDevicesHint)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Picker(AppStrings.output, selection: outputSelection) {
                    Text(AppStrings.chooseOutput).tag("")
                    if let uid = settings.outputDeviceUid,
                       !manager.devices.contains(where: { $0.uid == uid }) {
                        Text("\(manager.deviceDisplayName) — \(AppStrings.unavailableSuffix)")
                            .tag(uid)
                    }
                    ForEach(manager.devices) { device in
                        Text(device.pickerLabel)
                            .tag(device.uid)
                            .disabled(!device.isMonitoringCompatible)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                if let selectedUid = settings.outputDeviceUid,
                   let selected = manager.devices.first(where: { $0.uid == selectedUid }) {
                    Text(selected.detailLabel)
                        .font(.caption2)
                        .foregroundStyle(selected.isMonitoringCompatible ? Color.secondary : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var latencyControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            controlHeader("speedometer", AppStrings.buffering)
            Picker(AppStrings.buffering, selection: $settings.latencyPreset) {
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
            controlHeader("waveform.path", AppStrings.quality)
            Picker(AppStrings.quality, selection: srcQualityBinding) {
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
                    startButton
                }

                if showsStopButton {
                    Button(AppStrings.stopBridge) {
                        manager.stop()
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .disabled(manager.isTransitioning)
                    .accessibilityLabel(AppStrings.stopBridge)
                    .accessibilityIdentifier("stop-bridge")
                }
            }

            if showsRestartButton {
                Button {
                    Task { await manager.restart(reason: .user) }
                } label: {
                    Label(AppStrings.restart, systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(manager.isTransitioning || startBlockedReason != nil)
                .accessibilityLabel(AppStrings.restart)
                .accessibilityIdentifier("restart-bridge")
            }

            Button(AppStrings.quitApp) {
                Task { await manager.quitApplication() }
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
            .disabled(manager.isTransitioning)
            .accessibilityLabel(AppStrings.quitApp)
            .accessibilityIdentifier("quit-app")
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var startButton: some View {
        let enabled = startBlockedReason == nil && !manager.isTransitioning
        if enabled {
            Button(AppStrings.startBridge) {
                manager.start()
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(AppStrings.startBridge)
            .accessibilityIdentifier("start-bridge")
        } else {
            Button(AppStrings.startBridge) {
                manager.start()
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
            .disabled(true)
            .accessibilityLabel(AppStrings.startBridge)
            .accessibilityHint(startBlockedReason ?? "")
            .accessibilityIdentifier("start-bridge")
        }
    }

    private var updateSection: some View {
        Group {
            switch updater.state {
            case .idle:
                EmptyView()
            case .checking:
                updateStatus(AppStrings.checkingUpdates, systemImage: "arrow.triangle.2.circlepath", tint: .secondary)
            case let .available(version):
                Button {
                    updater.checkForUpdates()
                } label: {
                    Text(AppStrings.updateAvailable(version))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityLabel(AppStrings.updateAvailable(version))
            case let .readyToInstall(version):
                updateStatus(AppStrings.updateReady(version), systemImage: "checkmark.circle", tint: .green)
            case let .installing(version):
                updateStatus(AppStrings.installingUpdate(version), systemImage: "gearshape", tint: .accentColor)
            case .cancelled:
                updateStatus(AppStrings.updateCancelled, systemImage: "xmark.circle", tint: .secondary)
            case let .failed(message):
                updateStatus(message, systemImage: "exclamationmark.triangle", tint: .orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func updateStatus(_ message: String, systemImage: String, tint: Color) -> some View {
        Label {
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.1))
        )
    }

    private var showsStartButton: Bool {
        switch manager.state {
        case .idle, .error: return true
        case .starting, .running, .stopping, .reconnecting: return false
        }
    }

    private var showsStopButton: Bool {
        switch manager.state {
        case .running, .reconnecting: return true
        case .idle, .starting, .stopping, .error: return false
        }
    }

    private var showsRestartButton: Bool {
        switch manager.state {
        case .running, .error: return true
        case .idle, .starting, .stopping, .reconnecting: return false
        }
    }

    private var statusDetail: some View {
        Group {
            if manager.isRunning, let metrics = manager.latestMetrics {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(AppStrings.bufferFill)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f ms", metrics.fillMs))
                                .font(.caption)
                                .monospacedDigit()
                        }
                        ProgressView(value: metrics.fillProgress)
                            .accessibilityLabel(AppStrings.bufferFill)
                            .accessibilityValue(AppStrings.fillMilliseconds(String(format: "%.1f", metrics.fillMs)))
                    }

                    DisclosureGroup(AppStrings.details, isExpanded: $showMonitoringDetails) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                metricStat(AppStrings.knownLostFrames, "\(metrics.knownFrameLoss)", flashing: manager.glitchFlash)
                                Spacer()
                                metricStat(AppStrings.recoveries, "\(metrics.underruns)", alignment: .trailing)
                            }

                            HStack(alignment: .top) {
                                metricStat(AppStrings.halDrops, "\(metrics.producerDroppedFrames)")
                                Spacer()
                                metricStat(AppStrings.outputStarved, "\(metrics.outputStarvationFrames)", alignment: .trailing)
                            }

                            HStack(alignment: .top) {
                                metricStat(AppStrings.partialShortages, "\(metrics.partialShortageEvents)")
                                Spacer()
                                metricStat(
                                    AppStrings.rebuffersSrcResets,
                                    "\(metrics.rebufferEvents) / \(metrics.converterResetEvents)",
                                    alignment: .trailing
                                )
                            }

                            HStack(alignment: .top) {
                                metricStat(AppStrings.driftRatio, String(format: "%.4f", metrics.ratio))
                                Spacer()
                            }
                        }
                        .padding(.top, 6)
                    }
                    .font(.caption)

                    if manager.metricsStale {
                        Label(AppStrings.metricsStale, systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(settings.latencyPreset.stoppedLatencyHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

    private var footerSection: some View {
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
            Link(AppStrings.cubaseSetupGuide, destination: HelpLinks.cubaseSetup)
                .font(.caption2)
                .accessibilityLabel(AppStrings.cubaseSetupGuide)
        }
    }

    private func bannerView(_ message: String) -> some View {
        let isReconnecting: Bool = {
            switch manager.state {
            case .reconnecting, .starting: return true
            default: return false
            }
        }()
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

    private var startBlockedReason: String? {
        BridgeStartReadiness.blockedReason(
            binaryMissing: manager.binaryURL == nil,
            selectedUid: settings.outputDeviceUid,
            devices: manager.devices,
            lastKnownName: manager.deviceDisplayName
        )
    }

    private var outputSelection: Binding<String> {
        Binding(
            get: { settings.outputDeviceUid ?? "" },
            set: { newValue in
                settings.outputDeviceUid = newValue.isEmpty ? nil : newValue
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

    private var statusText: String {
        if manager.isRunning {
            return manager.connectionPhase.label
        }
        switch manager.state {
        case .idle: return AppStrings.stopped
        case .starting: return AppStrings.starting
        case .running: return manager.connectionPhase.label
        case .stopping: return AppStrings.stopping
        case .reconnecting:
            if let banner = manager.bannerMessage {
                return banner
            }
            return AppStrings.reconnecting
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
        case .idle, .starting, .stopping: return "headphones"
        }
    }

    private var statusTint: Color {
        switch manager.state {
        case .error: return .red
        case .reconnecting, .starting: return .orange
        case .running:
            return manager.metricsStale || manager.connectionPhase == .waitingForDAW ? .orange : .green
        case .idle, .stopping: return .secondary
        }
    }
}

enum HelpLinks {
    static let cubaseSetup = URL(string: "https://github.com/Niko96-dotcom/apm44-bridge/blob/master/docs/first-run-cubase.md")!
    static let releases = URL(string: "https://github.com/Niko96-dotcom/apm44-bridge/releases/latest")!
}

private extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
    }
}
