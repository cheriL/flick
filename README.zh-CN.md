# Flick

极简 macOS 菜单栏翻译软件。选中文本，鼠标旁出现翻译按钮，点击查看译文。

![license](https://img.shields.io/badge/license-GPL%20v3-blue.svg?style=flat-square)
![platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg?style=flat-square)
![release](https://img.shields.io/github/v/release/cheriL/flick.svg?style=flat-square&include_prereleases)

[English](README.md) · [中文](README.zh-CN.md)

## Features

- 选词 → Apple Translation（本地、免费）
- ⌘ + 选词 → AI 翻译（OpenAI）

## 环境要求

- macOS 14+
- 辅助功能权限（系统设置 → 隐私与安全 → 辅助功能）

## 快速开始

```bash
git clone https://github.com/cheriL/flick.git
cd flick
./scripts/build-app.sh
open .build/Flick.app
```

首次启动授予辅助功能权限。然后在任意应用内选中文本，鼠标旁会出现浮动按钮。按住 ⌘ 选词切换为 AI 翻译。API key 在 Settings → AI 中配置。

## 协议

[GPL-3.0](LICENSE)
