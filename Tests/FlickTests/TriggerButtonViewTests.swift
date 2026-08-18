import Testing
@testable import Flick

@Suite @MainActor final class TriggerButtonViewTests {

    @Test func normalModeUsesFilledBubbleWithFMonogram() {
        let view = TriggerButtonView(isAI: false, onTap: {})
        #expect(view.iconName == "character.bubble.fill")
        #expect(view.monogram == "F")
    }

    @Test func aiModeUsesSparklesWithoutMonogram() {
        let view = TriggerButtonView(isAI: true, onTap: {})
        #expect(view.iconName == "sparkles")
        #expect(view.monogram == nil)
    }
}