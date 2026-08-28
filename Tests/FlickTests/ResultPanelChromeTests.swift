import Testing
import AppKit
@testable import Flick

@Suite @MainActor final class ResultPanelChromeTests {

    /// Driving `viewDidChangeEffectiveAppearance` directly is the only
    /// reliable way to flip the chrome's appearance in a test — AppKit
    /// doesn't fire the notification just because you set
    /// `view.appearance`. Forcing it through the public lifecycle hook
    /// also exercises the path the production code uses.
    private func flipAppearance(of view: NSView, to appearance: NSAppearance) {
        view.appearance = appearance
        view.viewDidChangeEffectiveAppearance()
    }

    /// Force-unwrap the built-in Aqua / DarkAqua appearances. They are
    /// guaranteed to exist as long as macOS ships, and the test would
    /// be useless without them.
    private func light() -> NSAppearance { NSAppearance(named: .aqua)! }
    private func dark() -> NSAppearance { NSAppearance(named: .darkAqua)! }

    private func makeChrome() -> NSView {
        // `PanelChromeView` is the SwiftUI representable; we can
        // instantiate it but the actual view returned by `makeNSView`
        // is `AdaptiveChromeView`. We construct that directly because
        // it's the class that owns the appearance-driven repaint.
        let v = AdaptiveChromeView(frame: NSRect(x: 0, y: 0, width: 360, height: 140))
        // Initial paint under whatever appearance the test process has
        // — we don't care about the first paint, just the next two.
        v.layout()
        return v
    }

    private func red(_ cg: CGColor?) -> CGFloat {
        guard let c = cg?.components, c.count >= 1 else { return -1 }
        return c[0]
    }

    @Test func chromeIsWhiteInLightMode() {
        let view = makeChrome()
        flipAppearance(of: view, to: light())
        let r = red(view.layer?.backgroundColor)
        #expect(r > 0.95,
                "chrome background should be near-white in light mode, got red=\(r)")
    }

    @Test func chromeIsDarkInDarkMode() {
        let view = makeChrome()
        flipAppearance(of: view, to: dark())
        let r = red(view.layer?.backgroundColor)
        #expect(r < 0.25,
                "chrome background should be near-black in dark mode, got red=\(r)")
    }

    @Test func chromeBorderInvertsWithBackground() {
        let view = makeChrome()

        flipAppearance(of: view, to: light())
        let lightBorder = view.layer?.borderColor
        let lightAlpha = lightBorder?.alpha ?? -1
        // Light mode: black hairline. RGB should be near-zero.
        let lightR = red(lightBorder)
        #expect(lightR < 0.1, "light border should be black-ish, got r=\(lightR)")
        #expect(lightAlpha > 0 && lightAlpha < 0.2,
                "light border alpha should be subtle, got a=\(lightAlpha)")

        flipAppearance(of: view, to: dark())
        let darkBorder = view.layer?.borderColor
        let darkR = red(darkBorder)
        let darkAlpha = darkBorder?.alpha ?? -1
        // Dark mode: white hairline. RGB should be near-one.
        #expect(darkR > 0.9, "dark border should be white-ish, got r=\(darkR)")
        #expect(darkAlpha > 0 && darkAlpha < 0.2,
                "dark border alpha should be subtle, got a=\(darkAlpha)")
    }

    @Test func chromeShadowFadesInDarkMode() {
        let view = makeChrome()
        flipAppearance(of: view, to: light())
        let lightOpacity = view.layer?.shadowOpacity ?? -1
        #expect(lightOpacity > 0.05, "light mode should keep a soft shadow, got opacity=\(lightOpacity)")

        flipAppearance(of: view, to: dark())
        let darkOpacity = view.layer?.shadowOpacity ?? -1
        #expect(darkOpacity == 0,
                "dark mode should drop the shadow (the dark panel is already distinct on a dark desktop), got opacity=\(darkOpacity)")
    }
}