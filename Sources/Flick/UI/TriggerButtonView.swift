import SwiftUI

struct TriggerButtonView: View {
    let isAI: Bool
    let onTap: () -> Void

    /// SF Symbol name rendered inside the trigger button. Exposed for
    /// tests (SwiftUI renders `Image(systemName:)` into private view
    /// classes that don't surface the symbol name, so we assert against
    /// this public property instead of introspecting the rendered tree).
    var iconName: String { isAI ? "ellipsis.bubble.fill" : "character.bubble.fill" }

    var body: some View {
        Button(action: onTap) {
            // 28×28 frame, no extra background/border/shadow outside the
            // shape itself. `contentShape` extends the hit area to the
            // whole frame even though the visible glyph is smaller.
            //
            // Both modes share `.primary` tint, `.monochrome` rendering,
            // and the same font size — the only difference between modes
            // is the symbol shape itself. Earlier yellow/hierarchical
            // styling broke visual consistency with the normal-mode
            // bubble.
            ZStack {
                Image(systemName: isAI ? "ellipsis.bubble.fill" : "character.bubble.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .symbolRenderingMode(.monochrome)
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isAI ? "AI 翻译" : "普通翻译")
    }
}