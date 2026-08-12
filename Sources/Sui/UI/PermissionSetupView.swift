import AppKit

@MainActor
final class PermissionSetupView: NSView {
    var onGrant: (() -> Void)?
    var onOpenSettings: ((PermissionCenter.Kind) -> Void)?
    var onContinue: (() -> Void)?

    private let card = NSView()
    private let grantButton = NSButton(title: "Allow Access", target: nil, action: nil)
    private let continueButton = NSButton(title: "Continue", target: nil, action: nil)
    private var rows: [PermissionCenter.Kind: PermissionRow] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        card.wantsLayer = true
        card.layer?.cornerRadius = 18
        card.layer?.cornerCurve = .continuous
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.76).cgColor
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        card.layer?.borderWidth = 1

        let icon = NSImageView(image: NSImage(systemSymbolName: "waveform.badge.mic", accessibilityDescription: "Permissions")!)
        icon.symbolConfiguration = .init(pointSize: 27, weight: .medium)
        icon.contentTintColor = .controlAccentColor
        let title = NSTextField(labelWithString: "Set up sui")
        title.font = .systemFont(ofSize: 24, weight: .bold)
        let detail = NSTextField(wrappingLabelWithString: "Three permissions let sui hear you and place the transcript in the right app. Nothing is recorded until you hold a mapped button.")
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor

        let mic = PermissionRow(symbol: "mic.fill", title: "Microphone", detail: "Capture while a controller button is held")
        let speech = PermissionRow(symbol: "waveform", title: "Speech Recognition", detail: "Convert audio to text on this Mac")
        let ax = PermissionRow(symbol: "cursorarrow.motionlines", title: "Accessibility", detail: "Focus Telegram or Codex and paste the result")
        rows = [.microphone: mic, .speech: speech, .accessibility: ax]
        mic.onAction = { [weak self] in self?.onOpenSettings?(.microphone) }
        speech.onAction = { [weak self] in self?.onOpenSettings?(.speech) }
        ax.onAction = { [weak self] in self?.onOpenSettings?(.accessibility) }

        grantButton.bezelStyle = .rounded
        grantButton.controlSize = .large
        grantButton.keyEquivalent = "\r"
        grantButton.target = self
        grantButton.action = #selector(grant)
        continueButton.bezelStyle = .accessoryBarAction
        continueButton.target = self
        continueButton.action = #selector(continuePressed)

        let stack = NSStackView(views: [mic, speech, ax])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .width
        for view in [card, icon, title, detail, stack, grantButton, continueButton] { view.translatesAutoresizingMaskIntoConstraints = false }
        addSubview(card)
        for view in [icon, title, detail, stack, grantButton, continueButton] { card.addSubview(view) }

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 600),
            card.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.72),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 30), icon.topAnchor.constraint(equalTo: card.topAnchor, constant: 28), icon.widthAnchor.constraint(equalToConstant: 34), icon.heightAnchor.constraint(equalToConstant: 34),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12), title.topAnchor.constraint(equalTo: card.topAnchor, constant: 27),
            detail.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 30), detail.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -30), detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: detail.leadingAnchor), stack.trailingAnchor.constraint(equalTo: detail.trailingAnchor), stack.topAnchor.constraint(equalTo: detail.bottomAnchor, constant: 22),
            continueButton.leadingAnchor.constraint(equalTo: stack.leadingAnchor), continueButton.centerYAnchor.constraint(equalTo: grantButton.centerYAnchor),
            grantButton.trailingAnchor.constraint(equalTo: stack.trailingAnchor), grantButton.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 20), grantButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ snapshot: PermissionCenter.Snapshot) {
        rows[.microphone]?.update(snapshot.microphone)
        rows[.speech]?.update(snapshot.speech)
        rows[.accessibility]?.update(snapshot.accessibility)
        grantButton.title = snapshot.isReady ? "Done" : "Allow Access"
    }

    @objc private func grant() { onGrant?() }
    @objc private func continuePressed() { onContinue?() }
}

@MainActor
private final class PermissionRow: NSView {
    var onAction: (() -> Void)?
    private let status = NSButton(title: "", target: nil, action: nil)

    init(symbol: String, title: String, detail: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.58).cgColor
        heightAnchor.constraint(equalToConstant: 58).isActive = true
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)!)
        icon.contentTintColor = .controlAccentColor
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 10.5)
        detailLabel.textColor = .secondaryLabelColor
        status.bezelStyle = .accessoryBarAction
        status.target = self
        status.action = #selector(actionPressed)
        for view in [icon, titleLabel, detailLabel, status] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15), icon.centerYAnchor.constraint(equalTo: centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 22), icon.heightAnchor.constraint(equalToConstant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12), titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor), detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), status.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: status.leadingAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ state: PermissionCenter.State) {
        status.title = state.label
        status.image = NSImage(systemSymbolName: state == .granted ? "checkmark.circle.fill" : "exclamationmark.circle", accessibilityDescription: nil)
        status.contentTintColor = state == .granted ? .systemGreen : .systemOrange
        status.isEnabled = state == .denied
    }

    @objc private func actionPressed() { onAction?() }
}
