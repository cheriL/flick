import Testing
import AppKit
@testable import Flick

@Suite @MainActor final class FloatingPanelControllerTests {
    let controller = FloatingPanelController()

    @Test func outsideClickDismissesWhenNoPanelsVisible() {
        // Fresh controller — nothing on screen, any click should be
        // "outside". The actual dismissal is a no-op when there's
        // nothing to dismiss, but the predicate must say yes so the
        // monitor handler doesn't early-return.
        #expect(controller.isOutsideClick(at: CGPoint(x: 100, y: 100)))
    }

    @Test func outsideClickDoesNotDismissWhenInsideTrigger() {
        controller.showTrigger(at: CGPoint(x: 200, y: 200), text: "hello", isAI: false, onTap: {})
        let frame = controller.triggerFrameForTesting
        let insidePoint = CGPoint(x: frame.midX, y: frame.midY)
        #expect(!controller.isOutsideClick(at: insidePoint),
                "trigger frame = \(frame), click at \(insidePoint) should be inside")
    }

    @Test func outsideClickDismissesWhenOutsideTrigger() {
        controller.showTrigger(at: CGPoint(x: 200, y: 200), text: "hello", isAI: false, onTap: {})
        let frame = controller.triggerFrameForTesting
        // A point far past the panel's bottom-right corner is outside
        // regardless of where the headless screen geometry clamped it.
        let farAway = CGPoint(x: frame.maxX + 5000, y: frame.maxY + 5000)
        #expect(controller.isOutsideClick(at: farAway))
    }

    @Test func outsideClickDoesNotDismissWhenInsideResult() {
        controller.showResult(original: "hello", state: .loading, at: CGPoint(x: 100, y: 100), isAI: false, onRetry: {})
        let frame = controller.resultFrameForTesting
        let insidePoint = CGPoint(x: frame.midX, y: frame.midY)
        #expect(!controller.isOutsideClick(at: insidePoint),
                "result frame = \(frame), click at \(insidePoint) should be inside")
    }

    @Test func outsideClickDismissesWhenOutsideResult() {
        controller.showResult(original: "hello", state: .loading, at: CGPoint(x: 100, y: 100), isAI: false, onRetry: {})
        let frame = controller.resultFrameForTesting
        let farAway = CGPoint(x: frame.maxX + 5000, y: frame.maxY + 5000)
        #expect(controller.isOutsideClick(at: farAway))
    }

    @Test func dismissHidesBothPanels() {
        controller.showTrigger(at: CGPoint(x: 50, y: 50), text: "x", isAI: false, onTap: {})
        controller.showResult(original: "x", state: .loading, at: CGPoint(x: 50, y: 50), isAI: false, onRetry: {})
        controller.dismiss()
        #expect(controller.isOutsideClick(at: CGPoint(x: 100, y: 100)))
    }

    @Test func resultPanelHidesTrigger() {
        // showResult flips triggerActive to false. A click where the
        // trigger used to be should now be "outside" (it's gone), even
        // if the result panel is sitting somewhere else entirely.
        let triggerOrigin = CGPoint(x: 50, y: 50)
        let resultCursor = CGPoint(x: 800, y: 600)
        controller.showTrigger(at: triggerOrigin, text: "x", isAI: false, onTap: {})
        let oldTriggerCenter = CGPoint(
            x: controller.triggerFrameForTesting.midX,
            y: controller.triggerFrameForTesting.midY
        )
        controller.showResult(original: "x", state: .loading, at: resultCursor, isAI: false, onRetry: {})
        // Click in the middle of where the trigger was — must be "outside"
        // because triggerActive is now false.
        #expect(controller.isOutsideClick(at: oldTriggerCenter))
    }

    @Test func resultPanelDoesNotPinAppearance() {
        // The result panel's chrome is an adaptive NSView subclass
        // (`AdaptiveChromeView`) that repaints white in light mode and
        // dark gray in dark mode; the SwiftUI text uses `.primary` /
        // `.secondary` which auto-invert. We must NOT pin the panel —
        // both layers track the system appearance so the panel looks
        // the same as the rest of the UI (white panel + black text in
        // light, dark panel + white text in dark).
        let controller = FloatingPanelController()
        #expect(controller.resultAppearanceForTesting == nil,
                "result panel must inherit system appearance, not be pinned; got \(String(describing: controller.resultAppearanceForTesting))")
    }
}
