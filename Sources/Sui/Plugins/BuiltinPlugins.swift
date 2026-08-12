import AppKit
import ApplicationServices

@MainActor
final class NativeAppPlugin: SuiPlugin {
    let descriptor: PluginDescriptor
    private let bundleIdentifiers: [String]
    private let hints: [String]
    private let host: NativeAutomationHost
    private var preparedTarget: NativeAutomationHost.Target?

    init(descriptor: PluginDescriptor, bundleIdentifiers: [String], hints: [String], host: NativeAutomationHost) {
        self.descriptor = descriptor
        self.bundleIdentifiers = bundleIdentifiers
        self.hints = hints
        self.host = host
    }

    func availability() -> PluginAvailability {
        host.isApplicationInstalled(bundleIdentifiers: bundleIdentifiers)
            ? .available
            : .unavailable("未安装 \(descriptor.name)")
    }

    func prepare() async -> PluginPreparation {
        guard AXIsProcessTrusted() else {
            return .notReady(
                title: "需要辅助功能权限",
                message: "允许 sui 控制 \(descriptor.name) 的当前输入框。",
                actionTitle: "打开系统设置",
                action: .openAccessibilitySettings
            )
        }
        guard let target = host.prepare(bundleIdentifiers: bundleIdentifiers, hints: hints) else {
            return .notReady(
                title: "\(descriptor.name) 未准备好",
                message: descriptor.id == .telegram
                    ? "请先在 Telegram 中打开你想发送消息的聊天。"
                    : "请先打开一个可输入的 Codex 会话。",
                actionTitle: "打开 \(descriptor.name)",
                action: .openApplication(bundleIdentifiers: bundleIdentifiers)
            )
        }
        preparedTarget = target
        return .ready
    }

    func execute(text: String) async throws {
        guard let preparedTarget else { throw SuiError.automation("目标输入框已经失效，请重试。") }
        defer { self.preparedTarget = nil }
        try await host.execute(text: text, target: preparedTarget)
    }
}

@MainActor
final class XPlugin: SuiPlugin {
    let descriptor = PluginDescriptor(id: .x, name: "X.com", symbolName: "bubble.left.and.bubble.right", detail: "Browser Extension")
    private let bridge: BrowserBridge

    init(bridge: BrowserBridge) { self.bridge = bridge }

    func availability() -> PluginAvailability {
        bridge.isConnected ? .available : .unavailable("扩展未连接")
    }

    func prepare() async -> PluginPreparation { await bridge.prepareX() }
    func execute(text: String) async throws { try await bridge.postToX(text) }
}
