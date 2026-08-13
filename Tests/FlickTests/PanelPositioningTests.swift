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
}