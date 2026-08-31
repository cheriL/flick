import SwiftUI
import AppKit
import ApplicationServices

@main
struct FlickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // SwiftUI `@main App` requires at least one `Scene` to compile,
        // but Flick surfaces every window through AppKit directly:
        // the menu-bar icon is an `NSStatusItem` owned by
        // `MenuBarController` and the popup is an `NSPanel` owned by
        // `MenuPanelController`; `AISettingsWindow` opens its own
        // `NSPanel` from the menu. The previous `MenuBarExtra` was
        // dropped because its hosting panel is opaque and SwiftUI-auto-
        // applied Liquid Glass to it on macOS 26+, both unreachable
        // from outside the scene, which kept us from achieving the
        // Tailscale/NSMenu frosted look the menu had been aiming at.
        //
        // `Settings { EmptyView() }` is the smallest possible SwiftUI
        // scene: SwiftUI won't actually instantiate a window unless
        // `openSettings` is called, and Flick never calls it (the AI
        // config opens via `AISettingsWindow.show`), so this stays a
        // no-op in practice.
        Settings {
            EmptyView()
        }
    }
}

/// `Flick.icns` loaded from the app bundle and shown in full colour in
/// the menu bar (Things / Spotify / Raycast style). We considered the
/// template-image path (`isTemplate = true`) for auto light/dark
/// adaptation, but `Flick.icns`'s design — a rounded gradient square
/// with thin "ae" text — collapses to a featureless solid silhouette
/// at 18pt. Keeping the colour is more recognisable.
///
/// Loaded from `MenuBarController.configureStatusItem()` and assigned
/// directly to the `NSStatusItem.button.image` (the previous
/// `MenuBarExtra` label view was more restrictive — see the commit
/// history of `MenuBarExtra` removal for the rendering constraints
/// we used to work around). Returns the raw `NSImage` rather than a
/// SwiftUI `Image` so the caller assigns it directly without any
/// SwiftUI modifiers getting in the way.
///
/// `Flick.icns` is 1024×1024 with multiple internal representations
/// (16/32/64/.../1024). We sidestep two issues with using it directly
/// by going through `cgImage(forProposedRect:)` at the menu-bar slot
/// size (22pt) and wrapping that in a fresh `NSImage` with `size` set
/// to 22×22 — `NSStatusItem` lays it out at 22pt, and the underlying
/// CGImage supplies enough pixels to look sharp at @2x.
enum MenuBarIcon {
    private static let renderSize = NSSize(width: 22, height: 22)

    static func nsImage() -> NSImage? {
        guard let path = Bundle.main.path(forResource: "Flick", ofType: "icns"),
              let source = NSImage(contentsOfFile: path) else { return nil }
        var proposedRect = NSRect(origin: .zero, size: renderSize)
        guard let cgImage = source.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else { return nil }
        return NSImage(cgImage: cgImage, size: renderSize)
    }
}