# Flick UI Polish — Design Spec

**Date:** 2026-08-18
**Branch:** master
**Status:** Draft — pending user review

## Goal

Polish Flick's visible UI surfaces so the app feels intentional and native, not generic:

1. Replace the trigger button's text labels (`译` / `AI`) with SF Symbol icons that
   visually communicate the two translation modes.
2. Give the floating result panel a proper macOS-native look — rounded corners,
   translucent material background, refined shadow, and per-state visual cues.

Out of scope: menu-bar icon, menu layout, settings window, behavior changes
(selection tracking, modifier polling, panel positioning, retry logic).

## Decisions

| Surface | Decision |
|---|---|
| Menu bar icon | **Unchanged.** Stays `character.bubble`. |
| Trigger button — normal mode | `Image(systemName: "character.bubble")` (line). |
| Trigger button — AI mode | `Image(systemName: "sparkles")`. |
| Result panel — background | `.regularMaterial` via `NSVisualEffectView`. |
| Result panel — corner radius | `14pt`. |
| Result panel — shadow | Two-layer custom `NSShadow` — soft 12pt blur @ 0.18 alpha + crisp 2pt @ 0.08, both offset `y: 4`. |
| Result panel — AI accent bar | 3pt-tall gradient strip at top, shown **only when `isAI == true`**. |
| Result panel — state icons | `sparkles` for AI loading, plain `ProgressView` for normal loading, `xmark.circle` for failure. |

## Architecture

### Files

- **Modify** `Sources/Flick/UI/TriggerButtonView.swift`
  - Replace `Text(isAI ? "AI" : "译")` with `Image(systemName: isAI ? "sparkles" : "character.bubble")`.
  - Keep the rest of the view (frame, material, border, shadow, help text) unchanged.

- **Modify** `Sources/Flick/UI/ResultWindowView.swift`
  - Wrap the existing `VStack` content in a new `ResultPanelChrome` view that
    contributes the material background, shadow, and optional AI accent bar.
  - Add a `isAI: Bool` parameter threaded through from `FloatingPanelController`.
  - Replace `ProgressView` in the loading branch with the icon set described below.
  - Replace failure's plain red text with `xmark.circle` icon + text layout.

- **Modify** `Sources/Flick/UI/FloatingPanelController.swift`
  - Replace the `NSPanel` content view with a host that uses `NSVisualEffectView`
    as the backing layer for the material, masked to `cornerRadius = 14`.
  - Drop `panel.hasShadow = true` (we install a custom `NSShadow` on the chrome
    view instead).
  - Add `isAI: Bool` parameter to `showResult(original:state:at:onRetry:isAI:)`
    and forward it to `ResultWindowView`.
  - Pass `isAI` through the existing `showTrigger` chain: `showTrigger(...)
    → TriggerButtonView(isAI:)` already exists; no signature change there, but
    the same `isAI` value should flow into the result view when the tap fires.

### New file

- **Create** `Sources/Flick/UI/ResultPanelChrome.swift`
  - Houses the `NSViewRepresentable` that produces the chrome view, and a
    SwiftUI wrapper view (`ResultPanelChrome`) that lays out the AI accent bar
    + content with the correct padding/clipping.

### Unchanged files

- `Sources/Flick/UI/PanelPositioning.swift` — positioning math unchanged; the
  panel rect's outer size grows by 0–2pt from the rounded corners, well within
  existing tolerance.
- `Sources/Flick/MenuBar/MenuBarContent.swift`, `Sources/Flick/App.swift` — no
  changes.

## Detailed Design

### Trigger button

```swift
struct TriggerButtonView: View {
    let isAI: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: isAI ? "sparkles" : "character.bubble")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.regularMaterial))
                .overlay(
                    Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .help(isAI ? "AI 翻译" : "普通翻译")
    }
}
```

Rationale for icon size: SF Symbols at 14pt in a 28pt circle match the visual
weight of the old 13pt rounded "译"/"AI" text.

