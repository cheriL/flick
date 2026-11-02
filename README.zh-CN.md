# Flick

macOS 选词一键翻译。

[![license](https://img.shields.io/badge/license-GPL%20v3-blue.svg?style=flat-square)](LICENSE)
[![platform](https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey.svg?style=flat-square)](https://www.apple.com/macos/)
[![release](https://img.shields.io/github/v/release/cheriL/flick.svg?style=flat-square&include_prereleases)](https://github.com/cheriL/flick/releases)

[English](README.md) · [中文](README.zh-CN.md)

## 环境要求

- macOS 26+
- 辅助功能权限（系统设置 → 隐私与安全 → 辅助功能）

### Chrome（可选）

Chrome 通过 AppleScript 读取选区。一次性设置：Chrome 菜单 **查看 → 开发者 → 允许 Apple 事件中的 JavaScript**，首次取词时同意自动化授权弹窗。Chrome 内置 PDF 查看器不支持。不开启则回落旧模式（从菜单栏按钮启动 Chrome）。

## 安装

首次打开若提示「已损坏」（应用未签名），执行：

```bash
/usr/bin/xattr -cr /Applications/Flick.app
```

## 协议

[GPL-3.0](LICENSE)
