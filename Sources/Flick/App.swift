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

