# Flick — Claude Code Guide

A minimal macOS menu-bar translator. Select text anywhere, a translate button
appears next to the cursor, click it to see the result. Text selection →
Apple Translation (on-device, free); ⌘ + selection → AI translation
(OpenAI-compatible API).

Target: **macOS 14+**, Swift 5.9, SwiftPM only — no Xcode project.
License: **GPL-3.0**. Repo: `https://github.com/cheriL/flick`.

## Build & run

- **Always use `./scripts/build-app.sh`** to produce `.build/Flick.app`. It
  copies the binary into `Contents/MacOS/`, drops `Resources/Info.plist`,
  and uses the Homebrew Swift toolchain (`/opt/homebrew/opt/swift/bin`) —
  the CommandLineTools-only `/usr/bin/swift` produces `SWBBuildService`
  dyld errors. Bare `swift build` does **not** produce a working app.
- `./scripts/build-dmg.sh` packages the `.app` into `.build/Flick-<version>.dmg`
  via `create-dmg` (`brew install create-dmg`). Tag-driven version comes
  from `git describe --tags --always --dirty`, falling back to `dev`.
- Do **not** run `swift test` with `/usr/bin/swift` — same `SWBBuildService`
  issue. Use the Homebrew toolchain on `PATH`.

## TCC restart workflow (Accessibility)

macOS caches TCC (Transparency, Consent, and Control) state per process. After
**any** rebuild that touches AX code paths (`Sources/Flick/Capture/*`,
`TextSelectionMonitor`, `AXUIElement+Selection`), the new binary will
inherit stale Accessibility state and behavior will look unchanged.

Before re-launching during debugging, **explicitly tell the user**:

> Please go to **System Settings → Privacy & Security → Accessibility**,
> remove Flick, then say "done." I won't start the app until then.

Do not auto-launch first. This is a recorded project constraint.

## Project layout

```
Sources/Flick/
  App.swift, AppDelegate.swift          # entry, lifecycle
  Capture/                              # text-selection via Accessibility API
    TextSelectionMonitor.swift
    AXUIElement+Selection.swift
  UI/                                   # SwiftUI surfaces
    FloatingPanelController.swift       # near-cursor panel host
    TriggerButtonView.swift             # palette-style translate button
    PanelPositioning.swift              # cursor-to-screen anchoring
    ResultWindowView.swift              # loading/success/failure content
    ResultPanelChrome.swift             # rounded white background + shadow
  Translation/
    Provider.swift                      # enum: apple / openai
    AppleTranslationService.swift       # on-device Translation framework
    OpenAICompatibleService.swift       # OpenAI-compatible HTTP API
    TranslationService.swift            # dispatch + coexistence
    HiddenTranslationHost.swift         # hidden Translate.app host (Apple)
  Settings/                             # AISettingsView, AutoStart
  MenuBar/                              # MenuBarController, MenuBarContent
  Config/ConfigStore.swift              # UserDefaults-backed config
  Models/AIConfig.swift                 # API key, base URL, model name
Tests/FlickTests/                       # swift-testing (NOT XCTest)
Resources/Info.plist
scripts/build-app.sh, build-dmg.sh, start-chrome.sh
.github/workflows/release.yml
```

## Hard constraints (do not violate without an explicit ask)

- **OpenAI-compatible API only.** Claude/Anthropic was removed earlier and
  must not be reintroduced as a provider. `OpenAICompatibleService` is the
  single AI translation entry point.
- **API key is stored in plain plist** (`AIConfig` via `ConfigStore`). The
  user has consciously accepted this trade-off; do not migrate to Keychain
  or add encryption unless asked.
- **ATS exception is intentional.** `NSAllowsArbitraryLoads = true` is in
  `Resources/Info.plist` so OpenAI-compatible endpoints over plain HTTP
  work. Don't tighten ATS without confirming the user is fine with breaking
  those endpoints.
- **Bundle ID is `com.cheriL.flick`.** Don't change it without coordinating
  with the user — it'll break the Accessibility TCC entry on existing
  installs.
- **No Xcode project.** `*.xcodeproj` is in `.gitignore` for a reason. The
  project is SwiftPM-only.
- **Bilingual README.** `README.md` (English) and `README.zh-CN.md` (Chinese)
  are kept structurally mirrored. Update both in the same commit. The
  Quick Start section was removed by user request — do not re-add it.

## Testing

- Test framework is **swift-testing** (`@Test`, `#expect`, `@Suite`), not
  XCTest. See `Tests/FlickTests/` for usage.
- For SwiftUI views, expose internal state via **computed-property test
  hooks** (e.g. `loadingIconName`, `failureIconName` on
  `ResultWindowView`) rather than walking the rendered view tree. The
  symbol name passed to `Image(systemName:)` is otherwise unobservable.
  Comment these hooks with `// MARK: - Test hooks` so their purpose is
  obvious to future readers.
- Tests run via `swift test` from the project root with the Homebrew
  toolchain on `PATH`.

## Release workflow

- `release.yml` triggers on `v*` tag push and `workflow_dispatch`. It runs
  `./scripts/build-app.sh`, `./scripts/build-dmg.sh`, then uploads the DMG
  to the GitHub release via `softprops/action-gh-release@v2`.
- DMG is **unsigned**. First launch will show a Gatekeeper warning; users
  right-click → Open. Notarization is deferred until the project has a
  Developer ID. Don't add signing/notarization steps without the
  associated secrets.
- Branch protection on `master` does **not** block tag pushes — you can
  verify the workflow with a throwaway tag (`v0.1.2-test`) without merging.

## Git conventions

- Conventional commits: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`.
  Scope is optional but useful (e.g. `fix(ui): result panel — white bg`).
- Branch from `master`. Keep unrelated changes on separate branches.
- Before committing, read your diff. The user has trimmed README
  contents several times — don't silently re-add material they've removed.

## When unsure

- If a change could affect TCC / Accessibility behavior, ask the user to
  re-grant permission and rebuild via the workflow above.
- If a change touches the OpenAI config storage, API surface, or the
  translation dispatch logic, surface the change in the commit message
  body so the user can review.
- If a change adds a new build dependency, prefer keeping it to `brew`
  (which the script already uses) over adding a SwiftPM dependency.
