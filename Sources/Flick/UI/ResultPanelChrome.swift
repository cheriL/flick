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
        v.material = .appearanceBased
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