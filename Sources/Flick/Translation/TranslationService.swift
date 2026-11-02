import Foundation

struct TranslationResult: Equatable {
    let translation: String
    let sourcePronunciation: String?
    let targetPronunciation: String?
}

protocol TranslationService: AnyObject {
    var displayName: String { get }

    /// Cheap predicate; backends with language-pair or length limits report here.
    func canHandle(_ text: String) -> Bool

    /// Translate `text` into `target`. Implementations must respect task cancellation.
    func translate(_ text: String, to target: Locale.Language) async throws -> TranslationResult
}

enum TranslationError: LocalizedError, Equatable {
    case empty
    case tooLong
    case apiKeyMissing
    case network(String)
    case http(status: Int, body: String)
    case decoding(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .empty:                       return "No text to translate"
        case .tooLong:                     return "Text is too long"
        case .apiKeyMissing:               return "AI translation needs an API key. Set it in Menu → Settings."
        case .network(let msg):            return "Network error: \(msg)"
        case .http(let s, let b):          return "Server returned HTTP \(s): \(b)"
        case .decoding(let msg):           return "Failed to parse response: \(msg)"
        case .cancelled:                   return "Cancelled"
        }
    }
}