import AppKit

@MainActor
final class StatusItemController {
    var onOpen: (() -> Void)?
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init() {
        item.button?.image = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "sui")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open sui", action: #selector(open), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit sui", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.first?.target = self
        item.menu = menu
    }

    func setState(_ state: PTTCoordinator.State) {
        item.button?.image = NSImage(
            systemSymbolName: state == .idle ? "drop.fill" : "waveform.circle.fill",
            accessibilityDescription: state.label
        )
        item.button?.contentTintColor = state == .idle ? nil : .controlAccentColor
    }

    @objc private func open() { onOpen?() }
}

