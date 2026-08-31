import Testing
@testable import Flick

@Suite @MainActor final class ResultWindowViewTests {

    @Test func loadingUsesProgressViewAndLabel() {
        let view = ResultWindowView(original: "hi", state: .loading, onRetry: {})
        #expect(view.loadingIconName == nil)
        #expect(view.loadingLabel == "翻译中…")
    }

    @Test func failureUsesXmarkCircle() {
        let view = ResultWindowView(original: "hi", state: .failure("boom"), onRetry: {})
        #expect(view.failureIconName == "xmark.circle")
    }
}