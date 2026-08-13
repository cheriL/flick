import Foundation

struct AIConfig: Codable, Equatable {
    var provider: Provider
    var baseURL: String
    var apiKey: String
    var model: String

    static let `default` = AIConfig(
        provider: .openai,
        baseURL: "https://api.openai.com",
        apiKey: "",
        model: "gpt-4o-mini"
    )
}
