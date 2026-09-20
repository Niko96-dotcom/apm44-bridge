import AppKit
import SwiftUI

/// A native pop-up button that actually fills its row.
///
/// SwiftUI positions AppKit-backed Pickers at fitting size inside larger
/// frames, so equal full-width rows are impossible with Picker modifiers
/// alone. This wrapper pushes the row width into the control itself via
/// `intrinsicContentSize` and keeps the native bezel, checkmarks, disabled
/// items, type-select and accessibility for free.
struct FullWidthPopUpButton: NSViewRepresentable {
    struct Option: Identifiable, Equatable {
        let id: String
        let title: String
        let isEnabled: Bool
    }

    var width: CGFloat
    var options: [Option]
    var selectedId: String
    var accessibilityLabelText: String
    var onSelect: (String) -> Void

    func makeNSView(context: Context) -> FixedWidthPopUpButton {
        let popUp = FixedWidthPopUpButton(frame: .zero, pullsDown: false)
        popUp.target = context.coordinator
        popUp.action = #selector(Coordinator.chose(_:))
        return popUp
    }

    func updateNSView(_ popUp: FixedWidthPopUpButton, context: Context) {
        context.coordinator.onSelect = onSelect
        apply(to: popUp)
    }

    func apply(to popUp: FixedWidthPopUpButton) {
        if popUp.fixedWidth != width {
            popUp.fixedWidth = width
            popUp.invalidateIntrinsicContentSize()
        }
        popUp.setAccessibilityLabel(accessibilityLabelText)
        let ids = options.map(\.id)
        let existing = popUp.itemArray.compactMap { $0.representedObject as? String }
        if existing != ids {
            popUp.removeAllItems()
            for option in options {
                popUp.addItem(withTitle: option.title)
                popUp.lastItem?.representedObject = option.id
            }
        }
        var selectedTitleChanged = false
        for (index, option) in options.enumerated() where index < popUp.numberOfItems {
            popUp.item(at: index)?.isEnabled = option.isEnabled
            if popUp.item(at: index)?.title != option.title {
                if (popUp.item(at: index)?.representedObject as? String) == selectedId {
                    selectedTitleChanged = true
                }
                popUp.item(at: index)?.title = option.title
            }
        }
        // Same-id pickerLabel/compatibility updates mutate the item in place.
        // NSPopUpButton keeps a stale bezel title unless select runs again.
        if let item = popUp.itemArray.first(where: { ($0.representedObject as? String) == selectedId }),
           popUp.selectedItem != item || selectedTitleChanged || popUp.title != item.title {
            popUp.select(item)
        }
    }

    static func dismantleNSView(_ popUp: FixedWidthPopUpButton, coordinator: Coordinator) {
        popUp.target = nil
        popUp.action = nil
        coordinator.onSelect = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        var onSelect: ((String) -> Void)?
        @objc func chose(_ sender: NSPopUpButton) {
            guard let id = sender.selectedItem?.representedObject as? String else { return }
            onSelect?(id)
        }
    }
}

final class FixedWidthPopUpButton: NSPopUpButton {
    var fixedWidth: CGFloat = 0
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        if fixedWidth > 0 { size.width = fixedWidth }
        return size
    }
}
