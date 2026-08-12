import AVFoundation
import Speech

@available(macOS 27, *)
actor SpeechService {
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var provider: CaptureInputSequenceProvider?
    private var analyzerTask: Task<Void, Error>?
    private var resultsTask: Task<Void, Never>?
    private var finalText = ""
    private var volatileText = ""

    func requestPermissions() async throws {
        let microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard microphoneAllowed else {
            throw SuiError.permission("请在系统设置中允许 sui 使用麦克风。")
        }

        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            throw SuiError.permission("请在系统设置中允许 sui 使用语音识别。")
        }
    }

    func start() async throws {
        guard analyzer == nil else { return }
        try await requestPermissions()

        let currentLocale = await SpeechTranscriber.supportedLocale(equivalentTo: .current)
        let fallbackLocale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "zh-CN"))
        let locale = currentLocale ?? fallbackLocale
        guard let locale else {
            throw SuiError.speech("当前语言不受系统语音识别支持。")
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        let modules: [any SpeechModule] = [transcriber]
        let status = await AssetInventory.status(forModules: modules)
        if status != .installed {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await request.downloadAndInstall()
            }
        }

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
                    if result.isFinal {
                        await self?.appendFinal(text)
                    } else {
                        await self?.setVolatile(text)
                    }
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

    func stop() async throws -> String {
        guard let analyzer, let provider else { return "" }
        provider.captureSession.stopRunning()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        _ = try await analyzerTask?.value
        _ = await resultsTask?.value
        let text = (finalText + volatileText).trimmingCharacters(in: .whitespacesAndNewlines)
        reset()
        return text
    }

    func cancel() async {
        provider?.captureSession.stopRunning()
        await analyzer?.cancelAndFinishNow()
        analyzerTask?.cancel()
        resultsTask?.cancel()
        reset()
    }

    private func appendFinal(_ text: String) {
        finalText += text
        volatileText = ""
    }

    private func setVolatile(_ text: String) {
        volatileText = text
    }

    private func reset() {
        analyzerTask = nil
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        provider = nil
        finalText = ""
        volatileText = ""
    }
}
