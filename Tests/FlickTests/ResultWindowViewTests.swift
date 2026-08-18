import Testing
@testable import Flick

@Suite @MainActor final class ResultWindowViewTests {

    @Test func aiLoadingUsesEllipsisBubbleIconAndLabel() {
        let view = ResultWindowView(original: "hi", state: .loading, isAI: true, onRetry: {})
        #expect(view.loadingIconName == "ellipsis.bubble.fill")
        #expect(view.loadingLabel == "AI 翻译中…")
    }

    @Test func normalLoadingUsesProgressViewAndLabel() {
        let view = ResultWindowView(original: "hi", state: .loading, isAI: false, onRetry: {})
        #expect(view.loadingIconName == nil)  // ProgressView instead of Image
        #expect(view.loadingLabel == "翻译中…")
    }

    @Test func failureUsesXmarkCircle() {
        let view = ResultWindowView(original: "hi", state: .failure("boom"), isAI: false, onRetry: {})
        #expect(view.failureIconName == "xmark.circle")
    }

    @Test func aiAccentBarPresentOnlyForAI() {
        let aiView = ResultWindowView(original: "hi", state: .success("ok"), isAI: true, onRetry: {})
        #expect(aiView.showsAIAccentBar == true)

        let normalView = ResultWindowView(original: "hi", state: .success("ok"), isAI: false, onRetry: {})
        #expect(normalView.showsAIAccentBar == false)
    }
}