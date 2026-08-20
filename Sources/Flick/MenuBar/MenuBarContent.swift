import SwiftUI
import AppKit
import ApplicationServices
import Combine

struct MenuBarContent: View {
    let store: ConfigStore
    let onQuit: () -> Void

    /// Re-checked while the menu is visible. Updated via Combine from a
    /// 1 Hz timer that we start in `.onAppear` and stop in `.onDisappear`,
    /// so the timer only runs while the menu is actually open — no leak
    /// when the menu is closed.
    @State private var isTrusted = AXUIElement.isProcessTrusted
    @State private var ticker: AnyCancellable?
    /// Live mirror of the global "selection enabled" toggle. Initialised
    /// from `ConfigStore` in `.onAppear` and updated when the user flips
    /// the menu-bar switch. Persisted via `store.setSelectionEnabled`
    /// which also posts the notification the controller listens for.
    @State private var selectionEnabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(8)
        .frame(width: 210)
        // `.regularMaterial` gives the panel a frosted-glass look like
        // Tailscale's menu — the desktop bleeds through subtly, which
        // softens the contrast against the user's other windows and
        // makes the hairline dividers below readable on any wallpaper.
        .background(.regularMaterial)
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

        // The single Tailscale-style row that doubles as the hint and
        // the kill-switch. The previous static `⌘ 按住 ⌘ 选词 → AI 翻译`
        // label was removed by user request — the subtitle below the
        // title now carries the same hint, and the toggle on the right
        // is the action.
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

        // Original Flick menu (and Tailscale) put a separator between
        // "Settings…" and "Quit" to mark Quit as a terminal action that
        // shouldn't be visually grouped with the configuration options
        // above. Restored here after the refactor dropped it.
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

    /// Hairline separator between sections. `Color.primary.opacity(0.10)`
    /// gives a reliable contrast against any material — the
    /// `Color.secondary` variant we tried before collapsed into the
    /// panel background on the light system appearance and vanished
    /// entirely. The horizontal insets match the action row's
    /// horizontal padding so the line breaks cleanly under the label
    /// column rather than running edge-to-edge. Vertical padding
    /// matches the breathing room in the Tailscale reference.
    private var thinDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(MenuActionButtonStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Plain-button style for the action rows in the popover. Matches the
/// native NSMenu item look: full-width hit area, ~20pt row height
/// (reduced 1/4 from the original 26pt), and a subtle press highlight.
/// The fixed height keeps the three action rows visually even — without
/// it, the divider + VStack spacing produces uneven gaps depending on
/// label length.
struct MenuActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
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

    /// Relaunches this app fresh — needed because macOS only honours an
    /// Accessibility grant after the process restarts; the existing
    /// process keeps getting `AXIsProcessTrusted() == false` until then.
    static func relaunchSelf() {
        let bundlePath = Bundle.main.bundlePath
        // Spawn a tiny shell that waits for us to exit, then opens the
        // .app again. Calling `NSWorkspace.openApplication` from inside
        // `applicationWillTerminate` is unreliable, hence the detour.
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 0.2 && open \"\(bundlePath)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// Launches Google Chrome with the `--force-renderer-accessibility` flag
/// so Chrome's renderer process exposes web content to macOS Accessibility.
/// Without this, `AXUIElement` calls into Chrome's web content fail
/// (Chrome's main process tree doesn't include the `AXWebArea`s, only the
/// owning window) and Flick can't read selected text in web pages.
enum ChromeLaunch {
    static func launchWithAccessibilityFlag() {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "open -a \"Google Chrome\" --args --force-renderer-accessibility"]
        try? task.run()
    }
}

/// Hosts the AI settings SwiftUI view in a regular `NSWindow`.
///
/// We can't use a SwiftUI `.popover` from inside `MenuBarExtra`'s default
/// menu-style content: when the user clicks a menu item, the menu
/// dismisses immediately and the popover's anchor view is gone before the
/// popover can present. A standalone window has its own lifecycle and is
/// shown reliably from a menu click.
///
/// A single instance is reused — calling `show` again just brings the
/// existing window forward — so clicking the menu item twice doesn't
/// stack settings windows.
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
        // Auto-size to the SwiftUI view's intrinsic size. AISettingsView
        // declares `frame(width: 440)` plus the form's section padding;
        // this just nudges the initial content size to a reasonable
        // default. macOS will then grow/shrink the window as the view
        // reports a different intrinsic size.
        w.setContentSize(NSSize(width: 440, height: 360))
        w.center()
        // If the user closes via the red traffic-light button, drop the
        // cached reference so the next menu click re-creates a fresh one.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            if window === w { window = nil }
        }
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}