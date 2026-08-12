import Foundation
import OSLog

@MainActor
final class PTTCoordinator {
    private let logger = Logger(subsystem: "com.mizore.sui", category: "ptt")
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
    private var recordingTask: Task<Void, Error>?
    private var warmupTask: Task<Void, Error>?

    init(plugins: PluginHost) {
        self.plugins = plugins
        warmupTask = Task { try await speech.prepare() }
    }

    func installQwen(progress: @escaping SpeechService.DownloadProgress) async throws {
        try await speech.installQwen(progress: progress)
        warmupTask = Task { try await speech.prepare() }
        try await warmupTask?.value
    }

    func useSystemSpeech() {
        warmupTask?.cancel()
        warmupTask = Task {
            await speech.setEngine(.system)
            try await speech.prepare()
        }
    }

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
        logger.notice("Button \(button, privacy: .public) pressed for \(pluginID.rawValue, privacy: .public)")
        preparationTask = Task { await plugin.prepare() }
        recordingTask = Task { [weak self] in
            try await self?.warmupTask?.value
            try await self?.speech.start()
        }
    }

    private func end(button: String) {
        guard case .recording(let activeButton, let pluginID) = state, activeButton == button else { return }
        state = .transcribing
        Task {
            logger.notice("Button \(button, privacy: .public) released")
            do {
                try await recordingTask?.value
            } catch {
                await speech.cancel()
                fail(title: "无法开始录音", message: error.localizedDescription, actionTitle: nil, action: nil)
                return
            }
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
                logger.notice("Transcription finished with \(text.count) characters")
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
        recordingTask?.cancel()
        preparationTask = nil
        recordingTask = nil
        state = .idle
        onFailure?(title, message, actionTitle, action)
    }
}
