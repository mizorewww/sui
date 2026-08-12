import AppKit
import SafariServices

@MainActor
final class SettingsView: NSView {
    var onBack: (() -> Void)?
    var onControllerSelected: ((String?) -> Void)?
    var onPluginToggled: ((PluginID, Bool) -> Void)?
    var onQwenToggled: ((Bool) -> Void)?

    private let controllerPopup = NSPopUpButton()
    private let qwenSwitch = NSSwitch()
    private let pluginStack = NSStackView()
    private let documentView = FlippedView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        documentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        let contentGuide = NSLayoutGuide()
        documentView.addLayoutGuide(contentGuide)

        let back = NSButton(title: "Mapping", target: self, action: #selector(backPressed))
        back.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
        back.bezelStyle = .accessoryBarAction

        let title = NSTextField(labelWithString: "Settings")
        title.font = .systemFont(ofSize: 26, weight: .bold)

        let controllerTitle = sectionTitle("Controller")
        controllerPopup.controlSize = .large
        controllerPopup.target = self
        controllerPopup.action = #selector(controllerChanged)

        let speechTitle = sectionTitle("Speech recognition")
        let speechRow = qwenRow()

        let pluginsTitle = sectionTitle("Plugins")
        pluginStack.orientation = .vertical
        pluginStack.spacing = 1
        pluginStack.alignment = .width
        pluginStack.wantsLayer = true
        pluginStack.layer?.cornerRadius = 12
        pluginStack.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.62).cgColor

        for view in [back, title, controllerTitle, controllerPopup, speechTitle, speechRow, pluginsTitle, pluginStack] {
            view.translatesAutoresizingMaskIntoConstraints = false
            documentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),

            contentGuide.centerXAnchor.constraint(equalTo: documentView.centerXAnchor),
            contentGuide.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
            contentGuide.leadingAnchor.constraint(greaterThanOrEqualTo: documentView.leadingAnchor, constant: 38),
            contentGuide.trailingAnchor.constraint(lessThanOrEqualTo: documentView.trailingAnchor, constant: -38),
            contentGuide.widthAnchor.constraint(equalTo: documentView.widthAnchor, constant: -76).withPriority(.defaultHigh),

