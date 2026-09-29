import Foundation
import Testing
@testable import Flick

@Suite struct ProviderEndpointTests {
    @Test func appendsResourcePathOnly() {
        let url = Provider.openai.endpoint(forBaseURL: "https://api.openai.com/v1")
        #expect(url?.absoluteString == "https://api.openai.com/v1/chat/completions")
    }

    @Test func toleratesTrailingSlashes() {
        let url = Provider.openai.endpoint(forBaseURL: "https://api.minimaxi.com/v1/")
        #expect(url?.absoluteString == "https://api.minimaxi.com/v1/chat/completions")
    }

    @Test func keepsPathPrefix() {
        let url = Provider.openai.endpoint(forBaseURL: "https://example.com/gateway/v1")
        #expect(url?.absoluteString == "https://example.com/gateway/v1/chat/completions")
    }
}
