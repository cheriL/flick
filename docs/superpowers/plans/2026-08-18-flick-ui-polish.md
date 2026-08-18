# Flick UI Polish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the trigger button's text labels with SF Symbol icons and give the floating result panel a proper macOS-native look (rounded corners, material background, refined shadow, per-state icons).

**Architecture:** Two surgical changes to the UI layer. Trigger button is a one-file swap (text → SF Symbol `Image`). Result panel gets a new `NSViewRepresentable` chrome that hosts `NSVisualEffectView` for the material + custom shadow, with the existing SwiftUI `ResultWindowView` content layered on top and extended with an `isAI` parameter for accent bar + per-state icon selection. The `isAI` value flows through `MenuBarController` → `FloatingPanelController.showResult` → `ResultWindowView`.

**Tech Stack:** SwiftUI, AppKit (`NSVisualEffectView`, `NSShadow`, `NSPanel`), SF Symbols. macOS 14+ baseline.

## Global Constraints

- macOS floor: 14.0 (per `Package.swift` `platforms: [.macOS(.v14)]`). No new availability gates.
- SF Symbols used: `character.bubble` (line), `sparkles`, `xmark.circle`. All available since macOS 11.
- Result panel height: bump default from 120 → 140 to accommodate AI accent bar + new padding.
- `NSVisualEffectView.material = .regular` adapts to dark/light mode automatically.
- All behavior preserved: selection polling, ⌘ toggle, consumption suppression, panel positioning, retry logic, ESC dismiss, outside-click dismiss.
- Tests via Swift Testing (`@Test`, `#expect`). No XCTest.

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `Sources/Flick/UI/TriggerButtonView.swift` | Modify | Replace `Text` with `Image(systemName:)`; keep frame/material/border/shadow. |
| `Sources/Flick/UI/ResultWindowView.swift` | Modify | Add `isAI: Bool` param; AI accent bar at top; state icons in loading/failure branches. |
| `Sources/Flick/UI/ResultPanelChrome.swift` | **Create** | `NSViewRepresentable` producing an `NSVisualEffectView` chrome with rounded corners + custom `NSShadow`. |
| `Sources/Flick/UI/FloatingPanelController.swift` | Modify | Replace plain `NSHostingView` content with `PanelContainerView` (visualEffect + hosting stacked); thread `isAI` through `showResult`. |
| `Sources/Flick/MenuBar/MenuBarController.swift` | Modify | Pass `isAI` to `panel.showResult(...)` in all 3 call sites (loading / success / failure). |
| `Tests/FlickTests/ResultWindowViewTests.swift` | **Create** | Verify icon names, accent-bar presence by `isAI`, and retry wiring. |
| `Tests/FlickTests/TriggerButtonViewTests.swift` | **Create** | Verify icon name swaps with `isAI`. |

---

### Task 1: Trigger button icon swap

**Files:**
- Modify: `Sources/Flick/UI/TriggerButtonView.swift`
- Test: `Tests/FlickTests/TriggerButtonViewTests.swift`

**Interfaces:**
- Consumes: `isAI: Bool`, `onTap: () -> Void` (existing).
- Produces: same — no signature change.

- [ ] **Step 1: Write the failing test**

Create `Tests/FlickTests/TriggerButtonViewTests.swift`:

