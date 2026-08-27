import Foundation
import CoreGraphics
import Testing
@testable import Flick

@Suite final class PanelPositioningTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func placesPanelToLowerRightWhenRoom() {
        let cursor = CGPoint(x: 500, y: 500)
        let size = CGSize(width: 200, height: 100)
        let origin = PanelPositioning.origin(forPanel: size, near: cursor, on: screen)
        // The brief's algorithm uses cursor + offset on both axes, so:
        // x = 500 + 12 = 512
        // y = 500 + 12 = 512 (NOT 600; brief comment "500 + 100" was misleading)
        #expect(origin.x == 512)
        #expect(origin.y == 512)
    }

    @Test func flipsToUpperLeftWhenNoRoomBelow() {
        let cursor = CGPoint(x: 500, y: 850) // only 50pt below cursor
        let size = CGSize(width: 200, height: 100)
        let origin = PanelPositioning.origin(forPanel: size, near: cursor, on: screen)
        // Vertical flip: 850 + 12 + 100 = 962 > 900, so y flips to 850 - 100 - 12 = 738.
        // Horizontal flip does NOT happen: 500 + 12 + 200 = 712, well within screen.width=1440,
        // so x stays at 512 (NOT 300; brief expected x=300 which assumed an unconditional flip).
        #expect(origin.x == 512)
        #expect(origin.y == 738)
    }

    @Test func flipsHorizontallyWhenNoRoomRight() {
        let cursor = CGPoint(x: 1300, y: 500) // only 140pt to right
        let size = CGSize(width: 200, height: 100)
        let origin = PanelPositioning.origin(forPanel: size, near: cursor, on: screen)
        // Horizontal flip: 1300 + 12 + 200 = 1512 > 1440, so x flips to 1300 - 200 - 12 = 1088.
        // Vertical flip does NOT happen: 500 + 12 + 100 = 612, within screen.height=900,
        // so y stays at 512 (NOT 612; brief expected y=612 which assumed a vertical flip).
        #expect(origin.x == 1088)
        #expect(origin.y == 512)
    }

    @Test func clampsInsideScreenWhenNoRoomEitherSide() {
        let cursor = CGPoint(x: 10, y: 10)
        let size = CGSize(width: 800, height: 600)
        let origin = PanelPositioning.origin(forPanel: size, near: cursor, on: screen)
        #expect(origin.x >= screen.minX)
        #expect(origin.y >= screen.minY)
        #expect(origin.x + size.width <= screen.maxX)
        #expect(origin.y + size.height <= screen.maxY)
    }

    // MARK: - Multi-display screen selection
    //
    // Geometry taken from the setup that surfaced the bug: a 1920×1080
    // external display stacked *above* a 1512×982 built-in and offset
    // left, so the external occupies y 982…2062 and x -408…1512.

    /// Primary (built-in). `NSScreen.main` resolves to this one for a
    /// menu-bar accessory app regardless of where the user is working.
    let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
    /// Secondary (external), stacked above and offset left.
    let external = CGRect(x: -408, y: 982, width: 1920, height: 1080)

    @Test func picksTheDisplayContainingTheCursor() {
        let onExternal = CGPoint(x: 552, y: 1553)
        let frame = PanelPositioning.screenFrame(
            for: onExternal, in: [builtIn, external], fallback: builtIn
        )
        #expect(frame == external)
    }

    @Test func picksBuiltInWhenCursorIsOnBuiltIn() {
        let onBuiltIn = CGPoint(x: 756, y: 512)
        let frame = PanelPositioning.screenFrame(
            for: onBuiltIn, in: [builtIn, external], fallback: external
        )
        #expect(frame == builtIn)
    }

    /// The regression itself: a cursor on the external display must not
    /// produce an origin that lands on the built-in one. Before the fix the
    /// clamp pinned y to `982 - 140 = 842`, putting the panel on the wrong
    /// monitor entirely.
    @Test func doesNotStrandPanelOnAnotherDisplay() {
        let cursor = CGPoint(x: 552, y: 1553)
        let size = CGSize(width: 360, height: 140)
        let frame = PanelPositioning.screenFrame(
            for: cursor, in: [builtIn, external], fallback: builtIn
        )
        let origin = PanelPositioning.origin(forPanel: size, near: cursor, on: frame)

        #expect(external.contains(CGPoint(x: origin.x, y: origin.y)))
        #expect(!builtIn.contains(CGPoint(x: origin.x, y: origin.y)))
        // And it should still be adjacent to the cursor, not just on-screen.
        #expect(abs(origin.y - cursor.y) <= 152)
    }

    /// Negative-x region of the external display must survive the clamp —
    /// `builtIn.minX == 0` would have pushed it to 0.
    @Test func honoursNegativeOriginDisplays() {
        let cursor = CGPoint(x: -300, y: 1500)
        let size = CGSize(width: 360, height: 140)
        let frame = PanelPositioning.screenFrame(
            for: cursor, in: [builtIn, external], fallback: builtIn
        )
        let origin = PanelPositioning.origin(forPanel: size, near: cursor, on: frame)
        #expect(frame == external)
        #expect(origin.x < 0)
        #expect(origin.x >= external.minX)
    }

    /// Cursor in a dead zone between mismatched displays snaps to the
    /// nearest screen rather than defaulting to the primary.
    @Test func snapsToNearestScreenInDeadZone() {
        // x = 1600 is beyond both screens' right edge; y = 1500 is deep in
        // the external's vertical band, so the external is nearest.
        let deadZone = CGPoint(x: 1600, y: 1500)
        let frame = PanelPositioning.screenFrame(
            for: deadZone, in: [builtIn, external], fallback: builtIn
        )
        #expect(frame == external)
    }

    @Test func fallsBackWhenNoScreensReported() {
        let frame = PanelPositioning.screenFrame(
            for: CGPoint(x: 5, y: 5), in: [], fallback: builtIn
        )
        #expect(frame == builtIn)
    }
}