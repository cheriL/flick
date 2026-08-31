# Flick — Claude Code Guide

A minimal macOS menu-bar translator. Select text anywhere, a translate button
appears next to the cursor, click it to see the result. Text selection →
Apple Translation (on-device, free); ⌘ + selection → AI translation
(OpenAI-compatible API).

Target: **macOS 26+**, Swift 5 language mode (forced via `Package.swift`'s
`swift-tools-version: 6.2` + `swiftLanguageMode(.v5)`), SwiftPM only — no Xcode
project.
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

## Known pitfalls

These are real bugs / design constraints future work has hit. Refer to them
before chasing behaviour that has a known cause.

- **Multi-display anchoring.** Never use `NSScreen.main` to pick the
  panel's display rect. Flick is a menu-bar accessory and never becomes
  key, so `NSScreen.main` always resolves to the primary (built-in)
  display regardless of where the user is working. A panel anchored
  near a cursor on a secondary display will be **clamped onto the
  primary one** and rendered where the user isn't looking. Use
  `PanelPositioning.screenFrame(for:in:fallback:)` (it picks the screen
  containing the cursor and snaps to the nearest on dead zones).

- **WeChat, Feishu, and many Electron apps don't expose selection to
  Accessibility.** Their AX trees either skip text nodes entirely
  (Feishu has ~6 descendants, none text), or the focused element stays
  on the input box while the highlighted text lives in a sibling
  subtree AX never reaches (WeChat). No amount of tree walking fixes
  this — these apps don't follow macOS Accessibility conventions.
  **Flick does not translate inside these apps.** Selection-based
  translation requires an AX-visible frontmost app; if the user needs
  to translate WeChat/Feishu text, they should paste it into Chrome
  (which is AX-visible) or a different tool.

- **Chromium / Electron apps need `AXManualAccessibility`.** Apps built
  on Chromium only build their full accessibility tree when an
  assistive client asks. Setting `AXManualAccessibility = true` on
  their `AXUIElement` is the documented opt-in. Use it sparingly —
  it is sticky and asking once per process is enough.

- **`for _ in 0..<maxDepth` around a queue pop is a bug, not a depth
  limit.** It caps the number of *iterations* (and so nodes examined),
  not the depth. A child layer with hundreds of nodes will only be
  sampled and the rest dropped. Use a per-queued depth + explicit node
  budget; see `bfs(from:maxNodes:maxDepth:)` in
  `AXUIElement+Selection.swift` for the working version.

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
  Settings/                             # AISettingsView, AutoStart
  MenuBar/                              # MenuBarController, MenuBarContent,
                                         # MenuPanelController, SelectionToggleRow
                                         # MenuPanelController owns the NSStatusItem
                                         # popup panel (own NSPanel + frosted bg).
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

## Writing style: short & current

The user wants both commit messages and source comments to stay terse and
focused on what the code is *now*.

- **Commit messages:** conventional-commits subject line + at most one short
  body line. Don't enumerate files, list every fix, or write a changelog —
  `git diff` carries that detail. Skip `Tests:` / `Behaviour:` breakdowns.
- **Code comments:** explain *why* the current shape exists when it isn't
  obvious. Do **not** leave "ghost comments" that narrate past failures:
  no "previous versions tried X but…", no tombstones for deleted features,
  no post-mortems of approaches that didn't pan out. A one-line pointer
  to a spec or commit is fine when context is genuinely needed.

## When unsure

- If a change could affect TCC / Accessibility behavior, ask the user to
  re-grant permission and rebuild via the workflow above.
- If a change touches the OpenAI config storage, API surface, or the
  translation dispatch logic, mention it in the PR description (not the
  commit subject) so the user can review before merge.
- If a change adds a new build dependency, prefer keeping it to `brew`
  (which the script already uses) over adding a SwiftPM dependency.
