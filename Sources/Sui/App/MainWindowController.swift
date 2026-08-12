import AppKit

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let mappingView = MappingView()
    private let settingsView = SettingsView()
    private let permissionView = PermissionSetupView()
    private let content = NSVisualEffectView()
    private let pageContainer = NSView()
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private let settingsButton = NSButton()
    private let errorBox = NSBox()
    private let errorTitle = NSTextField(labelWithString: "")
    private let errorMessage = NSTextField(wrappingLabelWithString: "")
    private let recoveryButton = NSButton()
    private var recoveryAction: PluginRecoveryAction?
    private var downloadPanel: NSPanel?
    private var downloadProgress: NSProgressIndicator?
    private var downloadStatus: NSTextField?

    var onMappingChanged: ((String, PluginID) -> Void)?
    var onControllerSelected: ((String?) -> Void)?
    var onPluginToggled: ((PluginID, Bool) -> Void)?
    var onQwenToggled: ((Bool) -> Void)?
    var onCancelQwenDownload: (() -> Void)?
    var onRecovery: ((PluginRecoveryAction) -> Void)?
    var onRequestPermissions: (() -> Void)?
    var onOpenPermissionSettings: ((PermissionCenter.Kind) -> Void)?

    init() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 920, height: 610),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "sui"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = CGSize(width: 760, height: 520)
        window.contentMinSize = CGSize(width: 760, height: 492)
        window.setFrameAutosaveName("sui.main-window")
        window.center()
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func update(mappings: [String: PluginID], availability: [PluginID: PluginAvailability], devices: [ControllerService.Device], selectedKey: String?, pluginHost: PluginHost, qwenEnabled: Bool) {
        mappingView.configure(mappings: mappings, availability: availability, hasController: !devices.isEmpty)
        settingsView.configure(devices: devices, selectedKey: selectedKey, pluginHost: pluginHost, qwenEnabled: qwenEnabled)
    }

    func setState(_ state: PTTCoordinator.State) {
        statusLabel.stringValue = state.label
        statusLabel.textColor = state == .idle ? .secondaryLabelColor : .controlAccentColor
    }

    func showPermissions(_ snapshot: PermissionCenter.Snapshot, force: Bool = false) {
        permissionView.update(snapshot)
        if force || !snapshot.isReady { showPage(permissionView); settingsButton.isHidden = true }
    }

    func showFailure(title: String, message: String, actionTitle: String?, action: PluginRecoveryAction?) {
        errorTitle.stringValue = title
        errorMessage.stringValue = message
        recoveryAction = action
        recoveryButton.title = actionTitle ?? ""
        recoveryButton.isHidden = actionTitle == nil
        errorBox.isHidden = false
        show()
    }

    func showQwenDownload(progress: Double = 0, status: String = "准备下载…") {
        if downloadPanel == nil { buildDownloadPanel() }
        guard let window, let panel = downloadPanel else { return }
        downloadProgress?.doubleValue = progress * 100
        downloadStatus?.stringValue = status
        show()
        if panel.sheetParent == nil { window.beginSheet(panel) }
    }

    func updateQwenDownload(progress: Double, status: String) {
        downloadProgress?.doubleValue = progress * 100
        downloadStatus?.stringValue = status
    }

    func closeQwenDownload() {
        guard let panel = downloadPanel else { return }
        if let parent = panel.sheetParent { parent.endSheet(panel) }
        panel.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    private func buildUI() {
        guard let window else { return }
        content.material = .sidebar
        content.blendingMode = .behindWindow
        content.state = .active
        window.contentView = content

        let drop = NSImageView(image: NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "sui")!)
        drop.contentTintColor = .controlAccentColor
        let title = NSTextField(labelWithString: "sui")
        title.font = .systemFont(ofSize: 18, weight: .bold)
        let subtitle = NSTextField(labelWithString: "水群，按住就说")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor

        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.alignment = .right
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        settingsButton.bezelStyle = .accessoryBarAction
        settingsButton.target = self
        settingsButton.action = #selector(showSettings)

        pageContainer.wantsLayer = true
        pageContainer.layer?.backgroundColor = NSColor.clear.cgColor

        errorBox.boxType = .custom
        errorBox.cornerRadius = 12
        errorBox.fillColor = NSColor.systemOrange.withAlphaComponent(0.10)
        errorBox.borderColor = NSColor.systemOrange.withAlphaComponent(0.35)
        errorBox.isHidden = true
        errorTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        errorMessage.font = .systemFont(ofSize: 11)
        errorMessage.textColor = .secondaryLabelColor
        recoveryButton.bezelStyle = .rounded
        recoveryButton.target = self
        recoveryButton.action = #selector(recover)
        let dismiss = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")!, target: self, action: #selector(dismissError))
        dismiss.bezelStyle = .accessoryBarAction

        for view in [drop, title, subtitle, statusLabel, settingsButton, pageContainer, errorBox] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        for view in [errorTitle, errorMessage, recoveryButton, dismiss] {
            view.translatesAutoresizingMaskIntoConstraints = false
            errorBox.addSubview(view)
        }
        mappingView.translatesAutoresizingMaskIntoConstraints = false
        pageContainer.addSubview(mappingView)

        NSLayoutConstraint.activate([
            drop.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28), drop.topAnchor.constraint(equalTo: content.topAnchor, constant: 27), drop.widthAnchor.constraint(equalToConstant: 24), drop.heightAnchor.constraint(equalToConstant: 24),
            title.leadingAnchor.constraint(equalTo: drop.trailingAnchor, constant: 9), title.topAnchor.constraint(equalTo: content.topAnchor, constant: 23),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor), subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: -1),
            settingsButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24), settingsButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 26),
            statusLabel.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -14), statusLabel.centerYAnchor.constraint(equalTo: settingsButton.centerYAnchor),
            pageContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22), pageContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            pageContainer.topAnchor.constraint(equalTo: content.topAnchor, constant: 78), pageContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -22),
            mappingView.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor), mappingView.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor), mappingView.topAnchor.constraint(equalTo: pageContainer.topAnchor), mappingView.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor),
            errorBox.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor, constant: 18), errorBox.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor, constant: -18), errorBox.topAnchor.constraint(equalTo: pageContainer.topAnchor, constant: 16), errorBox.heightAnchor.constraint(equalToConstant: 74),
            errorTitle.leadingAnchor.constraint(equalTo: errorBox.leadingAnchor, constant: 16), errorTitle.topAnchor.constraint(equalTo: errorBox.topAnchor, constant: 12),
            errorMessage.leadingAnchor.constraint(equalTo: errorTitle.leadingAnchor), errorMessage.trailingAnchor.constraint(lessThanOrEqualTo: recoveryButton.leadingAnchor, constant: -12), errorMessage.topAnchor.constraint(equalTo: errorTitle.bottomAnchor, constant: 3),
            recoveryButton.trailingAnchor.constraint(equalTo: dismiss.leadingAnchor, constant: -10), recoveryButton.centerYAnchor.constraint(equalTo: errorBox.centerYAnchor),
            dismiss.trailingAnchor.constraint(equalTo: errorBox.trailingAnchor, constant: -10), dismiss.topAnchor.constraint(equalTo: errorBox.topAnchor, constant: 10)
        ])

        mappingView.onMappingChanged = { [weak self] in self?.onMappingChanged?($0, $1) }
        settingsView.onBack = { [weak self] in self?.showMapping() }
        settingsView.onControllerSelected = { [weak self] in self?.onControllerSelected?($0) }
        settingsView.onPluginToggled = { [weak self] in self?.onPluginToggled?($0, $1) }
        settingsView.onQwenToggled = { [weak self] in self?.onQwenToggled?($0) }
        permissionView.onGrant = { [weak self] in self?.onRequestPermissions?() }
        permissionView.onOpenSettings = { [weak self] in self?.onOpenPermissionSettings?($0) }
        permissionView.onContinue = { [weak self] in self?.showMapping() }
    }

    @objc private func showSettings() {
        showPage(settingsView)
        settingsButton.isHidden = true
    }

    private func showMapping() {
        showPage(mappingView)
        settingsButton.isHidden = false
    }

    private func showPage(_ view: NSView) {
        pageContainer.subviews.filter { $0 !== errorBox }.forEach { $0.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = false
        pageContainer.addSubview(view, positioned: .below, relativeTo: errorBox)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor), view.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
            view.topAnchor.constraint(equalTo: pageContainer.topAnchor), view.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor)
        ])
    }

    @objc private func recover() { if let recoveryAction { onRecovery?(recoveryAction) } }
    @objc private func dismissError() { errorBox.isHidden = true }

    private func buildDownloadPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 190),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "下载 Qwen3-ASR"
        panel.isMovable = false

        let icon = NSImageView(image: NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "下载")!)
        icon.contentTintColor = .controlAccentColor
        let title = NSTextField(labelWithString: "Qwen3-ASR 0.6B · MLX 4-bit")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString: "模型只下载一次并保存在本机。取消或下载失败时会自动切回系统语音识别。")
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: 12)
        let progress = NSProgressIndicator()
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 100
        progress.controlSize = .regular
        let status = NSTextField(labelWithString: "准备下载…")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelQwenDownload))

        guard let contentView = panel.contentView else { return }
        for view in [icon, title, detail, progress, status, cancel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            icon.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            icon.widthAnchor.constraint(equalToConstant: 34), icon.heightAnchor.constraint(equalToConstant: 34),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            title.topAnchor.constraint(equalTo: icon.topAnchor),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor), detail.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            progress.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            progress.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            progress.topAnchor.constraint(equalTo: detail.bottomAnchor, constant: 20),
            status.leadingAnchor.constraint(equalTo: progress.leadingAnchor), status.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 8),
            cancel.trailingAnchor.constraint(equalTo: progress.trailingAnchor), cancel.centerYAnchor.constraint(equalTo: status.centerYAnchor)
        ])
        downloadPanel = panel
        downloadProgress = progress
        downloadStatus = status
    }

    @objc private func cancelQwenDownload() { onCancelQwenDownload?() }
}
