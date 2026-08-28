import SwiftUI
import AppKit

/// A SwiftUI representable producing a single rounded panel backing for
/// the result window: white in light mode, dark gray in dark mode, with
/// a hairline border (black 8% on light, white 10% on dark) and a soft
/// drop shadow that fades out in dark mode (the dark panel is already
/// distinct against a dark desktop, so a shadow adds no depth).
///
/// The SwiftUI content sits on top via a separate `NSHostingView` —
/// see `PanelContainerView` in `FloatingPanelController.swift`.
///
/// Adaptive behavior comes from `AdaptiveChromeView` — a small layer-
/// backed `NSView` subclass that re-runs `applyAppearance()` on
/// `viewDidChangeEffectiveAppearance`. We can't just rely on
/// `updateNSView` for this because SwiftUI does not re-evaluate
/// `NSViewRepresentable` purely because the host's effective appearance
/// flipped.
struct PanelChromeView: NSViewRepresentable {
    let cornerRadius: CGFloat = 14

    func makeNSView(context: Context) -> NSView {
        let v = AdaptiveChromeView()
        v.cornerRadius = cornerRadius
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        guard let adaptive = v as? AdaptiveChromeView else { return }
        adaptive.cornerRadius = cornerRadius
        adaptive.applyAppearance()
    }
}

/// Layer-backed `NSView` that paints its layer's background, border,
/// and shadow from colors resolved against the *current* effective
/// appearance. When the system appearance flips (or the view moves
/// between windows with different appearances), AppKit calls
/// `viewDidChangeEffectiveAppearance` and we repaint.
final class AdaptiveChromeView: NSView {
    /// Corner radius of the panel. Setter triggers an appearance
    /// refresh so the shadow path stays in sync.
    var cornerRadius: CGFloat = 14 {
        didSet {
            guard oldValue != cornerRadius else { return }
            applyAppearance()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        applyAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    override func layout() {
        super.layout()
        // Shadow path has to track the rounded shape after layout;
        // colors are unaffected by bounds so we don't re-apply them.
        applyShadowPath()
    }

    // MARK: - Internal

    /// Repaint background / border / shadow for the current appearance.
    /// Visible to tests via `// MARK: - Test hooks` so they can drive the
    /// chrome from a controlled appearance without relying on
    /// `viewDidChangeEffectiveAppearance` being fired by AppKit.
    func applyAppearance() {
        guard let layer else { return }

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        layer.cornerRadius = cornerRadius
        layer.borderWidth = 1
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 20

        if isDark {
            layer.backgroundColor = NSColor(white: 0.14, alpha: 1).cgColor
            layer.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
            layer.shadowOpacity = 0
        } else {
            layer.backgroundColor = NSColor.white.cgColor
            layer.borderColor = NSColor.black.withAlphaComponent(0.08).cgColor
            layer.shadowOpacity = 0.10
        }

        applyShadowPath()
    }

    private func applyShadowPath() {
        guard let layer else { return }
        layer.shadowPath = NSBezierPath(
            roundedRect: layer.bounds,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        ).cgPath
    }
}