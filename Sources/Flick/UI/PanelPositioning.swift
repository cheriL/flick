import CoreGraphics

enum PanelPositioning {
    /// Pick the frame of the display that should host a panel anchored at
    /// `cursor`.
    ///
    /// This exists because `origin(forPanel:near:on:)` *clamps* into the
    /// screen it's handed. Passing `NSScreen.main` unconditionally is wrong
    /// on a multi-display setup: `NSScreen.main` is the screen with the key
    /// window, and Flick is a menu-bar accessory that never becomes key, so
    /// it resolves to the primary (built-in) display no matter where the
    /// user is actually working. A selection made on a secondary display
    /// then gets clamped onto the primary one — the panel is ordered front
    /// correctly but drawn on a monitor the user isn't looking at, which
    /// reads as "the popup stopped working".
    ///
    /// Screens are in Cocoa coordinates (y up, origin at the bottom-left of
    /// the primary display), which is the same space `NSEvent.mouseLocation`
    /// and `NSWindow.setFrame` use, so no conversion is needed.
    static func screenFrame(for cursor: CGPoint,
                            in screens: [CGRect],
                            fallback: CGRect) -> CGRect {
        if let hit = screens.first(where: { $0.contains(cursor) }) { return hit }
        // The cursor can sit in a dead zone that belongs to no screen when
        // displays of different heights are stacked/offset (this user's
        // external display is 1920×1080 at x=-408, above a 1512×982
        // built-in, which leaves such gaps). Snapping to the *nearest*
        // screen keeps the panel next to the cursor; falling back to the
        // primary would reintroduce the cross-monitor jump.
        let nearest = screens.min {
            squaredDistance(from: cursor, to: $0) < squaredDistance(from: cursor, to: $1)
        }
        return nearest ?? fallback
    }

    /// Squared distance from `point` to the closest point of `rect` (zero if
    /// inside). Squared to avoid a needless `sqrt` — only ordering matters.
    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        let dx = point.x - clampedX
        let dy = point.y - clampedY
        return dx * dx + dy * dy
    }

    /// Compute the top-left origin for a panel placed near `cursor` on `screen`.
    /// Tries lower-right first; flips horizontally if the panel would overflow right,
    /// vertically if it would overflow bottom; clamps inside `screen` as a last resort.
    static func origin(forPanel size: CGSize,
                       near cursor: CGPoint,
                       on screen: CGRect,
                       offset: CGFloat = 12) -> CGPoint {
        // Try lower-right.
        var x = cursor.x + offset
        var y = cursor.y + offset

        // Flip horizontally if it would overflow right.
        if x + size.width > screen.maxX {
            x = cursor.x - size.width - offset
        }
        // Flip vertically if it would overflow bottom.
        if y + size.height > screen.maxY {
            y = cursor.y - size.height - offset
        }

        // Clamp inside screen.
        x = min(max(x, screen.minX), screen.maxX - size.width)
        y = min(max(y, screen.minY), screen.maxY - size.height)

        return CGPoint(x: x, y: y)
    }
}