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
            // Custom `Flick.icns` shown in full colour (Things / Spotify
            // / Raycast style). The template-image path was considered
            // but `Flick.icns`'s gradient + thin "ae" text collapses to
            // a featureless silhouette at 18pt — colour is more
            // recognisable. Trade-off: this icon does NOT auto-adapt to
            // the menu-bar's tint, so contrast against the menu bar is
            // whatever the .icns provides.
            //
            // We deliberately do NOT use TimelineView / Timer here —
            // `MenuBarExtra` label views that constantly re-render have
            // been observed to leak memory and (worse) vanish from the
            // menu bar entirely on some macOS versions.
            //
            // Falls back to an SF Symbol if the .icns is missing
            // (e.g. running from `.build/` before build-app.sh has
            // copied it in), so the menu bar always has an icon.
            if let icon = MenuBarIcon.nsImage() {
                Image(nsImage: icon)
            } else {
                Image(systemName: "character.bubble.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

/// `Flick.icns` loaded from the app bundle and shown in full colour in
/// the menu bar (Things / Spotify / Raycast style). We considered the
/// template-image path (`isTemplate = true`) for auto light/dark
/// adaptation, but `Flick.icns`'s design — a rounded gradient square
/// with thin "ae" text — collapses to a featureless solid silhouette
/// at 18pt. Keeping the colour is more recognisable.
///
/// Loading happens in a helper (not inline in `MenuBarExtra`'s
/// `@ViewBuilder`) because the builder treats every expression as a
/// `View` and won't compile side-effect statements. Returns the raw
/// `NSImage` rather than a SwiftUI `Image` so the caller can attach
/// `.resizable()` and `.frame(...)` without the helper's return type
/// fighting those modifiers (`.frame(width:height:)` erases to
/// `some View`, which can't be returned from a function declared as
/// returning `Image`).
///
/// `Flick.icns` is 1024×1024 with multiple internal representations
/// (16/32/64/.../1024). Three known issues with using it directly:
///   1. NSStatusItem via SwiftUI `Image(nsImage:)` fails to render
///      1024×1024 sources in `MenuBarExtra` (blank menu bar).
///   2. `NSImage.draw(in:from:)` into a `lockFocus`'d NSImage
///      produces a vertically-stretched, tiled result — the system
///      draws multiple reps on top of each other.
///   3. `.resizable().frame(width:height:)` inside `MenuBarExtra`'s
///      label view does not constrain the rendered size — the host
///      uses the NSImage's intrinsic `size` property, so a 64×64
///      NSImage renders at 64pt instead of the requested 18pt.
/// All three are sidestepped by going through `cgImage(forProposedRect:)`
/// at the menu-bar slot size (22pt) and wrapping that in a fresh
/// NSImage with `size` set to 22×22. SwiftUI `Image(nsImage:)` then
/// uses that intrinsic size, NSStatusItem lays it out as 22pt, and the
/// underlying CGImage supplies enough pixels to look sharp at @2x.
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