import Foundation
import Security

final class ConfigStore {
    private let defaults: UserDefaults
    private let keychainService: String
    private let keychainAccount = "openai-api-key"
    private let defaultsKey = "Flick.AIConfig"

    init(defaults: UserDefaults = .standard,
         keychainService: String = "com.cheriL.flick") {
        self.defaults = defaults
        self.keychainService = keychainService
    }

    func load() -> AIConfig {
        let cfg: AIConfig
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(AIConfig.self, from: data) {
            cfg = decoded
        } else {
            cfg = .default
        }
        var copy = cfg
        copy.apiKey = readKeychain() ?? ""
        return copy
    }

    func save(_ cfg: AIConfig) {
        var withoutKey = cfg
        let key = withoutKey.apiKey
        withoutKey.apiKey = ""
        if let data = try? JSONEncoder().encode(withoutKey) {
            defaults.set(data, forKey: defaultsKey)
        }
        if !key.isEmpty {
            writeKeychain(key)
        }
    }

    func clearKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Keychain helpers

    private func writeKeychain(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
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