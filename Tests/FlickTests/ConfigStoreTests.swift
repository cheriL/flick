import Foundation
import Testing
@testable import Flick

@Suite final class ConfigStoreTests {
    let suiteName: String
    let defaults: UserDefaults
    let store: ConfigStore

    init() {
        let name = "test.\(UUID().uuidString)"
        self.suiteName = name
        let d = UserDefaults(suiteName: name)!
        self.defaults = d
        self.store = ConfigStore(defaults: d)
    }

    deinit {
        // Drop the dedicated defaults domain so the suite's plist
        // (`test.<UUID>.plist` in ~/Library/Preferences) doesn't
        // accumulate across test runs. `removePersistentDomain`
        // clears the in-memory store but cfprefsd leaves an empty
        // file shell behind, so we also delete it directly.
        defaults.removePersistentDomain(forName: suiteName)
        let plistPath = NSHomeDirectory() + "/Library/Preferences/\(suiteName).plist"
        try? FileManager.default.removeItem(atPath: plistPath)
    }

    @Test func loadReturnsDefaultWhenEmpty() {
        let cfg = store.load()
        #expect(cfg == .default)
    }

    @Test func saveAndLoadRoundTrip() {
        var cfg = store.load()
        cfg.baseURL = "https://example.com"
        cfg.apiKey = "secret-xyz"
        cfg.model = "gpt-4o-mini"
        store.save(cfg)

        let loaded = store.load()
        #expect(loaded.provider == .openai)
        #expect(loaded.baseURL == "https://example.com")
        #expect(loaded.apiKey == "secret-xyz")
        #expect(loaded.model == "gpt-4o-mini")
    }

    @Test func persistedPlistContainsAllFields() throws {
        var cfg = store.load()
        cfg.apiKey = "secret-abc"
        store.save(cfg)

        // After the Keychain removal, every field (including the API
        // key) lives in UserDefaults. The plist on disk must round-trip
        // the full config.
        let raw = try #require(defaults.data(forKey: "Flick.AIConfig"))
        let stored = try JSONDecoder().decode(AIConfig.self, from: raw)
        #expect(stored.apiKey == "secret-abc")
    }
}
