import Testing
@testable import Flick

@Suite @MainActor final class TriggerButtonViewTests {

    @Test func normalModeUsesCharacterBubble() {
        let view = TriggerButtonView(isAI: false, onTap: {})
        #expect(view.iconName == "character.bubble")
    }

    @Test func aiModeUsesSparkles() {
        let view = TriggerButtonView(isAI: true, onTap: {})
        #expect(view.iconName == "sparkles")
    }
}