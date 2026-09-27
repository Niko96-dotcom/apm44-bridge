import XCTest
@testable import APM44Bridge

private func makePresentation(
    state: BridgeRunState = .idle,
    isApplyingSettings: Bool = false,
    connectionPhase: BridgeConnectionPhase = .stopped,
    bannerMessage: String? = nil,
    metricsStale: Bool = false,
    startBlockedReason: String? = nil,
    latestMetrics: BridgeMetricsSnapshot? = nil,
    heldMetrics: BridgeMetricsSnapshot? = nil
) -> MenuPresentation {
    MenuPresentation(
        state: state,
        isApplyingSettings: isApplyingSettings,
        connectionPhase: connectionPhase,
        bannerMessage: bannerMessage,
        metricsStale: metricsStale,
        startBlockedReason: startBlockedReason,
        latestMetrics: latestMetrics,
        heldMetrics: heldMetrics
    )
}

private func makeMetrics(
    fillMs: Double = 10,
    estimatedRtMs: Double = 15,
    targetFillMs: Double = 20
) -> BridgeMetricsSnapshot {
    BridgeMetricsSnapshot(
        fillMs: fillMs,
        ratio: 1.0,
        ppm: 0,
        underruns: 0,
        overruns: 0,
        xruns: 0,
        estimatedRtMs: estimatedRtMs,
        targetFillMs: targetFillMs,
        srcQuality: "medium"
    )
}

final class MenuPresentationButtonTests: XCTestCase {
    func testButtonVisibilityTable() {
        // (state, applying settings) -> (start, stop, restart)
        let rows: [(BridgeRunState, Bool, Bool, Bool, Bool)] = [
            (.idle, false, true, false, false),
            (.starting, false, false, false, false),
            (.running, false, false, true, true),
            (.stopping, false, false, false, false),
            (.reconnecting, false, false, true, false),
            (.error("boom"), false, true, false, true),
            (.idle, true, false, true, true),
            (.starting, true, false, true, true),
            (.running, true, false, true, true),
            (.stopping, true, false, true, true),
            (.reconnecting, true, false, true, true),
            (.error("boom"), true, false, true, true),
        ]
        for (state, applying, start, stop, restart) in rows {
            let presentation = makePresentation(state: state, isApplyingSettings: applying)
            let label = "state=\(state) applying=\(applying)"
            XCTAssertEqual(presentation.showsStartButton, start, "start \(label)")
            XCTAssertEqual(presentation.showsStopButton, stop, "stop \(label)")
            XCTAssertEqual(presentation.showsRestartButton, restart, "restart \(label)")
        }
    }

    func testStartDisabledWhenBlockedOrTransitioning() {
        XCTAssertTrue(makePresentation(state: .idle).startEnabled)
        XCTAssertFalse(makePresentation(state: .idle, startBlockedReason: "pick one").startEnabled)
        XCTAssertFalse(makePresentation(state: .starting).startEnabled)
        XCTAssertFalse(makePresentation(state: .stopping).startEnabled)
        XCTAssertFalse(
            makePresentation(state: .starting, startBlockedReason: "pick one").startEnabled
        )
        XCTAssertTrue(makePresentation(state: .running).startEnabled)
    }

    func testRestartDisabledWhenBlocked() {
        XCTAssertFalse(makePresentation(state: .running).restartDisabled)
        XCTAssertTrue(
            makePresentation(state: .running, startBlockedReason: "pick one").restartDisabled
        )
        XCTAssertTrue(makePresentation(state: .running, isApplyingSettings: true).restartDisabled)
        XCTAssertTrue(makePresentation(state: .starting).restartDisabled)
    }

    func testStopAndQuitDisabled() {
        XCTAssertFalse(makePresentation(state: .running).stopDisabled)
        XCTAssertTrue(makePresentation(state: .running, isApplyingSettings: true).stopDisabled)
        XCTAssertTrue(makePresentation(state: .starting).stopDisabled)
        XCTAssertFalse(makePresentation(state: .running).quitDisabled)
        XCTAssertTrue(makePresentation(state: .starting).quitDisabled)
        XCTAssertTrue(makePresentation(state: .stopping).quitDisabled)
    }

