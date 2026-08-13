import CoreGraphics

enum PanelPositioning {
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