```swift
import SwiftUI
import Testing
@testable import Flick

@Suite @MainActor final class TriggerButtonViewTests {

    @Test func normalModeUsesCharacterBubble() {
        let view = TriggerButtonView(isAI: false, onTap: {})
        let names = collectSystemImageNames(view)
        #expect(names.contains("character.bubble"))
        #expect(!names.contains("sparkles"))
    }

    @Test func aiModeUsesSparkles() {
        let view = TriggerButtonView(isAI: true, onTap: {})
        let names = collectSystemImageNames(view)
        #expect(names.contains("sparkles"))
        #expect(!names.contains("character.bubble"))
    }

    /// Render the SwiftUI view tree and collect every `Image`'s
    /// `systemName` so we can assert on icon identity without a snapshot.
    private func collectSystemImageNames<V: View>(_ view: V) -> [String] {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let _ = hosting.subviews  // force layout
        return findSystemImages(in: hosting)
    }

    private func findSystemImages(in view: NSView) -> [String] {
        var names: [String] = []
        for sub in view.subviews {
            if let img = sub as? NSImageView, let name = img.image?.accessibilityIdentifier {
                names.append(name)
            }
            names.append(contentsOf: findSystemImages(in: sub))
        }
        return names
    }
}
```

Note: SF Symbols rendered by SwiftUI end up as `NSImageView` with the symbol name accessible. If `accessibilityIdentifier` is empty in practice, fall back to asserting on `image` name pattern — covered in step 4 verification.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TriggerButtonViewTests`
Expected: FAIL — `TriggerButtonView` still uses `Text("译"/"AI")`, so neither `character.bubble` nor `sparkles` is present.

- [ ] **Step 3: Implement the icon swap**

In `Sources/Flick/UI/TriggerButtonView.swift`, replace the `Text` inside the `Button` action:

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
                .background(
                    Circle().fill(.regularMaterial)
                )
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

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TriggerButtonViewTests`
Expected: PASS — both tests find their expected system image name.

If `accessibilityIdentifier` is nil, swap the assertion strategy: render the view with a known size, walk subviews, find `NSImageView`s, and assert each one's `image.name` matches. Document the chosen key in a comment.

- [ ] **Step 5: Commit**

```bash
git add Sources/Flick/UI/TriggerButtonView.swift Tests/FlickTests/TriggerButtonViewTests.swift
git commit -m "feat: swap trigger button text for SF Symbol icons"
```

---

### Task 2: Result window content — `isAI` + accent bar + state icons

**Files:**
- Modify: `Sources/Flick/UI/ResultWindowView.swift`
- Test: `Tests/FlickTests/ResultWindowViewTests.swift`

**Interfaces:**
- Consumes: `original: String`, `state: ResultState`, `onRetry: () -> Void` (existing), new `isAI: Bool`.
- Produces: same — only adds the parameter.

- [ ] **Step 1: Write the failing tests**

Create `Tests/FlickTests/ResultWindowViewTests.swift`:

```swift
import SwiftUI
import AppKit
import Testing
@testable import Flick

@Suite @MainActor final class ResultWindowViewTests {

    @Test func aiLoadingUsesSparklesIconAndLabel() {
        let view = ResultWindowView(original: "hi", state: .loading, isAI: true, onRetry: {})
        let names = collectSystemImageNames(view)
        #expect(names.contains("sparkles"))
    }

    @Test func normalLoadingHasNoSparklesIcon() {
        let view = ResultWindowView(original: "hi", state: .loading, isAI: false, onRetry: {})
        let names = collectSystemImageNames(view)
        #expect(!names.contains("sparkles"))
    }

    @Test func failureUsesXmarkCircle() {
        let view = ResultWindowView(original: "hi", state: .failure("boom"), isAI: false, onRetry: {})
        let names = collectSystemImageNames(view)
        #expect(names.contains("xmark.circle"))
    }

    @Test func retryButtonWiresThrough() {
        var tapped = 0
        let view = ResultWindowView(original: "hi", state: .failure("boom"), isAI: false) {
            tapped += 1
        }
        // Trigger the retry by finding the NSButton titled "重试".
        let button = findButton(titled: "重试", in: NSHostingView(rootView: view))
        button?.performClick(nil)
        #expect(tapped == 1)
    }

    // Reuses helper from TriggerButtonViewTests via shared file or copy.
    private func collectSystemImageNames<V: View>(_ view: V) -> [String] {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        let _ = hosting.subviews
        return findSystemImages(in: hosting)
    }

    private func findSystemImages(in view: NSView) -> [String] {
        var names: [String] = []
        for sub in view.subviews {
            if let img = sub as? NSImageView, let name = img.image?.accessibilityIdentifier {
                names.append(name)
            }
            names.append(contentsOf: findSystemImages(in: sub))
        }
        return names
    }

    private func findButton(titled title: String, in view: NSView) -> NSButton? {
        for sub in view.subviews {
            if let btn = sub as? NSButton, btn.title == title { return btn }
            if let found = findButton(titled: title, in: sub) { return found }
        }
        return nil
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ResultWindowViewTests`
Expected: FAIL — `ResultWindowView` has no `isAI` parameter; signature doesn't match.