    func testBlockedReasonTextOnlyWhenStartVisibleAndNotApplying() {
        XCTAssertEqual(
            makePresentation(state: .idle, startBlockedReason: "pick one").visibleStartBlockedReason,
            "pick one"
        )
        XCTAssertEqual(
            makePresentation(state: .error("x"), startBlockedReason: "pick one")
                .visibleStartBlockedReason,
            "pick one"
        )
        XCTAssertNil(
            makePresentation(state: .running, startBlockedReason: "pick one")
                .visibleStartBlockedReason
        )
        XCTAssertNil(
            makePresentation(
                state: .idle, isApplyingSettings: true, startBlockedReason: "pick one"
            ).visibleStartBlockedReason
        )
        XCTAssertNil(makePresentation(state: .idle).visibleStartBlockedReason)
    }

    func testIsRunningAndIsTransitioningMirrorManager() {
        XCTAssertTrue(makePresentation(state: .running).isRunning)
        XCTAssertFalse(makePresentation(state: .reconnecting).isRunning)
        XCTAssertFalse(makePresentation(state: .idle).isRunning)
        XCTAssertTrue(makePresentation(state: .starting).isTransitioning)
        XCTAssertTrue(makePresentation(state: .stopping).isTransitioning)
        XCTAssertFalse(makePresentation(state: .running).isTransitioning)
        XCTAssertFalse(makePresentation(state: .reconnecting).isTransitioning)
    }
}

final class MenuPresentationStatusTests: XCTestCase {
    func testStatusTextApplyingTakesPrecedence() {
        XCTAssertEqual(
            makePresentation(state: .running, isApplyingSettings: true).statusText,
            AppStrings.applyingSettings
        )
        XCTAssertEqual(
            makePresentation(state: .idle, isApplyingSettings: true).statusText,
            AppStrings.applyingSettings
        )
    }

    func testStatusTextReconnectingUsesBannerWhenPresent() {
        XCTAssertEqual(
            makePresentation(state: .reconnecting, bannerMessage: "attempt 1").statusText,
            "attempt 1"
        )
        XCTAssertEqual(
            makePresentation(state: .reconnecting).statusText,
            AppStrings.reconnecting
        )
    }

    func testStatusTextRunningUsesConnectionPhaseLabel() {
        for phase in [BridgeConnectionPhase.waitingForDAW, .connected, .running, .stopped] {
            XCTAssertEqual(
                makePresentation(state: .running, connectionPhase: phase).statusText,
                phase.label,
                "phase=\(phase)"
            )
        }
    }

    func testStatusTextIdleStartingStopping() {
        XCTAssertEqual(makePresentation(state: .idle).statusText, AppStrings.stopped)
        XCTAssertEqual(makePresentation(state: .starting).statusText, AppStrings.starting)
        XCTAssertEqual(makePresentation(state: .stopping).statusText, AppStrings.stopping)
    }

    func testStatusTextErrorUsesHeadline() {
        let message = "helper exited with status 1: could not open output device endpoint unavailable"
        XCTAssertEqual(
            makePresentation(state: .error(message)).statusText,
            BridgeErrorPresentation.headline(for: message)
        )
        XCTAssertEqual(
            makePresentation(state: .error(message)).statusText,
            AppStrings.couldNotStart
        )
    }

    func testStatusToneRunning() {
        XCTAssertEqual(
            makePresentation(state: .running, connectionPhase: .connected).statusTone,
            .green
        )
        XCTAssertEqual(
            makePresentation(
                state: .running, connectionPhase: .connected, metricsStale: true
            ).statusTone,
            .orange
        )
        XCTAssertEqual(
            makePresentation(state: .running, connectionPhase: .waitingForDAW).statusTone,
            .orange
        )
    }

