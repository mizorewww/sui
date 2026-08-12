<p align="center">
  <img src="Sources/Sui/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="sui logo">
</p>

<h1 align="center">sui 水</h1>

<p align="center">用游戏手柄说话、转文字、快速水群的 macOS 菜单栏工具。</p>

按住手柄按键开始录音，松开后由 macOS 本地语音识别转成文字，并发送到绑定的应用。

默认映射：

- A → Telegram 当前聊天
- B → X.com 新帖
- Y → Codex 当前任务

## 使用方式

1. 用 Xcode 打开 `Sui.xcodeproj`，选择 **Sui** Scheme，编译并运行。
2. 首次启动时允许麦克风、语音识别和辅助功能权限。
3. 在 **Settings** 中选择手柄，并启用需要的插件。
4. 在主界面给手柄按键选择 Telegram、X.com 或 Codex。
5. 先打开目标聊天或任务，按住对应按键说话，松开即可发送。

### X.com 扩展

- Safari：在 sui 的 **Settings → Safari Extension → Open Settings** 中打开 Safari 设置，然后勾选 `sui Browser Bridge`。
- Chromium 浏览器：加载 App 内附带的 `BrowserExtension` 扩展。

## 要求

- macOS 27+
- Xcode 27+
- macOS 支持的游戏手柄

更详细的产品范围与架构见 [`docs`](docs)。
