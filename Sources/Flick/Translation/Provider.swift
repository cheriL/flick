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
        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2,
        ]
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
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let e as TranslationError {
            throw e
        } catch {
            throw TranslationError.decoding(error.localizedDescription)
        }
    }
}