### Result panel — chrome

`NSVisualEffectView` is the standard macOS primitive for `.regularMaterial`
with custom shape. SwiftUI's `.background(.regularMaterial)` only works on
standard NSWindow content views — it does NOT work on `NSPanel` because
`NSPanel`'s content view is a plain `NSView`, not an `NSVisualEffectView`.
Therefore we go AppKit-side for the chrome and SwiftUI-side for the content.

```swift
struct PanelChromeView: NSViewRepresentable {
    let isAI: Bool
    let cornerRadius: CGFloat = 14

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .regular
        v.state = .active
        v.blendingMode = .behindWindow
        v.wantsLayer = true
        v.layer?.cornerRadius = cornerRadius
        v.layer?.masksToBounds = false  // shadow drawn outside bounds
        v.shadow = makeShadow()
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.shadow = makeShadow()
        // isAI only affects the SwiftUI accent-bar overlay; the chrome itself
        // is identical for AI and non-AI panels.
    }

    private func makeShadow() -> NSShadow {
        let s = NSShadow()
        s.shadowBlurRadius = 12
        s.shadowOffset = NSSize(width: 0, height: 4)
        s.shadowColor = NSColor.black.withAlphaComponent(0.18)
        return s
    }
}
```

The SwiftUI content (original text, divider, translation, failure UI) is
hosted in an `NSHostingView` placed **on top of** the `NSVisualEffectView`
inside a parent `NSView`. Order:

```
NSView (parent, transparent, sized to panel)
├── NSVisualEffectView (chrome: material, rounded corners, shadow)
└── NSHostingView (SwiftUI content: accent bar + text + buttons)
```

The accent bar lives in the SwiftUI overlay so it can react to `isAI` via
the parent's `State`/`let`, not via AppKit.

### Result panel — content

```swift
struct ResultWindowView: View {
    let original: String
    let state: ResultState
    let isAI: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // AI accent bar — 3pt gradient, only when AI mode.
            if isAI {
                LinearGradient(
                    colors: [.purple, .blue, .green],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 3)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(original)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Divider().opacity(0.4)

                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(width: 360)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            HStack(spacing: 8) {
                if isAI {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundStyle(.purple)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(isAI ? "AI 翻译中…" : "翻译中…")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        case .success(let text):
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .failure(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 6) {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                    Button("重试", action: onRetry)
                        .controlSize(.small)
                }
            }
        }
    }
}
```

### `FloatingPanelController` integration

```swift
private final class PanelContainerView: NSView {
    let visualEffect = NSVisualEffectView()
    let host: NSHostingView<ResultWindowView>

    init(rootView: ResultWindowView) {
        self.host = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        addSubview(visualEffect)
        addSubview(host)
        // pin visualEffect + host to self.edges with .notRight/.notBottom for shadow room
    }
    // ...autoresizing masks + frame layout...
}

func showResult(original: String, state: ResultState, at cursor: CGPoint,
                isAI: Bool, onRetry: @escaping () -> Void) {
    let size = CGSize(width: 360, height: 140)
    let screen = NSScreen.main?.frame ?? .zero
    let origin = PanelPositioning.origin(forPanel: size, near: cursor, on: screen)

    resultPanel.setFrame(NSRect(origin: origin, size: size), display: true)

    let root = ResultWindowView(original: original, state: state,
                                isAI: isAI, onRetry: onRetry)
    let container = PanelContainerView(rootView: root)
    container.frame = resultPanel.contentView!.bounds
    container.autoresizingMask = [.width, .height]
    resultPanel.contentView = container
    resultPanel.hasShadow = false  // shadow lives on the visualEffect subview

    resultPanel.orderFrontRegardless()
    triggerPanel.orderOut(nil)
    installMonitors()
}
```

Panel height changes from 120 → 140 to give the AI accent bar + new padding
some breathing room. `PanelPositioningTests` will need a tolerance bump or
its expected heights updated — see Testing below.

