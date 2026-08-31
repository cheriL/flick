import Foundation
import Translation

/// Translation backed by Apple's on-device `Translation` framework.
///
/// `canHandle` and `displayName` are available on all macOS versions; `translate`
/// is gated at runtime. On macOS < 26 the SDK only exposes
/// `TranslationSession(installedSource:target:)`. On macOS 26+ the framework also
/// requires `session.translate(_:)` to be invoked from inside a SwiftUI view's
/// `.translationTask` action closure — calling it from arbitrary async context
/// returns "Unable to Translate".
///
/// As of this commit, no `.translationTask` host is mounted in Flick, so the
/// macOS 26+ branch currently throws the same way as < 26. Restoring Apple
/// translation on macOS 26+ is tracked as a follow-up.
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
        if #available(macOS 26.0, *) {
            // macOS 26+ requires `session.translate(_:)` to be invoked from inside a
            // SwiftUI view's `.translationTask` action closure. Flick currently mounts
            // no such host (Phase 2 work), so calling `.translate` from arbitrary async
            // context surfaces "Unable to Translate" from the framework — we wrap it in
            // `.network(...)` exactly as before. Once the host lands, this branch is
            // expected to start succeeding.
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
        } else {
            throw TranslationError.unsupportedLanguagePair(
                source: nil,
                target: target.maximalIdentifier
            )
        }
    }
}
