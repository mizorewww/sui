import AppKit

@MainActor
final class MappingView: NSView {
    var onMappingChanged: ((String, PluginID) -> Void)?

    private let controllerImage = NSImageView()
    private let connectionLabel = NSTextField(labelWithString: "Connect a controller")
    private let instructionLabel = NSTextField(labelWithString: "Hold a mapped button to talk")
    private let railTitle = NSTextField(labelWithString: "BUTTON MAPPINGS")
    private let railDetail = NSTextField(labelWithString: "Choose where each recording goes")
    private let overlay = MappingOverlayView()
    private var popups: [String: NSPopUpButton] = [:]
    private var mappings: [String: PluginID] = ["A": .telegram, "B": .x, "Y": .codex]
    private var availability: [PluginID: PluginAvailability] = [:]
    private var stageRect = CGRect.zero
    private var railRect = CGRect.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        controllerImage.imageScaling = .scaleProportionallyUpOrDown
        controllerImage.setAccessibilityLabel("Game controller")
        if let url = Bundle.main.url(forResource: "controller", withExtension: "pdf") {
            controllerImage.image = NSImage(contentsOf: url)
        }
        addSubview(controllerImage)

        connectionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        connectionLabel.textColor = .labelColor
        instructionLabel.font = .systemFont(ofSize: 11)
        instructionLabel.textColor = .secondaryLabelColor
        railTitle.font = .systemFont(ofSize: 11, weight: .semibold)
        railTitle.textColor = .secondaryLabelColor
        railDetail.font = .systemFont(ofSize: 11)
        railDetail.textColor = .tertiaryLabelColor
        for label in [connectionLabel, instructionLabel, railTitle, railDetail] { addSubview(label) }

        for button in ["Y", "B", "A"] {
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.controlSize = .large
            popup.font = .systemFont(ofSize: 13, weight: .medium)
            popup.target = self
            popup.action = #selector(mappingChanged(_:))
            popup.identifier = NSUserInterfaceItemIdentifier(button)
            popup.setAccessibilityLabel("\(button) button destination")
            popups[button] = popup
            addSubview(popup)
        }
        overlay.mappingView = self
        addSubview(overlay)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(mappings: [String: PluginID], availability: [PluginID: PluginAvailability], hasController: Bool) {
        self.mappings = mappings
        self.availability = availability
        connectionLabel.stringValue = hasController ? "Controller connected" : "Connect a controller"
        connectionLabel.textColor = hasController ? .systemGreen : .labelColor
        instructionLabel.stringValue = hasController ? "Hold a mapped button to talk" : "sui will listen as soon as one appears"
        for (button, popup) in popups {
            popup.removeAllItems()
            let none = NSMenuItem(title: "None", action: nil, keyEquivalent: "")
            none.representedObject = PluginID.none.rawValue
            popup.menu?.addItem(none)
            popup.menu?.addItem(.separator())
            for descriptor in PluginHost.descriptors {
                let state = availability[descriptor.id] ?? .unavailable("Unavailable")
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
        overlay.needsDisplay = true
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = bounds.width < 800 ? 18 : 24
        let gap: CGFloat = bounds.width < 800 ? 14 : 20
        let railWidth = min(292, max(224, bounds.width * 0.31))
        railRect = CGRect(x: bounds.maxX - inset - railWidth, y: inset, width: railWidth, height: bounds.height - inset * 2)
        stageRect = CGRect(x: inset, y: inset, width: railRect.minX - gap - inset, height: railRect.height)

        let stageHeaderHeight: CGFloat = 58
        let footerHeight: CGFloat = 56
        let imageArea = stageRect.insetBy(dx: max(16, stageRect.width * 0.05), dy: 0)
        controllerImage.frame = CGRect(
            x: imageArea.minX,
            y: stageRect.minY + footerHeight,
            width: imageArea.width,
            height: max(180, stageRect.height - footerHeight - stageHeaderHeight)
        )
        connectionLabel.frame = CGRect(x: stageRect.minX + 20, y: stageRect.minY + 28, width: stageRect.width - 40, height: 18)
        instructionLabel.frame = CGRect(x: stageRect.minX + 20, y: stageRect.minY + 12, width: stageRect.width - 40, height: 16)

        railTitle.frame = CGRect(x: railRect.minX + 18, y: railRect.maxY - 34, width: railRect.width - 36, height: 16)
        railDetail.frame = CGRect(x: railRect.minX + 18, y: railRect.maxY - 52, width: railRect.width - 36, height: 16)
        let popupX = railRect.minX + 18
        let popupWidth = railRect.width - 36
        let centerY = railRect.midY - 4
        popups["Y"]?.frame = CGRect(x: popupX, y: centerY + 64, width: popupWidth, height: 40)
        popups["B"]?.frame = CGRect(x: popupX, y: centerY - 8, width: popupWidth, height: 40)
        popups["A"]?.frame = CGRect(x: popupX, y: centerY - 80, width: popupWidth, height: 40)
        overlay.frame = bounds
        needsDisplay = true
        overlay.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawPanel(stageRect, fill: .controlBackgroundColor)
        drawPanel(railRect, fill: NSColor.windowBackgroundColor.withAlphaComponent(0.72))
        let divider = NSBezierPath()
        divider.move(to: NSPoint(x: railRect.minX + 18, y: railRect.maxY - 64))
        divider.line(to: NSPoint(x: railRect.maxX - 18, y: railRect.maxY - 64))
        NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
        divider.lineWidth = 1
        divider.stroke()
    }

    private func drawPanel(_ rect: CGRect, fill: NSColor) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        fill.withAlphaComponent(0.64).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.32).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    fileprivate func drawOverlay() {
        let labels: [(String, NSPoint)] = [
            ("Y", imagePoint(x: 0.7481, y: 0.7778)),
            ("B", imagePoint(x: 0.8111, y: 0.6833)),
            ("A", imagePoint(x: 0.7463, y: 0.5833))
        ]
        let accent = NSColor.controlAccentColor
        for (name, start) in labels {
            guard let popup = popups[name] else { continue }
            let end = NSPoint(x: popup.frame.minX - 8, y: popup.frame.midY)
            let path = NSBezierPath()
            path.move(to: start)
            path.curve(to: end,
                       controlPoint1: NSPoint(x: start.x + min(66, (end.x - start.x) * 0.45), y: start.y),
                       controlPoint2: NSPoint(x: end.x - 40, y: end.y))
            path.lineWidth = 1.5
            accent.withAlphaComponent(0.48).setStroke()
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

    private func imagePoint(x: CGFloat, y: CGFloat) -> NSPoint {
        guard let image = controllerImage.image, image.size.width > 0, image.size.height > 0 else { return .zero }
        let frame = controllerImage.frame
        let scale = min(frame.width / image.size.width, frame.height / image.size.height)
        let renderedSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderedRect = CGRect(x: frame.midX - renderedSize.width / 2, y: frame.midY - renderedSize.height / 2,
                                  width: renderedSize.width, height: renderedSize.height)
        return NSPoint(x: renderedRect.minX + renderedRect.width * x, y: renderedRect.minY + renderedRect.height * y)
    }

    @objc private func mappingChanged(_ sender: NSPopUpButton) {
        guard let button = sender.identifier?.rawValue,
              let rawValue = sender.selectedItem?.representedObject as? String,
              let pluginID = PluginID(rawValue: rawValue) else { return }
        mappings[button] = pluginID
        onMappingChanged?(button, pluginID)
    }
}

@MainActor
private final class MappingOverlayView: NSView {
    weak var mappingView: MappingView?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        mappingView?.drawOverlay()
    }
}
