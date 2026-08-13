# Flick

极简 macOS 菜单栏翻译软件。选中文本 → 鼠标旁边出现翻译按钮 → 点击查看译文。
按住 ⌘ 选词 → AI 翻译（OpenAI 兼容：OpenAI / Claude / DeepSeek）；不按 ⌘ → Apple Translation（本地、免费）。

## 设计文档

见 [`docs/superpowers/specs/2026-08-12-flick-design.md`](docs/superpowers/specs/2026-08-12-flick-design.md)。

## 构建

```bash
swift build -c release
scripts/build-app.sh
open .build/Flick.app
```

需要 macOS 14+ 和辅助功能权限（系统设置 → 隐私与安全 → 辅助功能）。

## 测试

```bash
swift test
```