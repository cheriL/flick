import SwiftUI
import AppKit
import ApplicationServices

@main
struct FlickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // All Flick windows are AppKit-owned (MenuBarController, MenuPanelController,
        // AISettingsWindow). `Settings { EmptyView() }` keeps `@main App` compilable;
        // SwiftUI never instantiates it because we never call `openSettings`.
        Settings {
            EmptyView()
        }
    }
}

/// Loads `Flick.icns` from the bundle at 22pt (the menu-bar slot size) and returns
/// the raw `NSImage` so `MenuBarController.configureStatusItem` assigns it directly
/// to `statusItem.button.image`.
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