- [ ] **Step 3: Implement content changes**

In `Sources/Flick/UI/ResultWindowView.swift`:

```swift
import SwiftUI

enum ResultState: Equatable {
    case loading
    case success(String)
    case failure(String)
}

struct ResultWindowView: View {
    let original: String
    let state: ResultState
    let isAI: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ResultWindowViewTests`
Expected: PASS — all 4 tests find the expected icons / wire the retry button.

If `NSImageView.image.accessibilityIdentifier` is nil, fall back to `image.name()` or a custom mirror on the SwiftUI `Image` view. Update `collectSystemImageNames` accordingly and re-run.

- [ ] **Step 5: Commit**

```bash
git add Sources/Flick/UI/ResultWindowView.swift Tests/FlickTests/ResultWindowViewTests.swift
git commit -m "feat: AI accent bar + state icons in result panel"
```

---

### Task 3: Result panel chrome (`NSVisualEffectView` + custom shadow)

**Files:**
- Create: `Sources/Flick/UI/ResultPanelChrome.swift`

**Interfaces:**
- Consumes: nothing (the representable is self-contained).
- Produces: a `NSViewRepresentable` named `PanelChromeView`. Caller embeds it under the SwiftUI hosting view inside `FloatingPanelController`.

- [ ] **Step 1: Write the failing smoke test**

This AppKit bridging layer is hard to assert on in unit tests without an
`NSVisualEffectView` host. Add a minimal compile-only check that the type
exists and conforms to `NSViewRepresentable`. No file needed — the production
file's public API is the test.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift build`
Expected: FAIL — `ResultPanelChrome.swift` does not exist; `PanelChromeView` is undefined.

- [ ] **Step 3: Create the chrome**

Create `Sources/Flick/UI/ResultPanelChrome.swift`:

```swift
import SwiftUI
import AppKit

/// A SwiftUI representable producing a single `NSVisualEffectView` styled
/// for Flick's result panel: `.regular` material, 14pt rounded corners,
/// and a soft + crisp custom `NSShadow`.
///
/// Used by `FloatingPanelController` as the bottom layer of the result
/// panel's container view; the SwiftUI content sits on top via a separate
/// `NSHostingView`.
struct PanelChromeView: NSViewRepresentable {
    let cornerRadius: CGFloat = 14

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .regular
        v.state = .active
        v.blendingMode = .behindWindow
        v.wantsLayer = true
        v.layer?.cornerRadius = cornerRadius
        v.layer?.masksToBounds = false
        v.shadow = makeShadow()
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.shadow = makeShadow()
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

- [ ] **Step 4: Verify it builds**

Run: `swift build`
Expected: PASS — `PanelChromeView` compiles, no consumers yet.

- [ ] **Step 5: Commit**

```bash
git add Sources/Flick/UI/ResultPanelChrome.swift
git commit -m "feat: result panel chrome view (material + rounded + shadow)"
```

---

### Task 4: Wire chrome into `FloatingPanelController` and thread `isAI`

**Files:**
- Modify: `Sources/Flick/UI/FloatingPanelController.swift`
- Modify: `Sources/Flick/MenuBar/MenuBarController.swift`

**Interfaces:**
- `FloatingPanelController.showResult` gains `isAI: Bool` parameter.
- `MenuBarController` passes `isAI` (already in scope) into all 3 `panel.showResult` call sites.

- [ ] **Step 1: Update FloatingPanelController.swift**

Replace the result-panel section. Concretely:

1. Add `import AppKit` (already present).
2. Replace the contents of `showResult(original:state:at:onRetry:)` with a
   version that:
   - Takes a new `isAI: Bool` parameter.
   - Constructs a `PanelContainerView` that stacks `PanelChromeView` (via a
     small `NSHostingView`) under an `NSHostingView<ResultWindowView>`.
   - Sets `resultPanel.contentView = container`, `hasShadow = false`.
3. Update the result-panel's default size from `CGSize(width: 360, height: 120)`
   to `CGSize(width: 360, height: 140)`.
4. Add the private `PanelContainerView` class:

```swift
private final class PanelContainerView: NSView {
    let chrome: NSHostingView<PanelChromeView>
    let host: NSHostingView<ResultWindowView>

