import SwiftUI

struct TriggerButtonView: View {
    let isAI: Bool
    let onTap: () -> Void

    /// SF Symbol name rendered inside the trigger button. Exposed for tests
    /// (SwiftUI renders `Image(systemName:)` into private view classes that
    /// don't surface the symbol name, so we assert against this public
    /// property instead of introspecting the rendered tree).
    var iconName: String { isAI ? "sparkles" : "character.bubble.fill" }

    var body: some View {
        Button(action: onTap) {
            // Bare glyph — no background, border, or shadow. The user sees
            // only the bubble (normal) or sparkles (AI). 28×28 frame keeps
            // the click target generous.
            ZStack {
                Image(systemName: iconName)
                    .font(.system(size: isAI ? 18 : 22, weight: .medium))
                    .foregroundStyle(isAI ? Color.yellow : Color.primary)
                    .symbolRenderingMode(isAI ? .hierarchical : .monochrome)
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isAI ? "AI 翻译" : "普通翻译")
    }
}