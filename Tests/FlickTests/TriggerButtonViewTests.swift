import Testing
@testable import Flick

@Suite @MainActor final class TriggerButtonViewTests {

    @Test func iconSystemNameMatches() {
        let view = TriggerButtonView(onTap: {})
        #expect(view.iconSystemName == "f.square.fill")
    }
}