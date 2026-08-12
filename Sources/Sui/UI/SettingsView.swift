import AppKit
import SafariServices

@MainActor
final class SettingsView: NSView {
    var onBack: (() -> Void)?
    var onControllerSelected: ((String?) -> Void)?
    var onPluginToggled: ((PluginID, Bool) -> Void)?

    private let controllerPopup = NSPopUpButton()
    private let pluginStack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let contentGuide = NSLayoutGuide()
        addLayoutGuide(contentGuide)

        let back = NSButton(title: "Mapping", target: self, action: #selector(backPressed))
        back.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
        back.bezelStyle = .accessoryBarAction

        let title = NSTextField(labelWithString: "Settings")
        title.font = .systemFont(ofSize: 26, weight: .bold)

        let controllerTitle = sectionTitle("Controller")
        controllerPopup.controlSize = .large
        controllerPopup.target = self
        controllerPopup.action = #selector(controllerChanged)

        let pluginsTitle = sectionTitle("Plugins")
        pluginStack.orientation = .vertical
        pluginStack.spacing = 1
        pluginStack.alignment = .width
        pluginStack.wantsLayer = true
        pluginStack.layer?.cornerRadius = 12
        pluginStack.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.62).cgColor

        for view in [back, title, controllerTitle, controllerPopup, pluginsTitle, pluginStack] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            contentGuide.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentGuide.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
            contentGuide.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 38),
            contentGuide.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -38),
            contentGuide.widthAnchor.constraint(equalTo: widthAnchor, constant: -76).withPriority(.defaultHigh),
            back.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            back.topAnchor.constraint(equalTo: topAnchor, constant: 26),
            title.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            title.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 26),
            controllerTitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            controllerTitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 32),
            controllerPopup.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            controllerPopup.topAnchor.constraint(equalTo: controllerTitle.bottomAnchor, constant: 10),
            controllerPopup.trailingAnchor.constraint(lessThanOrEqualTo: contentGuide.trailingAnchor),
            controllerPopup.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            controllerPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            pluginsTitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            pluginsTitle.topAnchor.constraint(equalTo: controllerPopup.bottomAnchor, constant: 34),
            pluginStack.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            pluginStack.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor),
            pluginStack.topAnchor.constraint(equalTo: pluginsTitle.bottomAnchor, constant: 10)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(devices: [ControllerService.Device], selectedKey: String?, pluginHost: PluginHost) {
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

        pluginStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for descriptor in PluginHost.descriptors {
            pluginStack.addArrangedSubview(pluginRow(descriptor: descriptor, enabled: pluginHost.isEnabled(descriptor.id)))
        }
        pluginStack.addArrangedSubview(safariExtensionRow())
    }

    private func safariExtensionRow() -> NSView {
        let row = NSView()
        row.heightAnchor.constraint(equalToConstant: 62).isActive = true
        let icon = NSImageView(image: NSImage(systemSymbolName: "safari", accessibilityDescription: "Safari")!)
        icon.contentTintColor = .controlAccentColor
        let name = NSTextField(labelWithString: "Safari Extension")
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        let detail = NSTextField(labelWithString: "X.com browser bridge")
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        let button = NSButton(title: "Open Settings", target: self, action: #selector(openSafariSettings))
        button.bezelStyle = .rounded
        for view in [icon, name, detail, button] { view.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(view) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16), icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24), icon.heightAnchor.constraint(equalToConstant: 24),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12), name.topAnchor.constraint(equalTo: row.topAnchor, constant: 13),
            detail.leadingAnchor.constraint(equalTo: name.leadingAnchor), detail.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 2),
            button.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16), button.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func pluginRow(descriptor: PluginDescriptor, enabled: Bool) -> NSView {
        let row = NSView()
        row.heightAnchor.constraint(equalToConstant: 62).isActive = true
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
        for view in [icon, name, detail, toggle] { view.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(view) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16), icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24), icon.heightAnchor.constraint(equalToConstant: 24),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12), name.topAnchor.constraint(equalTo: row.topAnchor, constant: 13),
            detail.leadingAnchor.constraint(equalTo: name.leadingAnchor), detail.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 2),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16), toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func sectionTitle(_ string: String) -> NSTextField {
        let label = NSTextField(labelWithString: string.uppercased())
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    @objc private func backPressed() { onBack?() }
    @objc private func controllerChanged() { onControllerSelected?(controllerPopup.selectedItem?.representedObject as? String) }
    @objc private func pluginToggled(_ sender: NSSwitch) {
        guard let raw = sender.identifier?.rawValue, let id = PluginID(rawValue: raw) else { return }
        onPluginToggled?(id, sender.state == .on)
    }
    @objc private func openSafariSettings() {
        SFSafariApplication.showPreferencesForExtension(
            withIdentifier: "com.mizore.sui.SafariExtension"
        ) { _ in }
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: Priority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
