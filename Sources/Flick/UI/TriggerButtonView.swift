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
        .buttonStyle(TriggerButtonStyle())
    }
}

/// Press feedback fires on mouse-down — `.plain` gives none, so a click on the
/// trigger read as dead until the result panel replaced it.
private struct TriggerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}