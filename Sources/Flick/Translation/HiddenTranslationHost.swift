import SwiftUI
import Translation

/// A 1×1 SwiftUI view whose only job is to keep an Apple `TranslationSession` alive.
/// Required because the Translation framework on macOS only works inside a SwiftUI host.
@available(macOS 26.0, *)
struct HiddenTranslationHost: View {
    let session: TranslationSession
    var body: some View {
        // NOTE: API deviation from brief — the brief used
        // `.translationPresentation(isPresented: .constant(true), session: session)`,
        // but the actual macOS SDK signature is
        // `.translationPresentation(isPresented:text:attachmentAnchor:arrowEdge:replacementAction:)` —
        // it takes a `text:` String to translate (not a `session:`) and presents a user-facing
        // popover, not a session host. To keep `HiddenTranslationHost` compiling with the
        // brief's signature `init(session:)` we just render a 1×1 transparent rectangle.
        // The MenuBarController may later wire a `.translationTask` to keep a live session.
        Color.clear.frame(width: 1, height: 1)
    }
}
