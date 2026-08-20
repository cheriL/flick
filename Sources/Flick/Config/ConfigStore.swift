import Foundation
import Security

final class ConfigStore {
    private let defaults: UserDefaults
    private let defaultsKey = "Flick.AIConfig"
    private let selectionEnabledKey = "Flick.selectionEnabled"
    private let keychainService: String
    private let keychainAccount = "openai-api-key"

    init(defaults: UserDefaults = .standard,
         keychainService: String = "com.cheriL.flick") {
        self.defaults = defaults
        self.keychainService = keychainService
        // One-time migration: pull any pre-existing API key out of the
        // keychain (the old storage path) and persist it together with
        // the rest of the config in UserDefaults. The keychain entry is
        // deleted afterwards so the two stores can't drift.
        migrateKeychainToDefaults()
    }

    func load() -> AIConfig {
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(AIConfig.self, from: data) {
            return decoded
        }
        return .default
    }

    func save(_ cfg: AIConfig) {
        if let data = try? JSONEncoder().encode(cfg) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    // MARK: - Selection-enabled toggle

    /// Global "allow selection-to-translate" switch. Default ON. The
    /// monitor reads this each tick (and on change) so the user can
    /// kill the feature without quitting Flick.
    var isSelectionEnabled: Bool {
        // Object lookup (not `bool(forKey:)`) so an absent key returns
        // the default rather than being coerced to `false`.
        (defaults.object(forKey: selectionEnabledKey) as? Bool) ?? true
    }

    func setSelectionEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: selectionEnabledKey)
        NotificationCenter.default.post(name: .flickSelectionEnabledChanged, object: nil, userInfo: ["enabled": enabled])
    }

    // MARK: - Keychain → defaults migration

    private func migrateKeychainToDefaults() {
        guard let key = readKeychain(), !key.isEmpty else { return }
        // Only seed defaults if there's no existing record; we don't want
        // to clobber a config the user has since updated.
        if defaults.data(forKey: defaultsKey) == nil {
            var cfg = AIConfig.default
            cfg.apiKey = key
            save(cfg)
        }
        clearKeychain()
    }

    private func clearKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
