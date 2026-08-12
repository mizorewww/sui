import AppKit
import SafariServices

@MainActor
final class PluginHost {
    static let descriptors: [PluginDescriptor] = [
        .init(id: .telegram, name: "Telegram", symbolName: "paperplane.fill", detail: "Current chat"),
        .init(id: .x, name: "X.com", symbolName: "bubble.left.and.bubble.right", detail: "New post"),
        .init(id: .codex, name: "Codex", symbolName: "chevron.left.forwardslash.chevron.right", detail: "Current task")
    ]

    private let automation = NativeAutomationHost()
    private let browserBridge: BrowserBridge
    private var instances: [PluginID: SuiPlugin] = [:]
    private let defaults = UserDefaults.standard

    init(browserBridge: BrowserBridge) {
        self.browserBridge = browserBridge
        for id in [PluginID.telegram, .x, .codex] where defaults.object(forKey: enabledKey(id)) == nil {
            defaults.set(true, forKey: enabledKey(id))
        }
    }

    func isEnabled(_ id: PluginID) -> Bool { defaults.bool(forKey: enabledKey(id)) }

    func setEnabled(_ enabled: Bool, id: PluginID) {
        defaults.set(enabled, forKey: enabledKey(id))
        if !enabled { instances[id] = nil }
    }

    func plugin(_ id: PluginID) -> SuiPlugin? {
        guard id != .none, isEnabled(id) else { return nil }
        if let instance = instances[id] { return instance }
        let instance: SuiPlugin?
        switch id {
        case .telegram:
            instance = NativeAppPlugin(
                descriptor: Self.descriptors.first { $0.id == .telegram }!,
                bundleIdentifiers: ["com.tdesktop.Telegram", "ru.keepcoder.Telegram", "org.telegram.desktop"],
                hints: ["message", "write", "消息", "信息"],
                host: automation
            )
        case .x:
            instance = XPlugin(bridge: browserBridge)
        case .codex:
            instance = NativeAppPlugin(
                descriptor: Self.descriptors.first { $0.id == .codex }!,
                bundleIdentifiers: ["com.openai.codex", "com.openai.chat", "com.openai.ChatGPT"],
                hints: ["prompt", "message", "codex", "问"],
                host: automation
            )
        case .none:
            instance = nil
        }
        instances[id] = instance
        return instance
    }

    func availability(for id: PluginID) -> PluginAvailability {
        guard isEnabled(id) else { return .unavailable("插件已停用") }
        return plugin(id)?.availability() ?? .unavailable("不可用")
    }

    func requestAccessibility() { automation.requestAccessibility() }

    func perform(_ action: PluginRecoveryAction) {
        switch action {
        case .openApplication(let identifiers):
            automation.open(bundleIdentifiers: identifiers)
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        case .openAccessibilitySettings:
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
            automation.requestAccessibility()
        case .openExtensionsFolder:
            let url = Bundle.main.resourceURL?.appending(path: "BrowserExtension")
            if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        case .openSafariSettings:
            SFSafariApplication.showPreferencesForExtension(
                withIdentifier: "com.mizore.sui.SafariExtension"
            ) { _ in }
        }
    }

    private func enabledKey(_ id: PluginID) -> String { "plugin.\(id.rawValue).enabled" }
}
