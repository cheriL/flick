# Flick · 设计文档

**日期**：2026-08-12
**状态**：已批准（用户逐节确认通过）
**作者**：Soup（与 Claude 协作 brainstorm）

---

## 1. 目标

实现一款极简的 macOS 菜单栏翻译软件 Flick。用户在任何 App 中选中一段文本后，鼠标旁边自动弹出小翻译按钮；点击按钮后展示译文。支持两种翻译模式：

- **普通翻译**：使用 macOS 内置 Apple Translation framework（免费、本地、可离线）
- **AI 翻译**：按住 `⌘` 修饰键选词时触发，使用 OpenAI 兼容协议（OpenAI / Claude / DeepSeek）

---

## 2. 用户故事

| 编号 | 故事 |
|---|---|
| US-1 | 作为用户，我在 Safari 阅读英文文章时选中一段文本，希望无需离开当前页面就能看到中文译文 |
| US-2 | 作为用户，我希望默认用本地翻译（快、免费），但遇到俚语 / 长句时按住 `⌘` 就能切到 AI 获得更自然的翻译 |
| US-3 | 作为用户，我希望 AI 翻译只在我需要时调用，且 API Key 安全存储 |
| US-4 | 作为用户，我希望译文只显示译文本身（极简），不需要复制按钮、发音按钮等干扰元素 |
| US-5 | 作为用户，我希望浮窗出现在鼠标旁边，眼睛无需大幅移动 |

---

## 3. 功能需求

### 3.1 触发与 UI 形态

- Flick 是纯菜单栏常驻 App，**无 Dock 图标、无主窗口、无全局快捷键**
- 菜单栏图标使用 SF Symbol（`character.bubble` 或 `translate`），常驻显示
- **不**监听全局快捷键；选中文本是唯一触发方式

### 3.2 文本选择捕获

- 每 0.3 秒通过 macOS Accessibility API（`AXUIElementCopyAttributeValue`）轮询前台 App 的选区
- 选区发生变化或非空时触发；选区未变化跳过
- 单次选区文本长度 ≤ 5000 字符；超出则忽略（避免误触 / 性能问题）
- 选区位于 Flick 自身浮窗内时忽略（避免递归）
- ⌘ 修饰键状态在轮询那一刻读取（`NSEvent.modifierFlags`）

### 3.3 浮窗 UI

#### Trigger Button

- 28×28 pt 圆形按钮，半透明背景（`.regularMaterial`）
- 文字内容：未按 `⌘` 显示 "译"，按住 `⌘` 显示 "AI"
- 位置：鼠标光标右下方 12pt 偏移；若越界则翻转到左下方
- 出现动画：opacity 0→1 + scale 0.8→1，0.15s
- **不抢焦点**（`.nonactivatingPanel`）
- 选区变化时平移到新位置；选区消失或 ESC 时关闭

#### Result Window

- 宽 360pt，高度自适应（最小 60，最大 400）
- 位置与 Trigger Button 同位（按钮被替换为窗口，不跳位置）
- 不抢焦点
- 内容：原文（小字灰）+ 译文（大字），仅此而已
- 关闭：ESC 键、点击浮窗外部、选区变化时自动消失

### 3.4 翻译服务

#### 3.4.1 Apple Translation（普通模式）

- 使用 Apple 的 `Translation` framework（macOS 12.0 引入；Flick 整体最低 macOS 14.0 来自 MenuBarExtra 要求）
- 源语言自动检测（`source: nil`）
- 目标语言 = macOS 系统首选语言（`Locale.preferredLanguages.first`）
- **注意**：`TranslationSession` 必须挂载在 SwiftUI 视图里才能工作。实现时创建一个 `HiddenTranslationHost` —— 一个尺寸为 1×1、opacity=0、isHidden=true 的 SwiftUI 视图，作为 `TranslationSession.configuration` 的承载者；它的存在不影响 UI，但让 Apple 框架能正常运行

#### 3.4.2 OpenAI 兼容（AI 模式，按住 `⌘` 触发）

支持的 Provider：

| Provider | 路径 | 鉴权 header | 备注 |
|---|---|---|---|
| OpenAI | `/v1/chat/completions` | `Authorization: Bearer` | 默认 |
| DeepSeek | `/v1/chat/completions` | `Authorization: Bearer` | 与 OpenAI 完全兼容 |
| Claude | `/v1/messages` | `x-api-key` + `anthropic-version` | API 结构不同，需分支 |

