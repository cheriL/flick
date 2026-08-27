import Foundation

enum Provider: String, Codable, CaseIterable, Equatable {
    case openai

    var displayName: String { "OpenAI" }

    // MARK: - URL construction

    /// Resolve the chat-completions endpoint for a given config.
    func endpoint(forBaseURL raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(trimmed)/v1/chat/completions")
    }

    // MARK: - Request body

    func makeRequest(config: AIConfig, prompt: String) throws -> URLRequest {
        guard let url = endpoint(forBaseURL: config.baseURL) else {
            throw TranslationError.network("invalid base URL: \(config.baseURL)")
        }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2,
        ]
        // Suppress chain-of-thought on reasoning-capable providers. Both fields
        // are silently ignored by non-reasoning models (gpt-4o-mini, deepseek-chat,
        // qwen-plus, …) but actively disable the `<think>` prelude on
        // reasoning models (OpenAI o-series, DeepSeek-V3.1).
        if config.disableThinking {
            body["reasoning_effort"] = "minimal"
            body["thinking"] = ["type": "disabled"]
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    // MARK: - Response parsing

    func extractTranslation(from data: Data) throws -> String {
        do {
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let choices = obj?["choices"] as? [[String: Any]] ?? []
            guard let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw TranslationError.decoding("missing choices[0].message.content")
            }
            let cleaned = Self.stripThinkBlocks(content)
            return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let e as TranslationError {
            throw e
        } catch {
            throw TranslationError.decoding(error.localizedDescription)
        }
    }

    /// Strip `<think>...</think>` blocks (and any unclosed `<think>` opener) from
    /// reasoning-model output so the user only sees the final translation.
    /// Models like DeepSeek-R1 and QwQ emit a `<think>` reasoning prelude that
    /// is not part of the answer.
    static func stripThinkBlocks(_ text: String) -> String {
        // Match either a balanced `<think>...</think>` (lazy so we don't span
        // multiple blocks) or an unclosed opener that runs to end of string
        // (response truncated by max_tokens, etc.).
        let pattern = #"<think>[\s\S]*?(?:</think>|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}