The trigger panel keeps `panel.hasShadow = true` and its current borderless
setup; the trigger button's existing 4pt shadow inside `TriggerButtonView`
is sufficient.

## Behavior

No behavior changes. Selection polling, ⌘ toggle, consumption suppression,
panel positioning math, retry logic, ESC dismiss, outside-click dismiss —
none change.

The only new signal threaded through is `isAI: Bool`, which `MenuBarController`
already computes at the selection point and currently passes only to the
trigger button. We extend the same value to the result view via the
existing `runTranslation(text:at:isAI:)` closure chain.

## Edge Cases

- **Long original text.** `.lineLimit(3)` truncates with `…`. Unchanged.
- **Long translation.** `fixedSize(horizontal: false, vertical: true)` lets
  the text wrap; panel height grows within `resultPanel`'s `.resizable` mask.
- **Dark mode.** `NSVisualEffectView.material = .regular` automatically picks
  the system-appropriate light/dark variant. SF Symbol colors use
  `.purple`/`.red` semantic styles that adapt.
- **Multiple spaces / full-screen apps.** `panel.collectionBehavior = [.fullScreenAuxiliary]`
  already keeps the panel visible. Unchanged.
- **macOS 14 floor.** `NSVisualEffectView` and SF Symbols are available on
  macOS 14. No new availability gates required.

## Testing

### Unit tests to update

- `Tests/FlickTests/PanelPositioningTests.swift`
  - Expected heights for `showResult` change from 120 → 140. Update fixture.
  - All other positioning assertions remain valid.

- New file `Tests/FlickTests/ResultWindowViewTests.swift`
  - Snapshot-free, lightweight: assert the view contains the right SF Symbol
    name for each `(isAI, state)` combination, and that the AI accent bar is
    present only when `isAI == true`.
  - Approach: construct the view in a `NSHostingView`, walk the view tree,
    look for `Image` views whose `systemName` matches expectation.

### Manual test plan

1. **Trigger button — normal**: select text in TextEdit. 28pt circle appears
   next to cursor with `character.bubble` line icon. Tap → translation runs.
2. **Trigger button — AI**: hold ⌘, select text. Same circle, now with
   `sparkles` icon. Tap → AI translation runs.
3. **Result panel — normal success**: 14pt rounded corners, `.regularMaterial`
   background, visible shadow, translation text readable, copy works.
4. **Result panel — AI success**: same plus 3pt gradient bar at panel top.
5. **Result panel — loading AI**: `sparkles` icon + "AI 翻译中…" text.
6. **Result panel — loading normal**: `ProgressView` + "翻译中…" text.
7. **Result panel — failure**: `xmark.circle` icon, red text, retry button.
8. **Dark mode**: toggle macOS appearance to dark; all three states still
   readable, material picks dark variant automatically.
9. **Dismiss**: ESC and outside-click still dismiss the panel (no regression).
10. **Positioning**: trigger and result panels appear next to cursor; long
    translations don't push the panel off-screen.

## Risks

| Risk | Mitigation |
|---|---|
| `NSVisualEffectView` doesn't render material correctly inside a borderless `NSPanel` | Fallback: use plain `NSView` with `backgroundColor = NSColor(white: 1, alpha: 0.85)` for light mode and `0.15` for dark, plus `cornerRadius = 14`. Detected via manual test #3. |
| Custom shadow doesn't appear | `hasShadow = false` on the panel is required; shadow must be on the `NSVisualEffectView.layer.shadow` (or via `NSShadow` set on the view). Test #3 covers this. |
| AI accent bar clips at corners | Gradient is inside the `VStack`, which sits inside the panel's content area (not the rounded chrome layer). `VStack` content is clipped to its own bounds; rounded corners are on the visualEffect view beneath. Visually clean. |
| Positioning test fixtures break with new 140pt default height | Updated in `PanelPositioningTests`. Single-line edit. |