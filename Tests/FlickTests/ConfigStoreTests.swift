import Foundation
import Testing
@testable import Flick

@Suite struct ConfigStoreTests {
    let defaults: UserDefaults
    let store: ConfigStore

    init() {
        let d = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        self.defaults = d
        self.store = ConfigStore(
            defaults: d,
            keychainService: "com.cheriL.flick.test.\(UUID().uuidString)"
        )
    }

    @Test func loadReturnsDefaultWhenEmpty() {
        let cfg = store.load()
        #expect(cfg == .default)
    }

    @Test func saveAndLoadRoundTrip() {
        var cfg = store.load()
        cfg.provider = .claude
        cfg.baseURL = "https://example.com"
        cfg.apiKey = "secret-xyz"
        cfg.model = "claude-haiku-4-5"
        store.save(cfg)

        let loaded = store.load()
        #expect(loaded.provider == .claude)
        #expect(loaded.baseURL == "https://example.com")
        #expect(loaded.apiKey == "secret-xyz")
        #expect(loaded.model == "claude-haiku-4-5")
    }

    @Test func keychainIsSeparateFromDefaults() throws {
        var cfg = store.load()
        cfg.apiKey = "secret-abc"
        store.save(cfg)

        // Non-secret fields may be persisted in UserDefaults,
        // but the API key must NEVER appear there.
        let raw = try #require(defaults.data(forKey: "Flick.AIConfig"))
        let stored = try JSONDecoder().decode(AIConfig.self, from: raw)
        #expect(stored.apiKey.isEmpty)
    }
}