import AVFoundation
import HuggingFace
import MLX
import MLXAudioCore
import MLXAudioSTT
import OSLog
import Speech

enum SpeechEngineChoice: String, Sendable {
    case system
    case qwen3

    static let defaultsKey = "speech.engine"
}

private final class QwenAudioRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private var writeError: Error?

    func start(to url: URL) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw SuiError.speech("麦克风没有提供有效的音频格式。")
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        self.engine = engine
        self.file = file
        writeError = nil
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            lock.withLock {
                do { try file.write(from: buffer) }
                catch { writeError = error }
            }
        }
        engine.prepare()
        try engine.start()
    }

    func stop() throws {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.withLock { file = nil }
        self.engine = nil
        if let writeError { throw writeError }
    }

    func cancel() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.withLock { file = nil }
        self.engine = nil
        writeError = nil
    }
}

@available(macOS 27, *)
actor SpeechService {
    typealias DownloadProgress = @MainActor @Sendable (Double, String) -> Void

    private let logger = Logger(subsystem: "com.mizore.sui", category: "speech")
    private let qwenRepository = "mlx-community/Qwen3-ASR-0.6B-4bit"
    private var selectedEngine: SpeechEngineChoice

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var provider: CaptureInputSequenceProvider?
    private var analyzerTask: Task<Void, Error>?
    private var resultsTask: Task<Void, Never>?
    private var finalText = ""
    private var volatileText = ""
    private var readyLocale: Locale?

    private var qwenModel: Qwen3ASRModel?
    private var qwenRecorder: QwenAudioRecorder?
    private var qwenRecordingURL: URL?

    init() {
        selectedEngine = SpeechEngineChoice(
            rawValue: UserDefaults.standard.string(forKey: SpeechEngineChoice.defaultsKey) ?? ""
        ) ?? .system
    }

    func setEngine(_ engine: SpeechEngineChoice) {
        selectedEngine = engine
        if engine == .system { qwenModel = nil }
        UserDefaults.standard.set(engine.rawValue, forKey: SpeechEngineChoice.defaultsKey)
    }

    func installQwen(progress: @escaping DownloadProgress) async throws {
        try Task.checkCancellation()
        await progress(0.01, "正在连接 Hugging Face…")
        guard let repoID = Repo.ID(rawValue: qwenRepository) else {
            throw SuiError.speech("Qwen3-ASR 模型地址无效。")
        }
        let cache = HubCache.default
        let client = HubClient(cache: cache)
        let modelDirectory = try await ModelUtils.resolveOrDownloadModel(
            client: client,
            cache: cache,
            repoID: repoID,
            requiredExtension: "safetensors"
        ) { download in
            let fraction = download.totalUnitCount > 0 ? download.fractionCompleted : 0
            progress(min(0.90, max(0.02, fraction * 0.90)), "正在下载 Qwen3-ASR 0.6B…")
        }
        try Task.checkCancellation()
        await progress(0.92, "正在载入 MLX 模型…")
        qwenModel = try await Qwen3ASRModel.fromModelDirectory(modelDirectory)
        try Task.checkCancellation()
        selectedEngine = .qwen3
        UserDefaults.standard.set(SpeechEngineChoice.qwen3.rawValue, forKey: SpeechEngineChoice.defaultsKey)
        await progress(1, "Qwen3-ASR 已就绪")
        logger.notice("Qwen3-ASR MLX model is ready")
    }

    func prepare() async throws {
        try await requestPermissions(needsSpeechPermission: selectedEngine == .system)
        if selectedEngine == .qwen3 {
            guard qwenModel != nil else { throw SuiError.speech("Qwen3-ASR 尚未下载完成。") }
            return
        }
        try await prepareSystemSpeech()
    }

    private func prepareSystemSpeech() async throws {
        guard readyLocale == nil else { return }
        let preferredChineseIdentifier = Locale.preferredLanguages.first { $0.hasPrefix("zh") }
        let preferredChinese = preferredChineseIdentifier.flatMap { Locale(identifier: $0) }
        let chineseLocale = if let preferredChinese {
            await SpeechTranscriber.supportedLocale(equivalentTo: preferredChinese)
        } else {
            await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "zh-CN"))
        }
        let currentLocale = await SpeechTranscriber.supportedLocale(equivalentTo: .current)
        guard let locale = chineseLocale ?? currentLocale else {
            throw SuiError.speech("当前语言不受系统语音识别支持。")
        }
        let probe = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        let modules: [any SpeechModule] = [probe, SpeechDetector()]
        let status = await AssetInventory.status(forModules: modules)
        if status != .installed, let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            logger.notice("Installing speech model for \(locale.identifier, privacy: .public)")
            try await request.downloadAndInstall()
        }
        readyLocale = locale
        logger.notice("Speech model with Apple VAD is ready for \(locale.identifier, privacy: .public)")
    }

    func requestPermissions(needsSpeechPermission: Bool = true) async throws {
        let microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard microphoneAllowed else {
            throw SuiError.permission("请在系统设置中允许 sui 使用麦克风。")
        }
        guard needsSpeechPermission else { return }

        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            throw SuiError.permission("请在系统设置中允许 sui 使用语音识别。")
        }
    }

    func start() async throws {
        try await prepare()
        if selectedEngine == .qwen3 {
            try startQwenRecording()
        } else {
            try await startSystemRecording()
        }
    }

    private func startSystemRecording() async throws {
        guard analyzer == nil else { return }
        guard let locale = readyLocale else { throw SuiError.speech("语音模型尚未准备好。") }
        logger.notice("Starting system speech capture with Apple VAD")

        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        let detector = SpeechDetector(
            detectionOptions: .init(sensitivityLevel: .medium),
            reportResults: false
        )
        let modules: [any SpeechModule] = [detector, transcriber]
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            throw SuiError.speech("没有找到可用麦克风。")
        }
        let provider = try await CaptureInputSequenceProvider.providerWithSession(
            from: microphone,
            compatibleWith: modules,
            priority: .userInitiated
        )
        let analyzer = SpeechAnalyzer(modules: modules)
        finalText = ""
        volatileText = ""
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal { await self?.appendFinal(text) }
                    else { await self?.setVolatile(text) }
                }
            } catch {
                // The analyzer task surfaces the operational error to stop().
            }
        }
        self.transcriber = transcriber
        self.provider = provider
        self.analyzer = analyzer
        provider.captureSession.startRunning()
        let inputs = provider.analyzerInputs
        analyzerTask = Task.detached(priority: .userInitiated) {
            try await analyzer.start(inputSequence: inputs)
        }
    }

    private func startQwenRecording() throws {
        guard qwenRecorder == nil else { return }
        guard qwenModel != nil else { throw SuiError.speech("Qwen3-ASR 尚未准备好。") }
        let url = FileManager.default.temporaryDirectory
            .appending(path: "sui-qwen-\(UUID().uuidString).caf")
        let recorder = QwenAudioRecorder()
        try recorder.start(to: url)
        qwenRecorder = recorder
        qwenRecordingURL = url
        logger.notice("Starting Qwen3-ASR audio capture")
    }

    func stop() async throws -> String {
        if selectedEngine == .qwen3 { return try transcribeQwenRecording() }
        return try await stopSystemRecording()
    }

    private func stopSystemRecording() async throws -> String {
        guard let analyzer, let provider else { return "" }
        provider.captureSession.stopRunning()
        try await analyzer.finalize(through: nil)
        await analyzer.cancelAndFinishNow()
        _ = try await analyzerTask?.value
        _ = await resultsTask?.value
        let text = (finalText + volatileText).trimmingCharacters(in: .whitespacesAndNewlines)
        logger.notice("System speech capture stopped with \(text.count) characters")
        resetSystem()
        return text
    }

    private func transcribeQwenRecording() throws -> String {
        guard let recorder = qwenRecorder, let url = qwenRecordingURL, let model = qwenModel else { return "" }
        try recorder.stop()
        defer {
            try? FileManager.default.removeItem(at: url)
            qwenRecorder = nil
            qwenRecordingURL = nil
        }
        let (_, rawAudio) = try loadAudioArray(from: url, sampleRate: 16_000)
        guard let voicedAudio = Self.trimToVoice(rawAudio, sampleRate: 16_000) else {
            logger.notice("Qwen VAD found no speech")
            return ""
        }
        let output = model.generate(
            audio: voicedAudio,
            maxTokens: 512,
            language: nil,
            minChunkDuration: 0.25,
            repetitionPenalty: 1.08
        )
        let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.notice("Qwen transcription stopped with \(text.count) characters")
        return text
    }

    func cancel() async {
        if let qwenRecorder {
            qwenRecorder.cancel()
            if let qwenRecordingURL { try? FileManager.default.removeItem(at: qwenRecordingURL) }
            self.qwenRecorder = nil
            self.qwenRecordingURL = nil
        }
        provider?.captureSession.stopRunning()
        await analyzer?.cancelAndFinishNow()
        analyzerTask?.cancel()
        resultsTask?.cancel()
        resetSystem()
    }

    private static func trimToVoice(_ audio: MLXArray, sampleRate: Int) -> MLXArray? {
        let samples = audio.asArray(Float.self)
        let frameSize = max(1, sampleRate / 50) // 20 ms
        guard samples.count >= frameSize * 6 else { return nil }
        var levels: [Float] = []
        for start in stride(from: 0, to: samples.count, by: frameSize) {
            let end = min(samples.count, start + frameSize)
            let power = samples[start..<end].reduce(Float.zero) { $0 + $1 * $1 } / Float(end - start)
            levels.append(10 * log10(max(power, 1e-10)))
        }
        let sorted = levels.sorted()
        let noiseFloor = sorted[min(sorted.count - 1, sorted.count / 5)]
        let threshold = max(-42, noiseFloor + 10)
        let active = levels.indices.filter { levels[$0] >= threshold }
        guard active.count >= 6, let first = active.first, let last = active.last else { return nil }
        let paddingFrames = 8
        let startFrame = max(0, first - paddingFrames)
        let endFrame = min(levels.count, last + paddingFrames + 1)
        return MLXArray(Array(samples[(startFrame * frameSize)..<min(samples.count, endFrame * frameSize)]))
    }

    private func appendFinal(_ text: String) {
        finalText += text
        volatileText = ""
    }

    private func setVolatile(_ text: String) { volatileText = text }

    private func resetSystem() {
        analyzerTask = nil
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        provider = nil
        finalText = ""
        volatileText = ""
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
