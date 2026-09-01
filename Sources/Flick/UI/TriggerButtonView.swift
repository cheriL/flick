import SwiftUI

struct TriggerButtonView: View {
    let onTap: () -> Void

    // MARK: - Test hooks
    /// SF Symbol rendered inside the trigger button. Test-visible since SwiftUI's
    /// `Image(systemName:)` doesn't surface the symbol name on the rendered view tree.
    var iconSystemName: String { "f.square.fill" }

    var body: some View {
        Button(action: onTap) {
            // 28×28 with subtle SwiftUI drop shadow — window-level shadow is disabled (see
            // FloatingPanelController).
            Image(systemName: iconSystemName)
                .font(.system(size: 22, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .green)
                .frame(width: 28, height: 28)
                .shadow(color: Color.black.opacity(0.22), radius: 2, x: 0, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("翻译")
    }
}