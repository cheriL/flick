import Testing
@testable import Flick

@Suite @MainActor final class TriggerButtonViewTests {

    @Test func glyphCharacterMatches() {
        let view = TriggerButtonView(onTap: {})
        #expect(view.glyphCharacter == "F")
    }
}
