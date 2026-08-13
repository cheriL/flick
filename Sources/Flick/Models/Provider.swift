import Foundation

enum Provider: String, Codable, CaseIterable, Equatable {
    case openai
    case claude

    var displayName: String {
        switch self {
        case .openai: return "OpenAI / DeepSeek"
        case .claude: return "Claude"
        }
    }
}
