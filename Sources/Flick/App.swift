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
            // Static bubble + monogram. We deliberately do NOT use
            // TimelineView / Timer here — `MenuBarExtra` label views that
            // constantly re-render have been observed to leak memory and
            // (worse) vanish from the menu bar entirely on some macOS
            // versions.
            ZStack {
                Image(systemName: "character.bubble.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                Text("F")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
            }
        }
    }
}