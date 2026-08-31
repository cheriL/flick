import CoreGraphics

enum PanelPositioning {
    /// Pick the frame of the display that should host a panel anchored at `cursor`.
    ///
    /// `NSScreen.main` is wrong here: it's the screen with the key window, and Flick is a
    /// menu-bar accessory that never becomes key, so it always resolves to the primary display.
    /// A panel anchored on a secondary display would clamp onto the primary one.
    ///
    /// Screens are in Cocoa coordinates (y up, origin at the bottom-left of the primary display).
    static func screenFrame(for cursor: CGPoint,
                            in screens: [CGRect],
                            fallback: CGRect) -> CGRect {
        if let hit = screens.first(where: { $0.contains(cursor) }) { return hit }
        // Cursor may sit in a dead zone between differently-sized displays — snap to nearest.
        let nearest = screens.min {
            squaredDistance(from: cursor, to: $0) < squaredDistance(from: cursor, to: $1)
        }
        return nearest ?? fallback
    }

    /// Squared distance from `point` to the closest point of `rect` (zero if inside).
    /// Squared to skip a needless `sqrt` — only ordering matters.
    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        let dx = point.x - clampedX
        let dy = point.y - clampedY
        return dx * dx + dy * dy
    }

    /// Top-left origin for a panel near `cursor` on `screen`. Tries lower-right first;
    /// flips horizontally/vertically on overflow; clamps inside `screen` as a last resort.
    static func origin(forPanel size: CGSize,
                       near cursor: CGPoint,
                       on screen: CGRect,
                       offset: CGFloat = 12) -> CGPoint {
        var x = cursor.x + offset
        var y = cursor.y + offset

        if x + size.width > screen.maxX {
            x = cursor.x - size.width - offset
        }
        if y + size.height > screen.maxY {
            y = cursor.y - size.height - offset
        }

        x = min(max(x, screen.minX), screen.maxX - size.width)
        y = min(max(y, screen.minY), screen.maxY - size.height)

        return CGPoint(x: x, y: y)
    }
}