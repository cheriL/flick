import Foundation

protocol TranslationService: AnyObject {
    var displayName: String { get }

    /// Cheap predicate; backends with language-pair or length limits report here.
    func canHandle(_ text: String) -> Bool

    /// Translate `text` into `target`. Implementations must respect task cancellation.
    func translate(_ text: String, to target: Locale.Language) async throws -> String
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
        case .empty:                       return "没有可翻译的文本"
        case .tooLong:                     return "文本过长"
        case .apiKeyMissing:               return "AI 翻译需要先在菜单栏 → AI 设置 配置 API Key"
        case .network(let msg):            return "网络错误：\(msg)"
        case .http(let s, let b):          return "服务返回 HTTP \(s): \(b)"
        case .decoding(let msg):           return "解析失败：\(msg)"
        case .cancelled:                   return "已取消"
        }
    }
}