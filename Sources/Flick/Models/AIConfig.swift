import Foundation

struct AIConfig: Codable, Equatable {
    var provider: Provider
    var baseURL: String
    var apiKey: String
    var model: String
    /// When true (default), the OpenAI-compatible request body carries
    /// `reasoning_effort: "minimal"` and `thinking: {"type": "disabled"}`.
    /// Reasoning-capable models (OpenAI o-series, DeepSeek-V3.1) honour
    /// these and respond without a `<think>` prelude; non-reasoning models
    /// (gpt-4o-mini, etc.) ignore unknown fields. Set to false if your
    /// provider rejects unknown params outright.
    var disableThinking: Bool

    static let `default` = AIConfig(
        provider: .openai,
        baseURL: "https://api.openai.com",
        apiKey: "",
        model: "gpt-4o-mini",
        disableThinking: true
    )

    init(provider: Provider,
         baseURL: String,
         apiKey: String,
         model: String,
         disableThinking: Bool = true) {
        self.provider = provider
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.disableThinking = disableThinking
    }

    private enum CodingKeys: String, CodingKey {
        case provider, baseURL, apiKey, model, disableThinking
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.provider = try c.decode(Provider.self, forKey: .provider)
        self.baseURL = try c.decode(String.self, forKey: .baseURL)
        self.apiKey = try c.decode(String.self, forKey: .apiKey)
        self.model = try c.decode(String.self, forKey: .model)
        // decodeIfPresent so existing plists written before this field was
        // introduced still load — they get the safe default of "no thinking".
        self.disableThinking = try c.decodeIfPresent(Bool.self, forKey: .disableThinking) ?? true
    }
}