- 请求体构造统一 prompt：
  > "Translate the following text into {target language name}. Only output the translation, no explanation, no quotes. {text}"
- 超时 30s；网络失败重试 1 次（指数退避 0.5s）
- 用户取消时抛 `cancelled` 错误，上游吞掉不展示

### 3.5 模式切换

- **不按 `⌘`** → 普通翻译（Apple Translation）
- **按住 `⌘`** → AI 翻译
- 状态在轮询时基于 `NSEvent.modifierFlags` 判断
- **时机说明**：用户在选词之前按住 `⌘`、或选词之后按住 `⌘` 都会触发 AI 模式 —— 因为轮询在采样那一刻读 `modifierFlags`，只要那时还按着就算 AI

### 3.6 目标语言

- 始终跟随 macOS 系统首选语言（`Locale.preferredLanguages.first`）
- 用户不可手动切换（在偏好设置中暴露是未来扩展，本次不做）

### 3.7 配置存储

| 数据 | 存储位置 |
|---|---|
| provider, baseURL, model | UserDefaults |
| apiKey | Keychain（`kSecClassGenericPassword`，service=`com.cheriL.flick`）|
| 上次使用时间 | UserDefaults（仅调试用）|

### 3.8 AI 设置 Popover

菜单栏 → "AI 设置..." 触发一个 SwiftUI popover，包含：

- 服务商下拉（OpenAI / Claude）
- Base URL 输入框
- API Key 输入框（SecureField）
- 模型名输入框
- "测试连接" 按钮（发一个 "hello" → 中文 的小请求）
- "保存" 按钮

### 3.9 菜单栏菜单

```
┌─────────────────────────────────┐
│  ⌘  按住 ⌘ 选词 → AI 翻译      │   ← 帮助提示（只读）
├─────────────────────────────────┤
│  ⚙  AI 设置...                  │
├─────────────────────────────────┤
│  ⏻  退出 Flick                  │
└─────────────────────────────────┘
```

---

## 4. 错误处理

| 场景 | 用户看到 |
|---|---|
| 未授权辅助功能 | 菜单栏顶部红点 + 引导提示 "请在 系统设置 → 隐私与安全 → 辅助功能 启用 Flick" |
| Apple 不支持的语言对 | "Apple 不支持 [源]→[目标]，请用 AI 模式（按住 ⌘）" |
| AI 未配置 API Key | "AI 翻译需要先在菜单栏 → AI 设置 配置 API Key" |
| 网络超时 | "翻译超时 [重试]" |
| API Key 无效（401） | "API Key 无效，请在 AI 设置 检查" |
| 文本超长（>5000 字） | 静默忽略，不显示按钮 |
| 选区在浮窗内 | 静默忽略 |

---

## 5. 权限

- App 启动时 `AXIsProcessTrusted()` 检查辅助功能权限
- 未授权 → 菜单栏显示红点提示 + "去设置" 按钮（调用 `AXIsProcessTrustedWithOptions({prompt: true})`）
- 用户拒绝后，每天最多提示一次（不骚扰）

---

## 6. 架构

```
┌──────────────────────────────────────────────────────────────────┐
│                          Flick.app                                │
│  LSUIElement = YES（无 Dock 图标、无主窗口）                        │
│  macOS 14+, SwiftUI + 少量 AppKit                                 │
└──────────────────────────────────────────────────────────────────┘
        │
        ├── MenuBarController ── MenuBarExtra（菜单栏图标 + 下拉菜单）
        │
        ├── TextSelectionMonitor ── 0.3s 轮询 AXUIElement
        │
        ├── FloatingPanelController ── 两块 NSPanel
        │   ├─ triggerButtonPanel: 鼠标旁的小圆按钮
        │   └─ resultPanel:        译文窗口
        │
        ├── TranslationService (protocol)
        │   ├─ AppleTranslationService   (Translation framework)
        │   └─ OpenAICompatibleService   (URLSession)
        │
        └── ConfigStore
            ├─ UserDefaults: provider, baseURL, model
            └─ Keychain:      apiKey
```

### 数据流

