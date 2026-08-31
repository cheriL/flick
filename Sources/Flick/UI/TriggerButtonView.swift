import SwiftUI
import AppKit

struct TriggerButtonView: View {
    let onTap: () -> Void

    /// Bundle resource name rendered inside the trigger button. Test-visible since SwiftUI
/// renders `Image(nsImage:)` into private view classes that don't surface the resource name.
    var iconResourceName: String { "Flick" }

    var body: some View {
        Button(action: onTap) {
            // 28×28 with subtle SwiftUI drop shadow — window-level shadow is disabled (see
            // FloatingPanelController). SF Symbol fallback covers environments without the bundle
            // (e.g. `swift test`).
            ZStack {
                if let path = Bundle.main.path(forResource: iconResourceName, ofType: "icns"),
                   let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "character.bubble.fill")
                        .font(.system(size: 22, weight: .medium))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            Color.white,
                            Color(red: 0.45, green: 0.70, blue: 1.0)
                        )
                }
            }
            .frame(width: 28, height: 28)
            .shadow(color: Color.black.opacity(0.22), radius: 2, x: 0, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("翻译")
    }
}