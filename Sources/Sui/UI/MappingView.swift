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
    private var panelRect = CGRect.zero
    private var stageRect = CGRect.zero
    private var railRect = CGRect.zero
    private let buttonLocations: [String: CGPoint] = [
        "X": CGPoint(x: 0.688148, y: 0.681111),
        "Y": CGPoint(x: 0.751111, y: 0.776111),
        "B": CGPoint(x: 0.814074, y: 0.681111),
        "A": CGPoint(x: 0.751111, y: 0.586667)
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        controllerImage.imageScaling = .scaleProportionallyUpOrDown
        controllerImage.setAccessibilityLabel("Game controller")
        if let url = Bundle.main.url(forResource: "controller", withExtension: "pdf") {
            let image = NSImage(contentsOf: url)
            image?.isTemplate = true
            controllerImage.image = image
            controllerImage.contentTintColor = .labelColor
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
            popup.controlSize = .regular
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
        panelRect = bounds
        let padding: CGFloat = bounds.width < 800 ? 18 : 22
        let gap: CGFloat = bounds.width < 800 ? 18 : 24
        let railWidth = min(276, max(218, bounds.width * 0.30))
        railRect = CGRect(x: bounds.maxX - padding - railWidth, y: padding,
                          width: railWidth, height: bounds.height - padding * 2)
        stageRect = CGRect(x: padding, y: padding,
                           width: railRect.minX - gap - padding, height: railRect.height)

        let footerHeight: CGFloat = 56
        let imageArea = stageRect.insetBy(dx: max(8, stageRect.width * 0.025), dy: 0)
        controllerImage.frame = CGRect(
            x: imageArea.minX,
            y: stageRect.minY + footerHeight,
            width: imageArea.width,
            height: max(180, stageRect.height - footerHeight - 8)
        )
        connectionLabel.frame = CGRect(x: stageRect.minX + 4, y: stageRect.minY + 28, width: stageRect.width - 8, height: 18)
        instructionLabel.frame = CGRect(x: stageRect.minX + 4, y: stageRect.minY + 12, width: stageRect.width - 8, height: 16)

        railTitle.frame = CGRect(x: railRect.minX, y: railRect.maxY - 24, width: railRect.width, height: 16)
        railDetail.frame = CGRect(x: railRect.minX, y: railRect.maxY - 42, width: railRect.width, height: 16)
        let popupX = railRect.minX
        let popupWidth = railRect.width
        let rendered = renderedImageRect()
        let desiredCenter = ["Y", "B", "A"].compactMap { buttonLocations[$0] }
            .map { rendered.minY + rendered.height * $0.y }
            .reduce(0, +) / 3
        let spacing = min(68, max(52, rendered.height * 0.17))
        let centerY = min(railRect.maxY - 74 - spacing, max(railRect.minY + 24 + spacing, desiredCenter))
        for (button, offset) in [("Y", spacing), ("B", 0), ("A", -spacing)] {
            popups[button]?.frame = CGRect(x: popupX, y: centerY + offset - 17,
                                            width: popupWidth, height: 34)
        }
        overlay.frame = bounds
        needsDisplay = true
        overlay.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawPanel(panelRect, fill: .controlBackgroundColor)
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
        let accent = NSColor.controlAccentColor
        let rendered = renderedImageRect()
        let radius = min(24, max(10, rendered.width * 0.032))
        for name in ["X", "Y", "B", "A"] {
            guard let location = buttonLocations[name] else { continue }
            let start = NSPoint(x: rendered.minX + rendered.width * location.x,
                                y: rendered.minY + rendered.height * location.y)
            if let popup = popups[name] {
                let end = NSPoint(x: popup.frame.minX - 10, y: popup.frame.midY)
                let path = NSBezierPath()
                path.move(to: start)
                path.curve(to: end,
                           controlPoint1: NSPoint(x: start.x + min(72, (end.x - start.x) * 0.42), y: start.y),
                           controlPoint2: NSPoint(x: end.x - 34, y: end.y))
                path.lineWidth = max(1.25, rendered.width * 0.0018)
                accent.withAlphaComponent(0.48).setStroke()
                path.stroke()
            }

            let circle = NSBezierPath(ovalIn: CGRect(x: start.x - radius, y: start.y - radius,
                                                      width: radius * 2, height: radius * 2))
            (name == "X" ? NSColor.secondaryLabelColor : accent).setFill()
            circle.fill()
            let text = NSAttributedString(string: name, attributes: [
                .font: NSFont.systemFont(ofSize: min(18, max(10, radius * 0.86)), weight: .bold),
                .foregroundColor: NSColor.white
            ])
            let size = text.size()
            text.draw(at: NSPoint(x: start.x - size.width / 2, y: start.y - size.height / 2))
        }
    }

    private func renderedImageRect() -> CGRect {
        guard let image = controllerImage.image, image.size.width > 0, image.size.height > 0 else { return .zero }
        let frame = controllerImage.frame
        let scale = min(frame.width / image.size.width, frame.height / image.size.height)
        let renderedSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(x: frame.midX - renderedSize.width / 2, y: frame.midY - renderedSize.height / 2,
                      width: renderedSize.width, height: renderedSize.height)
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