```
  用户选中文本 ──┐
  ⌘ 是否按下 ───┤
                ▼
        TextSelectionMonitor.poll()
                │
                │ (text, location, isAI)
                ▼
        FloatingPanelController.showTrigger(at, text, isAI)
                │
                │ 用户点击按钮
                ▼
        TranslationService.translate(text, target, isAI)
                │
                │ async result
                ▼
        FloatingPanelController.showResult(translation, at)
                │
                │ ESC / 外部点击 / 选区变化
                ▼
        FloatingPanelController.dismiss()
```

---

## 7. 技术栈与打包

- **语言**：Swift 5.9+
- **UI**：SwiftUI（MenuBarExtra、SettingsPopover）+ AppKit（NSPanel、AXUIElement）
- **最低系统**：macOS 14.0（MenuBarExtra 要求）
- **构建**：Swift Package Manager（`Package.swift`）
  - 主可执行 target：`Flick`
  - 资源（Info.plist、Assets）：通过 `resources:` 处理
- **打包脚本**：shell 脚本生成 `.app` bundle 结构：
  ```
  Flick.app/
    Contents/
      Info.plist        (LSUIElement=YES, LSMinimumSystemVersion=14.0)
      MacOS/Flick       (可执行文件)
      Resources/        (Assets.car 等)
  ```
- **未来扩展**：codesign + notarize（本次不做）

---

## 8. 测试策略

### 8.1 单元测试

- `TextSelectionMonitor`：模拟选区变化、⌘ 状态、验证通知触发
- `OpenAICompatibleService`：mock URLSession，验证请求构造、响应解析、错误处理
- `ConfigStore`：Keychain 读写、UserDefaults 读写、JSON 编解码

### 8.2 集成测试

- Apple Translation：用一个隐藏 SwiftUI 视图 + `TranslationSession` 验证 hello world 翻译
- AI 端到端：用 mock HTTP server 验证 provider 分支（OpenAI / Claude / DeepSeek）

### 8.3 手动验证清单

- [ ] 启动后菜单栏出现图标，无 Dock 图标
- [ ] 在 Safari 选中文本 → 鼠标旁出现 "译" 按钮
- [ ] 按住 ⌘ 选文本 → 出现 "AI" 按钮
- [ ] 点击按钮 → 译文出现
- [ ] 按 ESC → 译文关闭
- [ ] 点浮窗外部 → 译文关闭
- [ ] 选区变化 → 旧浮窗消失，新按钮出现
- [ ] 未授权辅助功能时显示引导提示
- [ ] 菜单栏 → AI 设置 → 配置后能正常翻译

### 8.4 用户体感验证

- 0.3s 轮询间隔是否流畅（开发期可调）
- 浮窗位置是否准确（鼠标偏移、边界翻转）
- Apple Translation 隐藏承载视图是否引入延迟

---

## 9. 未来扩展（不在本次范围）

- 选词替换（选中 → 直接覆盖原文本）
- 翻译历史记录
- 多目标语言切换
- AI 流式输出（打字机效果）
- 自定义快捷键切换模式
- 开机自启
- 统计与用量监控

---

## 10. 风险与缓解

| 风险 | 缓解 |
|---|---|
| Apple Translation 必须挂 SwiftUI 视图 | 创建一个 `HiddenTranslationHost`（1×1 隐藏 SwiftUI 视图）专门承载 `TranslationSession`，不影响 UI |
| 不同 Mac App 的 AXUI 行为不一致 | 在多个 App 测一遍（Safari、Chrome、TextEdit、VS Code、Notes）；失败时静默忽略，不崩溃 |
| ⌘ 采样时机不准 | 用户在轮询间隔（0.3s）内松开 ⌘ 可能误判；可接受为极小概率，必要时把间隔缩短到 0.2s |
| Keychain 在 sandbox / dev 模式差异 | 用通用 keychain（无 sandbox）；调试时可通过 `security delete-generic-password` 清缓存 |
| Claude API 与 OpenAI API 结构差异大 | 在 `OpenAICompatibleService` 里按 `Provider` 分支构造请求体，单元测试覆盖两个分支 |
| 翻译时鼠标移到别处 | 用户点 ESC 或外部关闭即可，不主动追踪 |

---

## 11. 开放问题（开发期验证）

- 轮询间隔 0.3s 是否合适（用户希望体感测试后调整）
- 浮窗背景色 / 圆角 / 阴影的具体视觉风格（开发期截图给用户确认）
- AI 设置 popover 的字段顺序（Provider → URL → Key → Model vs URL → Provider → Model → Key）
