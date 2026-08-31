import Foundation
import Translation

/// Translation backed by Apple's on-device `Translation` framework.
///
/// `session.translate(_:)` must be invoked from inside a SwiftUI view's
/// `.translationTask` action closure — calling it from arbitrary async
/// context returns "Unable to Translate" from the framework, which we
/// surface as `.network(...)`. Flick currently mounts no `.translationTask`
/// host, so this path always fails; a follow-up will add one (likely via
/// `MenuBarContent`'s `.glassEffect` modifier path or a dedicated
/// long-lived SwiftUI view) and rewire this method to delegate through it.
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
