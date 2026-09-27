import SwiftUI

struct MenuUpdateSectionView: View {
    let updateModel: MenuUpdateSection
    @EnvironmentObject private var updater: SparkleUpdateController

    var body: some View {
        Group {
            switch updateModel {
            case .hidden:
                EmptyView()
            case let .status(message, systemImage, tone):
                updateStatus(message, systemImage: systemImage, tint: updateToneColor(tone))
            case let .action(title, kind, identifier):
                let button = Button {
                    dismissMenuBarPanel()
                    switch kind {
                    case .checkForUpdates: updater.checkForUpdates()
                    case .showPendingUpdate: updater.showPendingUpdate()
                    }
                } label: {
                    Text(title)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityLabel(title)
                if let identifier {
                    button.accessibilityIdentifier(identifier)
                } else {
                    button
                }
            case let .failed(message, retryVersionText):
                VStack(alignment: .leading, spacing: 8) {
                    updateStatus(message, systemImage: "exclamationmark.triangle", tint: .orange)
                    if let retryText = retryVersionText {
                        Text(retryText)
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

    private func updateToneColor(_ tone: MenuUpdateTone) -> Color {
        switch tone {
        case .secondary: return .secondary
        case .accent: return .accentColor
        case .orange: return .orange
        }
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
}
