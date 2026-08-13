import Foundation
import Testing
@testable import Flick

@Suite struct AIConfigTests {
    @Test func defaultConfig() {
        let cfg = AIConfig.default
        #expect(cfg.provider == .openai)
        #expect(cfg.baseURL == "https://api.openai.com")
        #expect(cfg.apiKey == "")
        #expect(cfg.model == "gpt-4o-mini")
    }

    @Test func roundTripsThroughJSON() throws {
        let original = AIConfig(provider: .claude,
                                baseURL: "https://api.deepseek.com",
                                apiKey: "sk-test",
                                model: "deepseek-chat")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AIConfig.self, from: data)
        #expect(decoded == original)
    }

    @Test func providerOpenAIAndClaudeAreDistinct() {
        #expect(Provider.openai != Provider.claude)
    }
}
