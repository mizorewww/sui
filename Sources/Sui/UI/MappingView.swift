import AppKit

@MainActor
final class MappingView: NSView {
    var onMappingChanged: ((String, PluginID) -> Void)?

    private let controllerImage = NSImageView()
    private let emptyState = NSTextField(labelWithString: "Connect a controller to start")
    private var popups: [String: NSPopUpButton] = [:]
    private var mappings: [String: PluginID] = ["A": .telegram, "B": .x, "Y": .codex]
    private var availability: [PluginID: PluginAvailability] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        controllerImage.imageScaling = .scaleProportionallyUpOrDown
        controllerImage.contentTintColor = .labelColor
        if let url = Bundle.main.url(forResource: "controller", withExtension: "svg") {
            controllerImage.image = NSImage(contentsOf: url)
        }
        addSubview(controllerImage)

        emptyState.font = .systemFont(ofSize: 12, weight: .medium)
        emptyState.textColor = .secondaryLabelColor
        emptyState.alignment = .center
        addSubview(emptyState)

        for button in ["Y", "B", "A"] {
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.controlSize = .large
            popup.font = .systemFont(ofSize: 13, weight: .medium)
            popup.target = self
            popup.action = #selector(mappingChanged(_:))
            popup.identifier = NSUserInterfaceItemIdentifier(button)
            popups[button] = popup
            addSubview(popup)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(mappings: [String: PluginID], availability: [PluginID: PluginAvailability], hasController: Bool) {
        self.mappings = mappings
        self.availability = availability
        emptyState.stringValue = hasController ? "Controller connected · hold a mapped button to talk" : "Connect a controller to start"
        for (button, popup) in popups {
            popup.removeAllItems()
            let none = NSMenuItem(title: "None", action: nil, keyEquivalent: "")
            none.representedObject = PluginID.none.rawValue
            popup.menu?.addItem(none)
            popup.menu?.addItem(.separator())
            for descriptor in PluginHost.descriptors {
                let state = availability[descriptor.id] ?? .unavailable("不可用")
                let item = NSMenuItem(title: descriptor.name, action: nil, keyEquivalent: "")
                item.image = NSImage(systemSymbolName: descriptor.symbolName, accessibilityDescription: nil)
                item.representedObject = descriptor.id.rawValue
                item.isEnabled = state.isAvailable
                if !state.isAvailable { item.title += "  — unavailable" }
                popup.menu?.addItem(item)
            }
            if let selected = popup.itemArray.first(where: { ($0.representedObject as? String) == mappings[button]?.rawValue }) {
                popup.select(selected)
            }
        }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let imageSize = CGSize(width: min(410, bounds.width * 0.51), height: min(330, bounds.height * 0.68))
        controllerImage.frame = CGRect(x: 46, y: 78, width: imageSize.width, height: imageSize.height)
        emptyState.frame = CGRect(x: 38, y: 34, width: imageSize.width + 16, height: 22)
        let popupX = max(520, bounds.width * 0.64)
        let popupWidth = max(220, bounds.width - popupX - 42)
        let centerY = controllerImage.frame.midY
        popups["Y"]?.frame = CGRect(x: popupX, y: centerY + 82, width: popupWidth, height: 34)
        popups["B"]?.frame = CGRect(x: popupX, y: centerY + 12, width: popupWidth, height: 34)
        popups["A"]?.frame = CGRect(x: popupX, y: centerY - 58, width: popupWidth, height: 34)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let labels: [(String, NSPoint)] = [
            ("Y", NSPoint(x: controllerImage.frame.maxX - 86, y: controllerImage.frame.midY + 78)),
            ("B", NSPoint(x: controllerImage.frame.maxX - 55, y: controllerImage.frame.midY + 18)),
            ("A", NSPoint(x: controllerImage.frame.maxX - 92, y: controllerImage.frame.midY - 45))
        ]
        let accent = NSColor.controlAccentColor
        for (name, start) in labels {
            guard let popup = popups[name] else { continue }
            let end = NSPoint(x: popup.frame.minX - 12, y: popup.frame.midY)
            let path = NSBezierPath()
            path.move(to: start)
            path.curve(to: end, controlPoint1: NSPoint(x: start.x + 72, y: start.y), controlPoint2: NSPoint(x: end.x - 72, y: end.y))
            path.lineWidth = 1.5
            accent.withAlphaComponent(0.42).setStroke()
            path.stroke()

            let circle = NSBezierPath(ovalIn: CGRect(x: start.x - 13, y: start.y - 13, width: 26, height: 26))
            accent.setFill()
            circle.fill()
            let text = NSAttributedString(string: name, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: NSColor.white
            ])
            let size = text.size()
            text.draw(at: NSPoint(x: start.x - size.width / 2, y: start.y - size.height / 2))
        }
    }

    @objc private func mappingChanged(_ sender: NSPopUpButton) {
        guard let button = sender.identifier?.rawValue,
              let rawValue = sender.selectedItem?.representedObject as? String,
              let pluginID = PluginID(rawValue: rawValue) else { return }
        mappings[button] = pluginID
        onMappingChanged?(button, pluginID)
    }
}

