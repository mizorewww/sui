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
- `SpeechService`：麦克风输入、SpeechAnalyzer/SpeechTranscriber、本地结果字符串。
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

- 麦克风音频只送入系统 Speech framework，不落盘。
- 转写文本只在内存和目标 App 的剪贴板/DOM 中短暂出现，不写历史数据库。
- App 不读取 `.env`，不收集第三方 token。
- Accessibility 只用于已启用的原生 App 插件。

## 平台选择

V0.1 直接要求 macOS 27，以使用 `CaptureInputSequenceProvider` 连接麦克风与 `SpeechAnalyzer`，不维护旧版语音栈。窗口与菜单栏完全使用 AppKit。
