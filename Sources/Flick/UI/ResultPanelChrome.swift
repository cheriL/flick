import SwiftUI
import AppKit

/// A SwiftUI representable producing a single white `NSView` with rounded
/// corners, a hairline border, and a soft all-around drop shadow, used as
/// the bottom layer of the result panel. The SwiftUI content sits on top
/// via a separate `NSHostingView`.
struct PanelChromeView: NSViewRepresentable {
    let cornerRadius: CGFloat = 14

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        guard let layer = v.layer else { return v }
        layer.backgroundColor = NSColor.white.cgColor
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = false
        layer.borderColor = NSColor.black.withAlphaComponent(0.08).cgColor
        layer.borderWidth = 1
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.10
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 20
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        guard let layer = v.layer else { return }
        // Keep the shadow path locked to the rounded shape so the shadow
        // follows the corner radius even after layout changes.
        layer.shadowPath = NSBezierPath(
            roundedRect: layer.bounds,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        ).cgPath
    }
}