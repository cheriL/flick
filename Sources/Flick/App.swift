import SwiftUI
import AppKit
import ApplicationServices

@main
struct FlickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                store: appDelegate.store,
                onQuit: { NSApp.terminate(nil) }
            )
        } label: {
            // Static icon. We deliberately do NOT use TimelineView / Timer
            // here — `MenuBarExtra` label views that constantly re-render
            // have been observed to leak memory and (worse) vanish from the
            // menu bar entirely on some macOS versions. The icon swaps to
            // the warning glyph in `MenuBarContent` once the user opens
            // the menu, which is sufficient UX.
            Image(systemName: "character.bubble")
        }
    }
}