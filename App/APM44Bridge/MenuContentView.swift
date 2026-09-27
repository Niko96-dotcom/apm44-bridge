import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var manager: BridgeProcessManager
    @ObservedObject var settings: BridgeSettings
    @EnvironmentObject private var updater: SparkleUpdateController
    @StateObject private var launchAtLogin = LaunchAtLoginController()
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
            MenuStatusHero(presentation: presentation)
            MenuControlCard(
                manager: manager,
                settings: settings,
                controlRowWidth: controlRowWidth,
                cardPadding: cardPadding
            )
            MenuUpdateSectionView(updateModel: updateModel)
            MenuPrimaryButtons(manager: manager, presentation: presentation)
            if let reason = presentation.visibleStartBlockedReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("start-blocked-reason")
                    .accessibilityLabel(reason)
            }
            if presentation.showsStatusDetail {
                Divider()
                MenuStatusDetail(
                    manager: manager,
                    presentation: presentation,
                    showMonitoringDetails: $showMonitoringDetails,
                    showErrorDetails: $showErrorDetails
                )
            }
            if let banner = presentation.visibleBanner {
                MenuBanner(message: banner, manager: manager)
                    .transition(.opacity)
            }
            Divider()
            MenuFooterSection(manager: manager, launchAtLogin: launchAtLogin, showFirstRun: $showFirstRun)
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

    /// Pure presentation model built from plain manager values. All decision
    /// logic lives in `MenuPresentation`; the view only renders.
    private var presentation: MenuPresentation {
        MenuPresentation(
            state: manager.state,
            isApplyingSettings: manager.isApplyingSettings,
            connectionPhase: manager.connectionPhase,
            bannerMessage: manager.bannerMessage,
            metricsStale: manager.metricsStale,
            startBlockedReason: manager.startBlockedReason,
            latestMetrics: manager.latestMetrics,
            heldMetrics: heldMetrics
        )
    }

    private var updateModel: MenuUpdateSection {
        MenuPresentation.updateSection(
            for: updater.state,
            lastOfferedVersion: updater.lastOfferedVersion
        )
    }

    private func clearHeldMetricsIfSettled() {
        if presentation.shouldClearHeldMetrics {
            heldMetrics = nil
        }
    }
}
