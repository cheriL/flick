import Testing
@testable import Flick

@Suite @MainActor final class TriggerButtonViewTests {

    @Test func iconResourceNameMatchesBundle() {
        let view = TriggerButtonView(onTap: {})
        #expect(view.iconResourceName == "Flick")
    }
}