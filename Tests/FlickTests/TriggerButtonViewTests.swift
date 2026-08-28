import Testing
@testable import Flick

@Suite @MainActor final class TriggerButtonViewTests {

    @Test func normalModeUsesFilledBubble() {
        let view = TriggerButtonView(isAI: false, onTap: {})
        #expect(view.iconResourceName == "Flick")
    }

    @Test func aiModeUsesEllipsisBubble() {
        let view = TriggerButtonView(isAI: true, onTap: {})
        #expect(view.iconResourceName == "Flick-AI")
    }
}