# Flick

One-click translation for selected text on macOS.

[![license](https://img.shields.io/badge/license-GPL%20v3-blue.svg?style=flat-square)](LICENSE)
[![platform](https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey.svg?style=flat-square)](https://www.apple.com/macos/)
[![release](https://img.shields.io/github/v/release/cheriL/flick.svg?style=flat-square&include_prereleases)](https://github.com/cheriL/flick/releases)

[English](README.md) · [中文](README.zh-CN.md)

## Requirements

- macOS 26+
- Accessibility permission (System Settings → Privacy & Security → Accessibility)

### Chrome (optional)

Chrome reads the selection via AppleScript. One-time setup: Chrome menu **View → Developer → Allow JavaScript from Apple Events**, then accept the Automation prompt on first use. Chrome's built-in PDF viewer is not supported. Without this setting Flick falls back to the legacy mode (launch Chrome from the menu-bar button).

## Installation

If macOS reports Flick as damaged on first launch (the app is unsigned), run:

```bash
/usr/bin/xattr -cr /Applications/Flick.app
```

## License

[GPL-3.0](LICENSE)
