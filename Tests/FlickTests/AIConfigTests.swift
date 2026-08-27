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
        // Default behaviour: suppress reasoning — keeps simple translations
        // fast and avoids leaked `<think>` blocks in the result panel.
        #expect(cfg.disableThinking == true)
    }

    @Test func roundTripsThroughJSON() throws {
        let original = AIConfig(provider: .openai,
                                baseURL: "https://api.deepseek.com",
                                apiKey: "sk-test",
                                model: "deepseek-chat")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AIConfig.self, from: data)
        #expect(decoded == original)
    }

    @Test func decodesLegacyJSONMissingDisableThinkingAsTrue() throws {
        // Older builds persisted AIConfig before `disableThinking` existed.
        // Those plists must still load — and they should opt into thinking
        // suppression so the previous behaviour (visible `<think>` blocks)
        // doesn't regress for anyone silently updating.
        let legacy = """
        {"provider":"openai","baseURL":"https://api.openai.com","apiKey":"sk-x","model":"gpt-4o-mini"}
        """
        let data = legacy.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AIConfig.self, from: data)
        #expect(decoded.disableThinking == true)
    }
}
