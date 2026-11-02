import Foundation

final class OpenAICompatibleService: TranslationService {
    let displayName: String
    private let config: AIConfig
    private let session: URLSession

    init(config: AIConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
        self.displayName = config.provider.displayName
    }

    func canHandle(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.count <= 5000 else { return false }
        return true
    }

    func translate(_ text: String, to target: Locale.Language) async throws -> TranslationResult {
        guard canHandle(text) else {
            throw text.isEmpty ? TranslationError.empty : TranslationError.tooLong
        }
        guard !config.apiKey.isEmpty else {
            throw TranslationError.apiKeyMissing
        }

        let langName = Locale(identifier: target.maximalIdentifier)
            .localizedString(forLanguageCode: target.maximalIdentifier)
            ?? target.maximalIdentifier
        let system = """
        Translate the user's text into \(langName). \
        Respond with exactly this format and nothing else: \
        <translation>the translation</translation> \
        <source-pronunciation>reading of the source text aloud</source-pronunciation> \
        <target-pronunciation>reading of the translation aloud</target-pronunciation> \
        Pronunciation scheme by script: IPA for Latin-script languages, \
        Hanyu Pinyin with tone marks for Chinese, \
        Hepburn romaji for Japanese, Revised Romanization for Korean. \
        Omit both pronunciation tags when the text is longer than two sentences. \
        Preserve the original line breaks inside <translation>. \
        Keep code, URLs, and proper nouns unchanged.
        """

        let request = try config.provider.makeRequest(config: config, system: system, user: text)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw TranslationError.cancelled
        } catch {
            throw TranslationError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.network("non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw TranslationError.http(status: http.statusCode, body: bodyText)
        }

        return try config.provider.extractResult(from: data)
    }
}