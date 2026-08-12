# V0.1 架构

```text
GCController ── down/up ──► PTTCoordinator ◄──► SpeechService
                                  │
                                  ▼
                              PluginHost
                         ┌────────┼────────┐
                         ▼        ▼        ▼
                    Telegram     X.com    Codex
                         │        │         │
                         └─ AX    │    AX ──┘
                                  ▼
                         Browser Extension
```

## 组件边界

- `ControllerService`：枚举手柄、后台监听 A/B/Y、遵守用户选择。
- `SpeechService`：统一管理两条本地识别路径。系统路径使用 SpeechAnalyzer、SpeechTranscriber 与 Apple SpeechDetector；Qwen 路径使用 AVAudioEngine、MLX 与 Qwen3-ASR 0.6B 4-bit。
- `PTTCoordinator`：唯一的 idle → recording → transcribing → executing 状态机。
- `PluginHost`：只实例化启用插件，提供列表、可用性与执行入口。
- `NativeAutomationHost`：应用发现、Accessibility composer 查找、聚焦、粘贴和 Return。
- `BrowserBridge`：与 Chromium Native Messaging helper 或内置 Safari Web Extension 通信；发送结构化命令。
- `MainWindowController`：映射图、单页设置、就绪错误。
- `StatusItemController`：菜单栏打开/退出及状态反馈。

## 插件协议

```swift
protocol SuiPlugin: AnyObject {
    var descriptor: PluginDescriptor { get }
    func availability() -> PluginAvailability
    func prepare() async -> PluginPreparation
    func execute(text: String) async throws
}
```

V0.1 的三个功能通过同一协议实现。禁用插件时，`PluginHost` 保留描述信息用于设置列表，但不构造插件实例、不开启观察和通信。

## 浏览器边界

WebExtension 只接受结构化命令：`prepareX` 与 `postX(text)`。它不执行插件提供的任意 JavaScript。Chromium 通过 Native Messaging helper 与 App 的本地 TCP bridge 通信；Safari 由 `SFSafariApplication.dispatchMessage` 接收命令，复用同一份 X DOM core，再由打包的 Safari Web Extension handler 把结构化结果回传给 App。Safari 扩展必须由用户在 Safari 设置中手动启用。

## 权限与数据

- 系统识别的麦克风音频直接送入 Speech framework，不落盘。Qwen 识别仅在录音期间写入系统临时目录，转写完成或取消后立即删除。
- 转写文本只在内存和目标 App 的剪贴板/DOM 中短暂出现，不写历史数据库。
- Qwen 模型由 App 从 Hugging Face 下载到本机模型缓存；取消或失败不会改变当前可用的系统识别引擎。
- App 不读取 `.env`，不收集第三方 token。
- Accessibility 只用于已启用的原生 App 插件。

## 平台选择

V0.1 直接要求 macOS 27，以使用 `CaptureInputSequenceProvider` 连接麦克风与 `SpeechAnalyzer`，不维护旧版语音栈。窗口与菜单栏完全使用 AppKit。

## 语音活动检测

- 系统识别把 `SpeechDetector(.medium)` 和 `SpeechTranscriber` 放入同一个 `SpeechAnalyzer`，由 Apple 第一方 VAD 抑制静音和非语音片段。
- Qwen 路径在送入 MLX 前使用 20 ms 帧的自适应噪声底裁剪，保留 160 ms 前后余量；没有检测到连续语音时不调用模型。
