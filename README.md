<div align="center">
  <img src="Resources/app-icon.png" width="138" />
  <h1>Flick</h1>
  <p><b>Select text anywhere, translate in one click.</b></p>
  <p>English · <a href="README.zh-CN.md">中文</a></p>
  <a href="LICENSE"><img alt="license" src="https://img.shields.io/badge/license-GPL%20v3-blue.svg?style=flat-square"></a>
  <a href="https://www.apple.com/macos/"><img alt="platform" src="https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey.svg?style=flat-square"></a>
  <a href="https://github.com/cheriL/flick/releases"><img alt="release" src="https://img.shields.io/github/v/release/cheriL/flick.svg?style=flat-square&include_prereleases"></a>
</div>

## Requirements

- macOS 26+
- Accessibility permission (System Settings → Privacy & Security → Accessibility)
- Chrome (optional): enable View → Developer → Allow JavaScript from Apple Events, then accept the prompt on first use

## Installation

If macOS reports Flick as damaged on first launch (the app is unsigned), run:

```bash
/usr/bin/xattr -cr /Applications/Flick.app
```

## License

[GPL-3.0](LICENSE)
