import SwiftUI

struct TriggerButtonView: View {
    let isAI: Bool
    let onTap: () -> Void

    /// SF Symbol name rendered inside the trigger button. Exposed for tests
    /// (SwiftUI renders `Image(systemName:)` into private view classes that
    /// don't surface the symbol name, so we assert against this public
    /// property instead of introspecting the rendered tree).
    var iconName: String { isAI ? "sparkles" : "character.bubble.fill" }

    /// Letter shown on top of the bubble glyph in normal mode. `nil` for
    /// AI mode, which renders sparkles only.
    var monogram: String? { isAI ? nil : "F" }

    var body: some View {
        Button(action: onTap) {
            // Bare glyph — no background, border, or shadow. The user sees
            // only the bubble + monogram (normal) or sparkles (AI).
            // 28×28 frame keeps the click target generous.
            ZStack {
                if let letter = monogram {
                    // White bubble fill hides the internal "A" glyph that
                    // SF Symbols renders inside `character.bubble.fill`,
                    // and gives the black "F" monogram solid contrast.
                    Image(systemName: iconName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                    Text(letter)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.yellow)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isAI ? "AI 翻译" : "普通翻译")
    }
}