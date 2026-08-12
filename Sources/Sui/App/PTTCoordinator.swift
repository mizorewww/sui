import Foundation

@MainActor
final class PTTCoordinator {
    enum State: Equatable {
        case idle
        case recording(button: String, plugin: PluginID)
        case transcribing
        case executing(PluginID)

        var label: String {
            switch self {
            case .idle: "Ready"
            case .recording: "Listening…"
            case .transcribing: "Transcribing…"
            case .executing: "Sending…"
            }
        }
    }

    var onStateChanged: ((State) -> Void)?
    var onFailure: ((String, String, String?, PluginRecoveryAction?) -> Void)?

    private let speech = SpeechService()
    private let plugins: PluginHost
    private var state: State = .idle { didSet { onStateChanged?(state) } }
    private var preparationTask: Task<PluginPreparation, Never>?

    init(plugins: PluginHost) { self.plugins = plugins }

    func button(_ button: String, pressed: Bool, mapping: [String: PluginID]) {
        if pressed { begin(button: button, pluginID: mapping[button] ?? .none) }
        else { end(button: button) }
    }

    private func begin(button: String, pluginID: PluginID) {
        guard state == .idle, pluginID != .none, let plugin = plugins.plugin(pluginID) else { return }
        guard plugin.availability().isAvailable else {
            fail(title: "\(plugin.descriptor.name) 不可用", message: "请先安装或启用目标插件。", actionTitle: nil, action: nil)
            return
        }
        state = .recording(button: button, plugin: pluginID)
        preparationTask = Task { await plugin.prepare() }
        Task {
            do { try await speech.start() }
            catch { fail(title: "无法开始录音", message: error.localizedDescription, actionTitle: nil, action: nil) }
        }
    }

    private func end(button: String) {
        guard case .recording(let activeButton, let pluginID) = state, activeButton == button else { return }
        state = .transcribing
        Task {
            let preparation = await preparationTask?.value ?? .notReady(title: "目标未准备好", message: "请重试。", actionTitle: nil, action: nil)
            guard case .ready = preparation else {
                await speech.cancel()
                if case .notReady(let title, let message, let actionTitle, let action) = preparation {
                    fail(title: title, message: message, actionTitle: actionTitle, action: action)
                }
                return
            }
            do {
                let text = try await speech.stop()
                guard !text.isEmpty else {
                    fail(title: "没有听清", message: "没有识别到语音，请按住按键后再说话。", actionTitle: nil, action: nil)
                    return
                }
                state = .executing(pluginID)
                try await plugins.plugin(pluginID)?.execute(text: text)
                state = .idle
            } catch {
                fail(title: "发送失败", message: error.localizedDescription, actionTitle: nil, action: nil)
            }
        }
    }

    private func fail(title: String, message: String, actionTitle: String?, action: PluginRecoveryAction?) {
        preparationTask?.cancel()
        preparationTask = nil
        state = .idle
        onFailure?(title, message, actionTitle, action)
    }
}

