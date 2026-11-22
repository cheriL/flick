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

        let request = try config.provider.makeRequest(
            config: config, system: systemPrompt(for: target), user: text
        )

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

    /// Streams the response via SSE, calling `onDelta` with the accumulated raw
    /// response each time it grows; returns the final parsed result. Endpoints
    /// that ignore `stream: true` come back as one plain-JSON body with no
    /// deltas — those fall through the non-streaming parse instead.
    func translateStreaming(_ text: String,
                            to target: Locale.Language,
                            onDelta: @escaping (String) -> Void) async throws -> TranslationResult {
        guard canHandle(text) else {
            throw text.isEmpty ? TranslationError.empty : TranslationError.tooLong
        }
        guard !config.apiKey.isEmpty else {
            throw TranslationError.apiKeyMissing
        }

        let request = try config.provider.makeRequest(
            config: config, system: systemPrompt(for: target), user: text, stream: true
        )

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch is CancellationError {
            throw TranslationError.cancelled
        } catch {
            throw TranslationError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.network("non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            throw TranslationError.http(
                status: http.statusCode,
                body: String(data: body, encoding: .utf8) ?? ""
            )
        }

        var accumulated = ""
        var receivedDelta = false
        var rawBody = ""
        do {
            for try await line in bytes.lines {
                rawBody += line + "\n"
                guard line.hasPrefix("data: ") else { continue }
                let payload = String(line.dropFirst("data: ".count))
                if payload == "[DONE]" { break }
                if let delta = Provider.streamDelta(from: Data(payload.utf8)), !delta.isEmpty {
                    receivedDelta = true
                    accumulated += delta
                    onDelta(accumulated)
                }
            }
        } catch is CancellationError {
            throw TranslationError.cancelled
        } catch {
            throw TranslationError.network(error.localizedDescription)
        }

        if !receivedDelta {
            return try config.provider.extractResult(from: Data(rawBody.utf8))
        }
        return Provider.parseTaggedResponse(Provider.stripThinkBlocks(accumulated))
    }

    private func systemPrompt(for target: Locale.Language) -> String {
        let langName = Locale(identifier: target.maximalIdentifier)
            .localizedString(forLanguageCode: target.maximalIdentifier)
            ?? target.maximalIdentifier
        return """
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
    }
}