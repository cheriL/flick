import Foundation
import Translation

/// Apple's on-device `Translation` framework. `session.translate(_:)` must run inside a
/// SwiftUI `.translationTask` — Flick doesn't host one yet, so this path always errors.
final class AppleTranslationService: TranslationService {
    let displayName = "Apple"

    func canHandle(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 500
    }

    func translate(_ text: String, to target: Locale.Language) async throws -> String {
        guard canHandle(text) else {
            throw text.isEmpty ? TranslationError.empty : TranslationError.tooLong
        }
        do {
            let session = TranslationSession(
                installedSource: Locale.current.language,
                target: target
            )
            let response = try await session.translate(text)
            return response.targetText
        } catch is CancellationError {
            throw TranslationError.cancelled
        } catch {
            throw TranslationError.network(error.localizedDescription)
        }
    }
}