    init(rootView: ResultWindowView) {
        self.chrome = NSHostingView(rootView: PanelChromeView())
        self.host = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        addSubview(chrome)
        addSubview(host)
        chrome.translatesAutoresizingMaskIntoConstraints = false
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: trailingAnchor),
            chrome.topAnchor.constraint(equalTo: topAnchor),
            chrome.bottomAnchor.constraint(equalTo: bottomAnchor),
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
```

Final method signature:

```swift
func showResult(original: String, state: ResultState, at cursor: CGPoint,
                isAI: Bool, onRetry: @escaping () -> Void)
```

- [ ] **Step 2: Update MenuBarController.swift**

In `Sources/Flick/MenuBar/MenuBarController.swift`, add `isAI: isAI` to the
three `panel.showResult(original:state:at:onRetry:)` call sites inside
`runTranslation(text:at:isAI:)`. The `isAI` value is already in scope.

- [ ] **Step 3: Run the full test suite to verify nothing regressed**

Run: `swift test`
Expected: PASS — `TriggerButtonViewTests`, `ResultWindowViewTests`, and all
existing tests still green.

- [ ] **Step 4: Build & smoke-test manually**

Run: `./scripts/build-app.sh && open .build/Flick.app`

Manual checks (matching spec §"Manual test plan"):

1. Trigger button normal: `character.bubble` line icon.
2. Trigger button AI (⌘ held): `sparkles` icon.
3. Result panel success (normal): rounded corners, translucent material, refined shadow, no top bar.
4. Result panel success (AI): same + 3pt gradient bar at top.
5. Result panel loading AI: `sparkles` + "AI 翻译中…".
6. Result panel loading normal: `ProgressView` + "翻译中…".
7. Result panel failure: `xmark.circle` + red text + 重试 button.
8. ESC and outside-click still dismiss.

- [ ] **Step 5: Commit**

```bash
git add Sources/Flick/UI/FloatingPanelController.swift Sources/Flick/MenuBar/MenuBarController.swift
git commit -m "feat: wire chrome view + thread isAI through result panel"
```

---

## Self-Review

- **Spec coverage:** Trigger icon swap → Task 1. Result panel chrome / corner radius / material / shadow → Tasks 3+4. AI accent bar / state icons / `isAI` plumbing → Task 2 + Task 4. Manual test plan → Task 4.4. ✅
- **Placeholder scan:** No "TODO" / "TBD" / "implement later" in any step. ✅
- **Type consistency:** `ResultWindowView(isAI:onRetry:)` signature is referenced identically in Task 2 (definition), Task 4 (constructor in `PanelContainerView`), and `MenuBarController` (call site). ✅
- **Interface consistency:** `PanelChromeView` is defined in Task 3 and consumed only in Task 4. `PanelContainerView` is private to `FloatingPanelController` and not exported. ✅
- **Scope:** Single implementation cycle, ~5 files modified, 2 created. Focused. ✅