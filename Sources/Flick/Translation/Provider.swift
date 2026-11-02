import Foundation

enum Provider: String, Codable, CaseIterable, Equatable {
    case openai

    var displayName: String { "OpenAI" }

    // MARK: - URL construction

    /// Resolve the chat-completions endpoint for a given config. The Base URL
    /// carries the version prefix (`…/v1`); only the resource path is appended.
    func endpoint(forBaseURL raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(trimmed)/chat/completions")
    }

    // MARK: - Request body

    func makeRequest(config: AIConfig, system: String, user: String) throws -> URLRequest {
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
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        // Both fields are silently ignored by non-reasoning models but disable the `<think>` prelude
        // on reasoning models (OpenAI o-series, DeepSeek-V3.1).
        if config.disableThinking {
            body["reasoning_effort"] = "minimal"
            body["thinking"] = ["type": "disabled"]
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    // MARK: - Response parsing

    func extractResult(from data: Data) throws -> TranslationResult {
        do {
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let choices = obj?["choices"] as? [[String: Any]] ?? []
            guard let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw TranslationError.decoding("missing choices[0].message.content")
            }
            return Self.parseTaggedResponse(Self.stripThinkBlocks(content))
        } catch let e as TranslationError {
            throw e
        } catch {
            throw TranslationError.decoding(error.localizedDescription)
        }
    }

    /// Strip `<think>...</think>` blocks (and any unclosed opener) from reasoning-model output so
    /// the user only sees the final translation.
    static func stripThinkBlocks(_ text: String) -> String {
        // Match either a balanced `<think>...</think>` (lazy) or an unclosed opener running to
        // end of string (response truncated by max_tokens).
        let pattern = #"<think>[\s\S]*?(?:</think>|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    // MARK: - Tagged-response parsing

    static func parseTaggedResponse(_ raw: String) -> TranslationResult {
        let text = stripCodeFences(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        let translation = tagContents("translation", in: text)
            ?? text
                .replacingOccurrences(
                    of: #"<(?:source|target)-pronunciation>[\s\S]*?</(?:source|target)-pronunciation>"#,
                    with: "",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
        return TranslationResult(
            translation: translation,
            sourcePronunciation: tagContents("source-pronunciation", in: text),
            targetPronunciation: tagContents("target-pronunciation", in: text)
        )
    }

    /// `[^>]*` tolerates attributes the model may add (`<translation lang="zh">`);
    /// `[\s\S]*?` spans newlines — `.` does not match them in NSRegularExpression.
    private static func tagContents(_ name: String, in text: String) -> String? {
        let pattern = #"<\#(name)[^>]*>([\s\S]*?)</\#(name)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let value = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Models occasionally fence the tagged block; tags match fine inside fences,
    /// but fence lines leak into the untagged fallback text.
    private static func stripCodeFences(_ text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
        if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}
