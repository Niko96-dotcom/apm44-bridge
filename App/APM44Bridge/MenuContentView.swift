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
    @State private var showErrorDetails = false
    @State private var heldMetrics: BridgeMetricsSnapshot?
    /// Fixed layout geometry (see body `.padding(outerPadding)` +
    /// `.frame(width: contentWidth)`): menu pop-up bezels hug their label
    /// and segmented controls hug in window-hosted views, so equal
    /// full-width rows need an explicit shared width.
    private let contentWidth: CGFloat = 340
    private let outerPadding: CGFloat = 16
    private let cardPadding: CGFloat = 12
    private var controlRowWidth: CGFloat {
        contentWidth - outerPadding * 2 - cardPadding * 2
    }
    /// Only the Controls window owns global Setup presentation (F3).
    /// Menu-bar popover and Settings use `false` so one Help command
    /// cannot open duplicate sheets. Footer buttons still work locally.
    var presentsGlobalSetup: Bool = false
    @ObservedObject var setupCoordinator: SetupCoordinator = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusHero
            controlCard
            updateSection
            primaryButtons
            if let reason = startBlockedReason, showsStartButton, !manager.isApplyingSettings {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("start-blocked-reason")
                    .accessibilityLabel(reason)
            }
            if showsStatusDetail {
                Divider()
                statusDetail
            }
            if let banner = visibleBanner {
                bannerView(banner)
            }
            Divider()
            footerSection
        }
        .padding(outerPadding)
        .frame(width: contentWidth)
        .onAppear {
            launchAtLogin.refresh()
            // F3: global Help requests are owned solely by Controls.
            // First-run auto-presentation is first-come-wins so the initial
            // Setup still appears once even when several windows exist.
            // Footer buttons always work locally in every host.
            if presentsGlobalSetup, setupCoordinator.isSetupRequested {
                showFirstRun = true
                setupCoordinator.consumeSetupRequest()
            } else if !UserDefaults.standard.bool(forKey: FirstRunKeys.completed),
                      setupCoordinator.claimFirstRunAuto() {
                showFirstRun = true
            }
        }
        .task {
            _ = await manager.refreshDevices()
        }
        .onAppear {
            if let current = manager.latestMetrics { heldMetrics = current }
        }
        .onChange(of: manager.latestMetrics) { _, new in
            if let new { heldMetrics = new }
        }
        .onChange(of: manager.state) { _, _ in
            clearHeldMetricsIfSettled()
        }
        .onChange(of: manager.isApplyingSettings) { _, _ in
            clearHeldMetricsIfSettled()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
        .sheet(isPresented: $showFirstRun) {
            FirstRunPreflightView(manager: manager, isPresented: $showFirstRun)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAPM44Setup)) { _ in
            guard presentsGlobalSetup else { return }
            showFirstRun = true
        }
        .onReceive(setupCoordinator.$isSetupRequested) { requested in
            guard presentsGlobalSetup, requested else { return }
            showFirstRun = true
            setupCoordinator.consumeSetupRequest()
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

            Text(statusText)
                .font(.headline)

            Spacer(minLength: 8)

            if let metrics = effectiveDetailMetrics {
                latencyBadge(metrics)
                    .opacity(showsHeldMetrics ? 0.5 : 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppStrings.bridgeStatus)
        .accessibilityValue(statusText)
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

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            outputControl
            latencyControl
            qualityControl
        }
        .padding(cardPadding)
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
                FullWidthPopUpButton(
                    width: controlRowWidth,
                    options: outputOptions,
                    selectedId: settings.outputDeviceUid ?? "",
                    accessibilityLabelText: AppStrings.output
                ) { selectOutput($0.isEmpty ? nil : $0) }
                .accessibilityIdentifier("output-picker")
            }
        }
    }

    private var outputOptions: [FullWidthPopUpButton.Option] {
        var options = [FullWidthPopUpButton.Option(
            id: "",
            title: AppStrings.chooseOutput,
            isEnabled: true
        )]
        if let uid = settings.outputDeviceUid,
           !manager.devices.contains(where: { $0.uid == uid }) {
            options.append(FullWidthPopUpButton.Option(
                id: uid,
                title: "\(manager.deviceDisplayName) — \(AppStrings.unavailableSuffix)",
                isEnabled: true
            ))
        }
        options += manager.devices.map { device in
            FullWidthPopUpButton.Option(
                id: device.uid,
                title: device.pickerLabel,
                isEnabled: device.isMonitoringCompatible
            )
        }
        return options
    }

    private func selectOutput(_ uid: String?) {
        guard settings.outputDeviceUid != uid else { return }
        settings.outputDeviceUid = uid
        Task { await manager.restartForSettingsChange() }
    }

    private var latencyControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            controlHeader("speedometer", AppStrings.buffering)
            HStack(spacing: 0) {
                ForEach(Array(LatencyPreset.allCases.enumerated()), id: \.element) { index, preset in
                    let selected = preset == settings.latencyPreset
                    if index > 0 {
                        let hideSeparator = LatencyPreset.allCases[index - 1] == settings.latencyPreset || selected
                        Rectangle()
                            .fill(Color.primary.opacity(0.18))
                            .frame(width: 1, height: 14)
                            .opacity(hideSeparator ? 0 : 1)
                    }
                    Button {
                        selectLatency(preset)
                    } label: {
                        Text(preset.shortTitle)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(selected ? Color.accentColor : Color.clear)
                            )
                            .foregroundStyle(selected ? .white : .primary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.shortTitle)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .frame(width: controlRowWidth)
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(nsColor: .controlColor))
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(AppStrings.buffering)
        }
    }

    private var qualityControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            controlHeader("waveform.path", AppStrings.quality)
            FullWidthPopUpButton(
                width: controlRowWidth,
                options: SrcQuality.allCases.map { quality in
                    FullWidthPopUpButton.Option(
                        id: quality.rawValue,
                        title: quality.menuTitle,
                        isEnabled: true
                    )
                },
                selectedId: settings.effectiveSrcQuality.rawValue,
                accessibilityLabelText: AppStrings.quality
            ) {
                if let quality = SrcQuality(rawValue: $0) { selectQuality(quality) }
            }
            .accessibilityIdentifier("quality-picker")
        }
    }

    private func selectLatency(_ preset: LatencyPreset) {
        guard settings.latencyPreset != preset else { return }
        settings.latencyPreset = preset
        Task { await manager.restartForSettingsChange() }
    }

    private func selectQuality(_ quality: SrcQuality) {
        guard settings.effectiveSrcQuality != quality else { return }
        settings.srcQualityOverride = quality
        Task { await manager.restartForSettingsChange() }
    }

    private var primaryButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if showsStartButton {
                    startButton
                }

                if showsStopButton {
                    Button {
                        manager.stop()
                    } label: {
                        Label(AppStrings.stopBridge, systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manager.isTransitioning || manager.isApplyingSettings)
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
                .disabled(manager.isTransitioning || manager.isApplyingSettings || startBlockedReason != nil)
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
            .disabled(manager.isTransitioning)
            .accessibilityLabel(AppStrings.quitApp)
            .accessibilityIdentifier("quit-app")
        }
        .controlSize(.regular)
    }

    @ViewBuilder
    private var startButton: some View {
        let enabled = startBlockedReason == nil && !manager.isTransitioning
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
                    dismissMenuBarPanel()
                    updater.checkForUpdates()
                } label: {
                    Text(AppStrings.updateAvailable(version))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityLabel(AppStrings.updateAvailable(version))
            case let .readyToInstall(version):
                Button {
                    dismissMenuBarPanel()
                    updater.showPendingUpdate()
                } label: {
                    Text(AppStrings.installUpdateAndRelaunch(version))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityLabel(AppStrings.installUpdateAndRelaunch(version))
                .accessibilityIdentifier("install-update")
            case let .installing(version):
                updateStatus(AppStrings.installingUpdate(version), systemImage: "gearshape", tint: .accentColor)
            case .cancelled:
                updateStatus(AppStrings.updateCancelled, systemImage: "xmark.circle", tint: .secondary)
            case let .failed(message):
                VStack(alignment: .leading, spacing: 8) {
                    updateStatus(message, systemImage: "exclamationmark.triangle", tint: .orange)
                    if let retryVersion = updater.lastOfferedVersion {
                        Text(AppStrings.updateAvailable(retryVersion))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        dismissMenuBarPanel()
                        updater.checkForUpdates()
                    } label: {
                        Text(AppStrings.tryAgain)
                    }
                    .buttonStyle(.link)
                    .accessibilityLabel(AppStrings.tryAgain)
                    .accessibilityIdentifier("retry-update")
                }
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
        if manager.isApplyingSettings { return false }
        switch manager.state {
        case .idle, .error: return true
        case .starting, .running, .stopping, .reconnecting: return false
        }
    }

    private var showsStopButton: Bool {
        if manager.isApplyingSettings { return true }
        switch manager.state {
        case .running, .reconnecting: return true
        case .idle, .starting, .stopping, .error: return false
        }
    }

    private var showsRestartButton: Bool {
        if manager.isApplyingSettings { return true }
        switch manager.state {
        case .running, .error: return true
        case .idle, .starting, .stopping, .reconnecting: return false
        }
    }

    /// While settings apply, and until the relaunched daemon's first tick,
    /// the last snapshot stays visible (dimmed) so the layout never jumps.
    private var effectiveDetailMetrics: BridgeMetricsSnapshot? {
        if manager.isApplyingSettings || manager.isRunning {
            return manager.latestMetrics ?? heldMetrics
        }
        return nil
    }

    private var showsHeldMetrics: Bool {
        manager.latestMetrics == nil && effectiveDetailMetrics != nil
    }

    private func clearHeldMetricsIfSettled() {
        guard !manager.isApplyingSettings else { return }
        switch manager.state {
        case .idle, .error: heldMetrics = nil
        default: break
        }
    }

    private var statusDetail: some View {
        Group {
            if let metrics = effectiveDetailMetrics {
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
                .opacity(showsHeldMetrics ? 0.5 : 1)
            } else if case .error(let message) = manager.state,
                      errorHasContent(message) {
                errorDetailView(message: message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: errorIdentity) { _, _ in
            showErrorDetails = false
        }
    }

    private var errorIdentity: String {
        if case .error(let message) = manager.state { return message }
        return ""
    }

    /// The details section only exists when it holds content: live metrics,
    /// or an error with recovery guidance/a diagnostic. No empty chrome.
    /// While settings are being applied the last seen snapshot stays visible
    /// (dimmed) so the popover height does not jump.
    private var showsStatusDetail: Bool {
        if effectiveDetailMetrics != nil { return true }
        if case .error(let message) = manager.state { return errorHasContent(message) }
        return false
    }

    private func errorHasContent(_ message: String) -> Bool {
        let presentation = BridgeErrorPresentation.presentation(for: message)
        return presentation.recovery != nil || presentation.diagnostic != nil
    }

    @ViewBuilder
    private func errorDetailView(message: String) -> some View {
        let presentation = BridgeErrorPresentation.presentation(for: message)
        VStack(alignment: .leading, spacing: 6) {
            if let recovery = presentation.recovery {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(recovery)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("error-recovery")
                }
            }
            if let diagnostic = presentation.diagnostic {
                DisclosureGroup(AppStrings.errorDetails, isExpanded: $showErrorDetails) {
                    Text(diagnostic)
                        .font(.caption2)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("error-diagnostic")
                        .accessibilityLabel(diagnostic)
                }
                .font(.caption)
                .accessibilityIdentifier("error-details-disclosure")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
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
        manager.startBlockedReason
    }

    private var statusText: String {
        if manager.isApplyingSettings {
            return AppStrings.applyingSettings
        }
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
            // F2: never truncate helper jargon into the headline. Use a
            // short localized headline; the full diagnostic lives under
            // Details with mapped recovery text.
            return BridgeErrorPresentation.headline(for: message)
        }
    }

    /// F2: banner that duplicates the raw error diagnostic is suppressed —
    /// the error section already shows headline + recovery + Details.
    private var visibleBanner: String? {
        guard let banner = manager.bannerMessage else { return nil }
        if case .error(let message) = manager.state,
           banner == message,
           BridgeErrorPresentation.presentation(for: message).diagnostic != nil {
            return nil
        }
        return banner
    }

    private var statusSymbol: String {
        if manager.isApplyingSettings { return "arrow.triangle.2.circlepath" }
        switch manager.state {
        case .error: return "exclamationmark.triangle.fill"
        case .reconnecting: return "arrow.triangle.2.circlepath"
        case .running: return "waveform"
        case .idle, .starting, .stopping: return "headphones"
        }
    }

    private var statusTint: Color {
        if manager.isApplyingSettings { return .orange }
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
