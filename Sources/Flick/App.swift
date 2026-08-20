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
            // Plain `character.bubble.fill` glyph. Matches the trigger
            // button's normal-mode icon so the menu bar and the trigger
            // panel share one recognizable shape. We deliberately do NOT
            // use TimelineView / Timer here — `MenuBarExtra` label views
            // that constantly re-render have been observed to leak memory
            // and (worse) vanish from the menu bar entirely on some macOS
            // versions. The icon uses the system's primary tint so it stays
            // legible against both light and dark menu bars.
            Image(systemName: "character.bubble.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
        }
        .menuBarExtraStyle(.window)
    }
}