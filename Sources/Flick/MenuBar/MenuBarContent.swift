import SwiftUI
import AppKit
import ApplicationServices
import Combine

struct MenuBarContent: View {
    let store: ConfigStore
    let onQuit: () -> Void

    /// Re-checked while the menu is visible via a 1 Hz Combine timer started in `.onAppear`.
    @State private var isTrusted = AXUIElement.isProcessTrusted
    @State private var ticker: AnyCancellable?
    /// Live mirror of `ConfigStore.isSelectionEnabled`. Persisting via
    /// `store.setSelectionEnabled` posts the notification `MenuBarController` listens for.
    @State private var selectionEnabled: Bool = true

    var body: some View {
        // `GlassEffectContainer` is required for `.glassEffect` to sample wallpaper; bare
        // modifiers render only as a tint.
        GlassEffectContainer(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(8)
            .frame(width: 210)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))
        }
        .onAppear {
            isTrusted = AXUIElement.isProcessTrusted
            selectionEnabled = store.isSelectionEnabled
            ticker = Timer.publish(every: 1.0, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    let now = AXUIElement.isProcessTrusted
                    if now != isTrusted { isTrusted = now }
                }
        }
        .onDisappear { ticker?.cancel(); ticker = nil }
    }

    @ViewBuilder
    private var content: some View {
        if !isTrusted {
            permissionWarning
            thinDivider
        }

        // Tailscale-style row: title + subtitle on the left, pill toggle on the right.
        SelectionToggleRow(
            isOn: Binding(
                get: { selectionEnabled },
                set: { newValue in
                    selectionEnabled = newValue
                    store.setSelectionEnabled(newValue)
                }
            ),
            onChange: { _ in }
        )

        thinDivider

        actionButton("启动 Chrome (辅助模式)") {
            ChromeLaunch.launchWithAccessibilityFlag()
        }
        actionButton("设置…") {
            AISettingsWindow.show(store: store)
        }

        // Separator marks Quit as a terminal action.
        thinDivider

        actionButton("退出", action: onQuit)
            .keyboardShortcut("q")
    }

    private var permissionWarning: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("⚠️ 需要辅助功能权限")
                .font(.headline)
            Text("Flick 需要读取选中文字。\n请在 系统设置 → 隐私与安全 → 辅助功能 中启用 Flick。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("系统设置") {
                    PermissionGrant.openSystemSettingsAccessibility()
                    PermissionGrant.triggerAXPrompt()
                }
                Button("重启") {
                    PermissionGrant.relaunchSelf()
                }
                Button("检测") {
                    isTrusted = AXUIElement.isProcessTrusted
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Hairline separator using `Color.primary.opacity(0.10)` — reads against any material.
    private var thinDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(MenuActionButtonStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Plain button style for the action rows. Native NSMenu look: full-width hit area,
/// ~26pt fixed row height so the three rows stay visually even, subtle press highlight.
struct MenuActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(configuration.isPressed ? Color.accentColor.opacity(0.20) : Color.clear)
            )
            .contentShape(Rectangle())
    }
}

enum PermissionGrant {
    /// Triggers the system "Flick wants to control your computer" prompt.
    static func triggerAXPrompt() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// Opens System Settings directly to the Accessibility pane.
    /// We try the canonical URL first, fall back to the universal-access
    /// root if macOS rejects it (different releases accept different
    /// spellings).
    static func openSystemSettingsAccessibility() {
        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
            URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess"),
        ].compactMap { $0 }
        for url in urls where NSWorkspace.shared.open(url) {
            return
        }
    }

    /// Relaunches this app fresh — macOS only honours a new Accessibility grant after
    /// the process restarts; the current process keeps seeing `isProcessTrusted == false`.
    static func relaunchSelf() {
        let bundlePath = Bundle.main.bundlePath
        // Tiny shell waits for us to exit, then opens the .app. `NSWorkspace.openApplication`
        // from inside `applicationWillTerminate` is unreliable, hence the detour.
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 0.2 && open \"\(bundlePath)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// Launches Chrome with `--force-renderer-accessibility` so its renderer exposes web content
/// to AX. Without it, `AXUIElement` calls into Chrome's web content see no `AXWebArea` and
/// Flick can't read selected text on web pages.
enum ChromeLaunch {
    static func launchWithAccessibilityFlag() {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "open -a \"Google Chrome\" --args --force-renderer-accessibility"]
        try? task.run()
    }
}

/// Hosts `AISettingsView` in a standalone `NSWindow` so it has its own lifecycle and survives
/// menu dismissal. A single instance is reused across `show` calls.
enum AISettingsWindow {
    private static var window: NSWindow?

    static func show(store: ConfigStore) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: AISettingsView(store: store) {
            window?.close()
            window = nil
        })
        let w = NSWindow(contentViewController: host)
        w.title = "Flick 设置"
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.isReleasedWhenClosed = false
        // Initial content-size hint for the first paint; SwiftUI's intrinsic-size layout takes over.
        w.setContentSize(NSSize(width: 400, height: 320))
        w.center()
        // Drop the cached reference if the user closes via the traffic-light button,
        // so the next menu click re-creates a fresh one.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            if window === w { window = nil }
        }
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}