            back.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            back.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 4),
            title.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            title.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 18),

            controllerTitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            controllerTitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 24),
            controllerPopup.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            controllerPopup.topAnchor.constraint(equalTo: controllerTitle.bottomAnchor, constant: 8),
            controllerPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            controllerPopup.widthAnchor.constraint(lessThanOrEqualToConstant: 420),

            speechTitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            speechTitle.topAnchor.constraint(equalTo: controllerPopup.bottomAnchor, constant: 24),
            speechRow.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            speechRow.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor),
            speechRow.topAnchor.constraint(equalTo: speechTitle.bottomAnchor, constant: 8),

            pluginsTitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            pluginsTitle.topAnchor.constraint(equalTo: speechRow.bottomAnchor, constant: 24),
            pluginStack.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            pluginStack.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor),
            pluginStack.topAnchor.constraint(equalTo: pluginsTitle.bottomAnchor, constant: 8),
            pluginStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -18)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(
        devices: [ControllerService.Device],
        selectedKey: String?,
        pluginHost: PluginHost,
        qwenEnabled: Bool
    ) {
        controllerPopup.removeAllItems()
        if devices.isEmpty {
            controllerPopup.addItem(withTitle: "No controller connected")
            controllerPopup.isEnabled = false
        } else {
            controllerPopup.isEnabled = true
            for device in devices {
                controllerPopup.addItem(withTitle: device.name)
                controllerPopup.lastItem?.representedObject = device.key
            }
            if let item = controllerPopup.itemArray.first(where: { ($0.representedObject as? String) == selectedKey }) {
                controllerPopup.select(item)
            }
        }
        qwenSwitch.state = qwenEnabled ? .on : .off

        pluginStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for descriptor in PluginHost.descriptors {
            pluginStack.addArrangedSubview(pluginRow(descriptor: descriptor, enabled: pluginHost.isEnabled(descriptor.id)))
        }
        pluginStack.addArrangedSubview(safariExtensionRow())
    }

    private func qwenRow() -> NSView {
        let row = cardRow()
        let icon = NSImageView(image: NSImage(systemSymbolName: "waveform.badge.magnifyingglass", accessibilityDescription: "Qwen3 ASR")!)
        icon.contentTintColor = .controlAccentColor
        let name = NSTextField(labelWithString: "Qwen3-ASR 0.6B")
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        let detail = NSTextField(labelWithString: "MLX 4-bit · 本地识别 · 约 700 MB")
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        qwenSwitch.target = self
        qwenSwitch.action = #selector(qwenToggled)
        layoutRow(row, icon: icon, name: name, detail: detail, trailing: qwenSwitch)
        return row
    }

    private func safariExtensionRow() -> NSView {
        let row = NSView()
        row.heightAnchor.constraint(equalToConstant: 58).isActive = true
        let icon = NSImageView(image: NSImage(systemSymbolName: "safari", accessibilityDescription: "Safari")!)
        icon.contentTintColor = .controlAccentColor
        let name = NSTextField(labelWithString: "Safari Extension")
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        let detail = NSTextField(labelWithString: "X.com browser bridge")
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        let button = NSButton(title: "Open Settings", target: self, action: #selector(openSafariSettings))
        button.bezelStyle = .rounded
        layoutRow(row, icon: icon, name: name, detail: detail, trailing: button)
        return row
    }

    private func pluginRow(descriptor: PluginDescriptor, enabled: Bool) -> NSView {
        let row = NSView()
        row.heightAnchor.constraint(equalToConstant: 58).isActive = true
        let icon = NSImageView(image: NSImage(systemSymbolName: descriptor.symbolName, accessibilityDescription: descriptor.name)!)
        icon.contentTintColor = .controlAccentColor
        let name = NSTextField(labelWithString: descriptor.name)
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        let detail = NSTextField(labelWithString: descriptor.detail)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        let toggle = NSSwitch()
        toggle.state = enabled ? .on : .off
        toggle.identifier = NSUserInterfaceItemIdentifier(descriptor.id.rawValue)
        toggle.target = self
        toggle.action = #selector(pluginToggled(_:))
        layoutRow(row, icon: icon, name: name, detail: detail, trailing: toggle)
        return row
    }

    private func cardRow() -> NSView {
        let row = NSView()
        row.wantsLayer = true
        row.layer?.cornerRadius = 12
        row.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.62).cgColor
        row.heightAnchor.constraint(equalToConstant: 62).isActive = true
        return row
    }

    private func layoutRow(_ row: NSView, icon: NSImageView, name: NSTextField, detail: NSTextField, trailing: NSView) {
        for view in [icon, name, detail, trailing] { view.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(view) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16), icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24), icon.heightAnchor.constraint(equalToConstant: 24),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12), name.topAnchor.constraint(equalTo: row.topAnchor, constant: 11),
            detail.leadingAnchor.constraint(equalTo: name.leadingAnchor), detail.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 2),
            trailing.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16), trailing.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
    }

    private func sectionTitle(_ string: String) -> NSTextField {
        let label = NSTextField(labelWithString: string.uppercased())
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    @objc private func backPressed() { onBack?() }
    @objc private func controllerChanged() { onControllerSelected?(controllerPopup.selectedItem?.representedObject as? String) }
    @objc private func qwenToggled() { onQwenToggled?(qwenSwitch.state == .on) }
    @objc private func pluginToggled(_ sender: NSSwitch) {
        guard let raw = sender.identifier?.rawValue, let id = PluginID(rawValue: raw) else { return }
        onPluginToggled?(id, sender.state == .on)
    }
    @objc private func openSafariSettings() {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: "com.mizore.sui.SafariExtension") { _ in }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: Priority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