    func testStatusToneOtherStates() {
        XCTAssertEqual(makePresentation(state: .error("x")).statusTone, .red)
        XCTAssertEqual(
            makePresentation(state: .idle, isApplyingSettings: true).statusTone, .orange
        )
        XCTAssertEqual(makePresentation(state: .reconnecting).statusTone, .orange)
        XCTAssertEqual(makePresentation(state: .starting).statusTone, .orange)
        XCTAssertEqual(makePresentation(state: .idle).statusTone, .secondary)
        XCTAssertEqual(makePresentation(state: .stopping).statusTone, .secondary)
    }

    func testStatusSymbol() {
        XCTAssertEqual(
            makePresentation(state: .idle, isApplyingSettings: true).statusSymbol,
            "arrow.triangle.2.circlepath"
        )
        XCTAssertEqual(
            makePresentation(state: .error("x")).statusSymbol,
            "exclamationmark.triangle.fill"
        )
        XCTAssertEqual(
            makePresentation(state: .reconnecting).statusSymbol,
            "arrow.triangle.2.circlepath"
        )
        XCTAssertEqual(makePresentation(state: .running).statusSymbol, "waveform")
        XCTAssertEqual(makePresentation(state: .idle).statusSymbol, "headphones")
        XCTAssertEqual(makePresentation(state: .starting).statusSymbol, "headphones")
        XCTAssertEqual(makePresentation(state: .stopping).statusSymbol, "headphones")
    }

    func testVisibleBannerSuppressedOnlyForErrorDiagnosticDuplicate() {
        let diagnostic = AppStrings.bridgeCouldNotStart(detail: "boom")
        XCTAssertNotNil(
            BridgeErrorPresentation.presentation(for: diagnostic).diagnostic,
            "test message must carry a diagnostic"
        )
        XCTAssertNil(
            makePresentation(state: .error(diagnostic), bannerMessage: diagnostic).visibleBanner
        )
        XCTAssertEqual(
            makePresentation(
                state: .error(diagnostic), bannerMessage: "something else"
            ).visibleBanner,
            "something else"
        )
        XCTAssertEqual(
            makePresentation(
                state: .error(AppStrings.bridgeNotFound),
                bannerMessage: AppStrings.bridgeNotFound
            ).visibleBanner,
            AppStrings.bridgeNotFound
        )
        XCTAssertEqual(
            makePresentation(state: .running, bannerMessage: "attempt 1").visibleBanner,
            "attempt 1"
        )
        XCTAssertNil(makePresentation(state: .running).visibleBanner)
    }

    func testShowsStatusDetail() {
        XCTAssertFalse(makePresentation(state: .idle).showsStatusDetail)
        XCTAssertTrue(
            makePresentation(state: .running, latestMetrics: makeMetrics()).showsStatusDetail
        )
        let diagnostic = AppStrings.bridgeCouldNotStart(detail: "boom")
        XCTAssertTrue(makePresentation(state: .error(diagnostic)).showsStatusDetail)
        XCTAssertFalse(
            makePresentation(state: .error(AppStrings.bridgeNotFound)).showsStatusDetail
        )
    }
}

final class MenuPresentationMetricsTests: XCTestCase {
    func testHeldMetricsWhileApplying() {
        let held = makeMetrics(fillMs: 9)
        let presentation = makePresentation(
            state: .reconnecting,
            isApplyingSettings: true,
            latestMetrics: nil,
            heldMetrics: held
        )
        XCTAssertEqual(presentation.effectiveDetailMetrics, held)
        XCTAssertTrue(presentation.showsHeldMetrics)
    }

    func testIdleClearsDetailMetrics() {
        let held = makeMetrics()
        let latest = makeMetrics(fillMs: 12)
        XCTAssertNil(
            makePresentation(state: .idle, latestMetrics: latest, heldMetrics: held)
                .effectiveDetailMetrics
        )
        XCTAssertFalse(
            makePresentation(state: .idle, latestMetrics: latest, heldMetrics: held)
                .showsHeldMetrics
        )
    }

