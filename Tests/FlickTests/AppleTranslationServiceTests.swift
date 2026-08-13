import Foundation
import Testing
import Translation
@testable import Flick

@Suite @MainActor final class AppleTranslationServiceTests {

    @Test func canHandleRejectsEmptyAndTooLong() {
        let svc = AppleTranslationService()
        #expect(!svc.canHandle(""))
        #expect(!svc.canHandle(String(repeating: "x", count: 5001)))
        #expect(svc.canHandle("hello"))
    }

    @Test func displayName() {
        #expect(AppleTranslationService().displayName == "Apple")
    }
}
