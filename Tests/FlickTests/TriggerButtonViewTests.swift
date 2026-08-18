import Testing
@testable import Flick

@Suite @MainActor final class TriggerButtonViewTests {

    @Test func normalModeUsesFilledBubble() {
        let view = TriggerButtonView(isAI: false, onTap: {})
        #expect(view.iconName == "character.bubble.fill")
    }

    @Test func aiModeUsesEllipsisBubble() {
        let view = TriggerButtonView(isAI: true, onTap: {})
        #expect(view.iconName == "ellipsis.bubble.fill")
    }
}