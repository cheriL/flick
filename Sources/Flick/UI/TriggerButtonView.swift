import SwiftUI
import AppKit

struct TriggerButtonView: View {
    let isAI: Bool
    let onTap: () -> Void

    /// Bundle resource name rendered inside the trigger button. Exposed
    /// for tests (SwiftUI renders `Image(nsImage:)` into private view
    /// classes that don't surface the resource name, so we assert against
    /// this public property instead of introspecting the rendered tree).
    ///
    /// The actual image is loaded from `Contents/Resources/<name>.icns`
    /// at render time, so this is just a stable identifier — same
    /// contract as the previous SF-Symbol `iconName` hook.
    var iconResourceName: String { isAI ? "Flick-AI" : "Flick" }

    var body: some View {
        Button(action: onTap) {
            // 28×28 frame, no extra background/border/shadow outside the
            // shape itself. `contentShape` extends the hit area to the
            // whole frame even though the visible glyph is smaller.
            //
            // Both modes use the full-colour .icns (the popup has its
            // own white background, so we don't apply template tinting
            // like the menu-bar icon does). The fallback SF Symbol
            // matches the pre-refactor look for environments without a
            // built bundle (e.g. `swift test`).
            ZStack {
                if let path = Bundle.main.path(forResource: iconResourceName, ofType: "icns"),
                   let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: isAI ? "ellipsis.bubble.fill" : "character.bubble.fill")
                        .font(.system(size: 22, weight: .medium))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            Color.white,
                            Color(red: 0.45, green: 0.70, blue: 1.0)
                        )
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isAI ? "AI 翻译" : "普通翻译")
    }
}