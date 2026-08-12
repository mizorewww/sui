import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.mizore.sui", category: "lifecycle")
    private let browserBridge = BrowserBridge()
    private lazy var plugins = PluginHost(browserBridge: browserBridge)
    private lazy var coordinator = PTTCoordinator(plugins: plugins)
    private let controllers = ControllerService()
    private let mainWindow = MainWindowController()
    private let statusItem = StatusItemController()
    private let permissionCenter = PermissionCenter()

    private var devices: [ControllerService.Device] = []
    private var selectedControllerKey: String?
    private var mappings: [String: PluginID] = ["A": .telegram, "B": .x, "Y": .codex]

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "sui", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        } else {
            logger.error("App icon resource is missing")
        }
        NSApp.setActivationPolicy(.accessory)
        BrowserExtensionInstaller.installNativeMessagingManifests()
        browserBridge.start()
        loadMappings()
        wireActions()
        controllers.start()
        refreshUI()
        mainWindow.show()
        mainWindow.showPermissions(permissionCenter.snapshot)
        logger.notice("sui finished launching")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func wireActions() {
        statusItem.onOpen = { [weak self] in self?.mainWindow.show() }
        mainWindow.onMappingChanged = { [weak self] button, pluginID in
            self?.mappings[button] = pluginID
            UserDefaults.standard.set(pluginID.rawValue, forKey: "mapping.\(button)")
            self?.refreshUI()
        }
        mainWindow.onControllerSelected = { [weak self] key in
            self?.selectedControllerKey = key
            self?.controllers.select(key: key)
            self?.refreshUI()
        }
        mainWindow.onPluginToggled = { [weak self] id, enabled in
            self?.plugins.setEnabled(enabled, id: id)
            self?.refreshUI()
        }
        mainWindow.onRecovery = { [weak self] action in self?.plugins.perform(action) }
        mainWindow.onRequestPermissions = { [weak self] in
            guard let self else { return }
            Task {
                await permissionCenter.requestAll()
                mainWindow.showPermissions(permissionCenter.snapshot, force: true)
            }
        }
        mainWindow.onOpenPermissionSettings = { [weak self] kind in self?.permissionCenter.openSettings(for: kind) }

        controllers.onDevicesChanged = { [weak self] devices in
            self?.devices = devices
            if self?.selectedControllerKey == nil { self?.selectedControllerKey = devices.first?.key }
            self?.refreshUI()
        }
        controllers.onButtonChanged = { [weak self] button, pressed in
            guard let self else { return }
            coordinator.button(button, pressed: pressed, mapping: mappings)
        }
        coordinator.onStateChanged = { [weak self] state in
            self?.mainWindow.setState(state)
            self?.statusItem.setState(state)
        }
        coordinator.onFailure = { [weak self] title, message, actionTitle, action in
            self?.logger.error("PTT failed: \(title, privacy: .public) — \(message, privacy: .public)")
            self?.mainWindow.showFailure(title: title, message: message, actionTitle: actionTitle, action: action)
        }
        browserBridge.onConnectionChanged = { [weak self] connected in
            self?.logger.notice("Browser extension connection: \(connected)")
            self?.refreshUI()
        }
    }

    private func loadMappings() {
        for button in ["A", "B", "Y"] {
            if let raw = UserDefaults.standard.string(forKey: "mapping.\(button)"), let id = PluginID(rawValue: raw) {
                mappings[button] = id
            }
        }
    }

    private func refreshUI() {
        var availability: [PluginID: PluginAvailability] = [:]
        for descriptor in PluginHost.descriptors { availability[descriptor.id] = plugins.availability(for: descriptor.id) }
        mainWindow.update(
            mappings: mappings,
            availability: availability,
            devices: devices,
            selectedKey: selectedControllerKey,
            pluginHost: plugins
        )
    }
}
