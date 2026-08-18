import SwiftUI

struct TriggerButtonView: View {
    let isAI: Bool
    let onTap: () -> Void

    /// SF Symbol name rendered inside the trigger circle. Exposed for tests
    /// (SwiftUI renders `Image(systemName:)` into private view classes that
    /// don't surface the symbol name, so we assert against this public
    /// property instead of introspecting the rendered tree).
    var iconName: String { isAI ? "sparkles" : "character.bubble" }

    var body: some View {
        Button(action: onTap) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(.regularMaterial)
                )
                .overlay(
                    Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .help(isAI ? "AI 翻译" : "普通翻译")
    }
}