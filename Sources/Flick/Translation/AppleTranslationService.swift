import Foundation
import Translation

/// Translation backed by Apple's on-device `Translation` framework.
///
/// Note: `TranslationSession` itself requires macOS 15+, and the
/// `TranslationSession(installedSource:target:)` init requires macOS 26+ —
/// the SDK shipped with the current build host only exposes that init.
/// `canHandle` and `displayName` are available on all macOS versions; only
/// `translate` is gated at runtime.
final class AppleTranslationService: TranslationService {
    let displayName = "Apple"

    func canHandle(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 500
    }

    /// Note: this method must be invoked from a context where a `TranslationSession`
    /// is currently active (e.g. while `HiddenTranslationHost` is mounted in the view
    /// hierarchy by the menu-bar app). The MenuBarController is responsible for
    /// keeping that host view alive.
    func translate(_ text: String, to target: Locale.Language) async throws -> String {
        guard canHandle(text) else {
            throw text.isEmpty ? TranslationError.empty : TranslationError.tooLong
        }
        if #available(macOS 26.0, *) {
            do {
                // NOTE: API deviation from brief — the macOS SDK shipped on this build
                // host (Xcode 26 / macOS 26 SDK) only exposes
                // `TranslationSession(installedSource:target:)` (a 2-arg init, macOS 26+).
                // The brief's `TranslationSession(source: nil, target: target)` form
                // does not compile against the installed SDK. We fall back to passing
                // `Locale.current.language` for the installed source; the framework still
                // auto-detects the actual input language from the text at translate time.
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
