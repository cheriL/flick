# Flick

Minimal macOS menu-bar translator. Select text, a translate button appears next to the cursor, click to see the result.

![license](https://img.shields.io/badge/license-GPL%20v3-blue.svg?style=flat-square)
![platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg?style=flat-square)
![release](https://img.shields.io/github/v/release/cheriL/flick.svg?style=flat-square&include_prereleases)

[English](README.md) · [中文](README.zh-CN.md)

## Features

- select → Apple Translation (on-device, free)
- ⌘ + select → AI translation (OpenAI)

## Requirements

- macOS 14+
- Accessibility permission (System Settings → Privacy & Security → Accessibility)

## Quick Start

```bash
git clone https://github.com/cheriL/flick.git
cd flick
./scripts/build-app.sh
open .build/Flick.app
```

On first launch, grant Accessibility. Then select any text in any app — the floating button appears next to the cursor. Hold ⌘ while selecting for AI translation. Configure the API key in Settings → AI.

## License

[GPL-3.0](LICENSE)
