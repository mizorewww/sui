# V0.1 验收清单

## 构建

- [x] Xcode 27 使用 Apple Development 证书编译成功。
- [x] Debug App 可启动，Hardened Runtime、麦克风说明与 audio-input entitlement 存在。
- [x] `.env`、Derived Data、模型依赖缓存和用户 Xcode 状态不进入 Git。

## 界面

- [x] 首屏是一张透明背景的真实矢量手柄图，而不是白色画布。
- [x] A/B/Y 连线分别落到 Telegram、X.com、Codex 下拉菜单。
- [x] 无目标 App 时相应选项灰置。
- [x] 设置仍在同一窗口，只显示手柄与插件列表。
- [x] 760×520、920×610 与系统 Zoom 尺寸均通过真实截图验收。
- [x] 系统麦克风设置已注册 sui，并显示水滴 App 图标。
- [ ] 关闭窗口后菜单栏图标仍可重新打开。

## 行为

- [ ] 后台接收已选手柄的 A/B/Y down/up。
- [ ] 第一个按键锁定一次 PTT，其他按键不抢占。
- [ ] 按下立即录音，松开结束并取得转写。
- [ ] Telegram/Codex 未打开 composer 时不粘贴，sui 到前台说明原因。
- [ ] X 未安装扩展或未登录时不发布，sui 到前台说明原因。
- [x] Safari 设置能发现唯一一份 `sui Browser Bridge`，且 sui 内提供直接打开扩展设置的入口。
- [ ] 禁用插件后不加载其运行实例。
- [x] Qwen3-ASR 下载取消或失败后恢复系统语音识别。
- [x] 系统语音识别使用 Apple SpeechDetector 过滤非语音片段。

## 人工测试安全线

自动验收不实际发送 Telegram/Codex 消息，也不发布 X 帖子。端到端发送必须由用户打开明确的测试会话后再执行。
