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
            // Same trick as MenuBarContent: TimelineView re-checks
            // `AXIsProcessTrusted()` every second so the icon swaps to
            // an exclamation glyph the moment permission is granted.
            TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                Image(systemName: AXUIElement.isProcessTrusted
                      ? "character.bubble"
                      : "exclamationmark.bubble")
            }
        }
    }
}