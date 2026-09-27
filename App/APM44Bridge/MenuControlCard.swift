import SwiftUI

struct MenuControlCard: View {
    @ObservedObject var manager: BridgeProcessManager
    @ObservedObject var settings: BridgeSettings
    let controlRowWidth: CGFloat
    let cardPadding: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MenuOutputControl(manager: manager, settings: settings, controlRowWidth: controlRowWidth)
            MenuLatencyControl(manager: manager, settings: settings, controlRowWidth: controlRowWidth)
            MenuQualityControl(manager: manager, settings: settings, controlRowWidth: controlRowWidth)
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
}

struct MenuControlHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
                .font(.subheadline.weight(.medium))
        }
    }
}

struct MenuOutputControl: View {
    @ObservedObject var manager: BridgeProcessManager
    @ObservedObject var settings: BridgeSettings
    let controlRowWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MenuControlHeader(icon: "hifispeaker.fill", title: AppStrings.output)
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
}

struct MenuLatencyControl: View {
    @ObservedObject var manager: BridgeProcessManager
    @ObservedObject var settings: BridgeSettings
    let controlRowWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MenuControlHeader(icon: "speedometer", title: AppStrings.buffering)
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

    private func selectLatency(_ preset: LatencyPreset) {
        guard settings.latencyPreset != preset else { return }
        settings.latencyPreset = preset
        Task { await manager.restartForSettingsChange() }
    }
}

struct MenuQualityControl: View {
    @ObservedObject var manager: BridgeProcessManager
    @ObservedObject var settings: BridgeSettings
    let controlRowWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MenuControlHeader(icon: "waveform.path", title: AppStrings.quality)
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

    private func selectQuality(_ quality: SrcQuality) {
        guard settings.effectiveSrcQuality != quality else { return }
        settings.srcQualityOverride = quality
        Task { await manager.restartForSettingsChange() }
    }
}
