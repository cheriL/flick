import AppKit

/// Shared show/hide presentation for the popup panels: quick fade, scaled
/// from the frame's top-left anchor (the cursor / status-item corner the
/// panel grows out of). Final geometry and visibility are applied
/// synchronously — only the presentation animates, so callers can rely on
/// `frame`/`isVisible` semantics right after the call.
enum PanelTransitions {
    private static let appearDuration: TimeInterval = 0.15
    private static let dismissDuration: TimeInterval = 0.12
    private static let initialScale: CGFloat = 0.96

    static func present(_ panel: NSPanel, frame: NSRect, order: (() -> Void)? = nil) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(frame, display: true)
            panel.alphaValue = 1
            if let order { order() } else { panel.orderFrontRegardless() }
            return
        }
        let start = NSRect(
            origin: frame.origin,
            size: NSSize(width: frame.size.width * initialScale,
                         height: frame.size.height * initialScale)
        )
        panel.setFrame(start, display: true)
        panel.alphaValue = 0
        if let order { order() } else { panel.orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = appearDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    /// Fade out, then order out. `isValid` gates the final orderOut so a panel
    /// re-shown mid-fade isn't hidden by a stale completion.
    static func dismissAnimated(_ panel: NSPanel, isValid: @escaping () -> Bool) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = dismissDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            if isValid() { panel.orderOut(nil) }
        })
    }
}
