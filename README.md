# sui 水

用游戏手柄高强度水群的 macOS 菜单栏工具。

按住手柄按键说话，松开后由 macOS 本地语音识别转成文本，再交给当前绑定的插件：

- A → Telegram 当前聊天
- B → X.com 新 Post
- Y → Codex 当前会话

sui 不保存 Telegram、X 或 OpenAI 凭据，不替用户选择聊天或会话，也不解决游戏按键冲突。

## V0.1 环境

- macOS 27+
- Xcode 27+
- 支持扩展配置的手柄
- 麦克风、语音识别与辅助功能权限

## 开发

```sh
xcodebuild -project Sui.xcodeproj -scheme Sui -configuration Debug build
```

更完整的范围、架构和验收标准见 [docs/product.md](docs/product.md)、[docs/architecture.md](docs/architecture.md) 与 [docs/acceptance.md](docs/acceptance.md)。

## 素材

界面中的手柄矢量图来自 Wikimedia Commons 的 “Video Game Controller (56435) - The Noun Project.svg”，采用 CC0 1.0。

