import SwiftUI

struct TriggerButtonView: View {
    let onTap: () -> Void

    // MARK: - Test hooks
    /// Character rendered inside the bubble glyph. Test-visible since SwiftUI's
    /// `Text` content isn't surfaced on the rendered view tree.
    var glyphCharacter: String { "F" }

    var body: some View {
        Button(action: onTap) {
            // 28×28 with subtle SwiftUI drop shadow — window-level shadow is disabled (see
            // FloatingPanelController).
            FlickBubbleGlyph(side: 27,
                             bubbleStyle: AnyShapeStyle(LinearGradient.flick),
                             glyphColor: .white)
                .frame(width: 28, height: 28)
                .shadow(color: Color.black.opacity(0.22), radius: 2, x: 0, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Translate")
    }
}