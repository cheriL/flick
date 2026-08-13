import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()
    let store = ConfigStore()
    let panel = FloatingPanelController()
    lazy var controller = MenuBarController(store: store, panel: panel)

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestAccessibilityIfNeeded()
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}