    func testRunningPrefersLatestOverHeld() {
        let held = makeMetrics(fillMs: 9)
        let latest = makeMetrics(fillMs: 12)
        let presentation = makePresentation(
            state: .running,
            connectionPhase: .running,
            latestMetrics: latest,
            heldMetrics: held
        )
        XCTAssertEqual(presentation.effectiveDetailMetrics, latest)
        XCTAssertFalse(presentation.showsHeldMetrics)
    }

    func testShouldClearHeldMetrics() {
        XCTAssertTrue(makePresentation(state: .idle).shouldClearHeldMetrics)
        XCTAssertTrue(makePresentation(state: .error("x")).shouldClearHeldMetrics)
        XCTAssertFalse(makePresentation(state: .running).shouldClearHeldMetrics)
        XCTAssertFalse(makePresentation(state: .reconnecting).shouldClearHeldMetrics)
        XCTAssertFalse(
            makePresentation(state: .idle, isApplyingSettings: true).shouldClearHeldMetrics
        )
        XCTAssertFalse(
            makePresentation(state: .error("x"), isApplyingSettings: true)
                .shouldClearHeldMetrics
        )
    }
}

final class MenuUpdateSectionTests: XCTestCase {
    func testIdleIsHidden() {
        XCTAssertEqual(
            MenuPresentation.updateSection(for: .idle, lastOfferedVersion: nil),
            .hidden
        )
    }

    func testCheckingIsStatus() {
        XCTAssertEqual(
            MenuPresentation.updateSection(for: .checking, lastOfferedVersion: nil),
            .status(
                message: AppStrings.checkingUpdates,
                systemImage: "arrow.triangle.2.circlepath",
                tone: .secondary
            )
        )
    }

    func testAvailableIsCheckActionWithoutIdentifier() {
        XCTAssertEqual(
            MenuPresentation.updateSection(
                for: .available(version: "1.2.3"), lastOfferedVersion: nil
            ),
            .action(
                title: AppStrings.updateAvailable("1.2.3"),
                kind: .checkForUpdates,
                accessibilityIdentifier: nil
            )
        )
    }

    func testReadyToInstallIsShowActionWithIdentifier() {
        XCTAssertEqual(
            MenuPresentation.updateSection(
                for: .readyToInstall(version: "1.2.3"), lastOfferedVersion: nil
            ),
            .action(
                title: AppStrings.installUpdateAndRelaunch("1.2.3"),
                kind: .showPendingUpdate,
                accessibilityIdentifier: "install-update"
            )
        )
    }

    func testInstallingIsStatus() {
        XCTAssertEqual(
            MenuPresentation.updateSection(
                for: .installing(version: "1.2.3"), lastOfferedVersion: nil
            ),
            .status(
                message: AppStrings.installingUpdate("1.2.3"),
                systemImage: "gearshape",
                tone: .accent
            )
        )
    }

    func testCancelledIsStatus() {
        XCTAssertEqual(
            MenuPresentation.updateSection(for: .cancelled, lastOfferedVersion: nil),
            .status(
                message: AppStrings.updateCancelled,
                systemImage: "xmark.circle",
                tone: .secondary
            )
        )
    }

    func testFailedWithoutOfferedVersion() {
        XCTAssertEqual(
            MenuPresentation.updateSection(
                for: .failed(message: "nope"), lastOfferedVersion: nil
            ),
            .failed(message: "nope", retryVersionText: nil)
        )
    }

    func testFailedWithOfferedVersion() {
        XCTAssertEqual(
            MenuPresentation.updateSection(
                for: .failed(message: "nope"), lastOfferedVersion: "1.2.3"
            ),
            .failed(
                message: "nope",
                retryVersionText: AppStrings.updateAvailable("1.2.3")
            )
        )
    }
}
