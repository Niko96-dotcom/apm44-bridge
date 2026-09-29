import SwiftUI

struct MenuStatusHero: View {
    let presentation: MenuPresentation

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusTint.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: presentation.statusSymbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(statusTint)
            }
            .accessibilityHidden(true)

            Text(presentation.statusText)
                .font(.headline)

            Spacer(minLength: 8)

            if let metrics = presentation.effectiveDetailMetrics {
                MenuLatencyBadge(metrics: metrics, tint: statusTint)
                    .opacity(presentation.showsHeldMetrics ? 0.5 : 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppStrings.bridgeStatus)
        .accessibilityValue(presentation.statusText)
    }

    private var statusTint: Color {
        menuStatusTint(for: presentation.statusTone)
    }
}

struct MenuLatencyBadge: View {
    let metrics: BridgeMetricsSnapshot
    let tint: Color

    var body: some View {
        Text(AppStrings.latencyBadge(Int(max(1, metrics.estimatedRtMs.rounded()))))
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint)
            .accessibilityLabel(metrics.bridgeBufferingLabel)
    }
}

struct MenuStatusDetail: View {
    @ObservedObject var manager: BridgeProcessManager
    let presentation: MenuPresentation
    @Binding var showMonitoringDetails: Bool
    @Binding var showErrorDetails: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let metrics = presentation.effectiveDetailMetrics {
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
                .opacity(presentation.showsHeldMetrics ? 0.5 : 1)
            } else if case .error(let error) = manager.state,
                      MenuPresentation.errorHasContent(error) {
                errorDetailView(error: error)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: errorIdentity) { _, _ in
            showErrorDetails = false
        }
    }

    private var errorIdentity: BridgeError? {
        if case .error(let error) = manager.state { return error }
        return nil
    }

    @ViewBuilder
    private func errorDetailView(error: BridgeError) -> some View {
        let presentation = BridgeErrorPresentation.presentation(for: error)
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
}

struct MenuBanner: View {
    let message: String
    @ObservedObject var manager: BridgeProcessManager

    var body: some View {
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
    }
}

fileprivate func menuStatusTint(for tone: MenuStatusTone) -> Color {
    switch tone {
    case .secondary: return .secondary
    case .orange: return .orange
    case .green: return .green
    case .red: return .red
    }
}
