import SwiftUI
import AppKit
import ApplicationServices
import Combine

struct MenuBarContent: View {
    let store: ConfigStore
    let onQuit: () -> Void

    @State private var showingAISettings = false
    /// Re-checked while the menu is visible. Updated via Combine from a
    /// 1 Hz timer that we start in `.onAppear` and stop in `.onDisappear`,
    /// so the timer only runs while the menu is actually open — no leak
    /// when the menu is closed.
    @State private var isTrusted = AXUIElement.isProcessTrusted
    @State private var ticker: AnyCancellable?

    var body: some View {
        content
            .onAppear {
                isTrusted = AXUIElement.isProcessTrusted
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
            Divider()
        }

        Text("⌘  按住 ⌘ 选词 → AI 翻译")
        Divider()
        Button("AI 设置…") { showingAISettings.toggle() }
            .popover(isPresented: $showingAISettings, arrowEdge: .bottom) {
                AISettingsView(store: store)
            }
        Divider()
        Button("退出 Flick", action: onQuit)
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
                Button("打开系统设置") {
                    PermissionGrant.openSystemSettingsAccessibility()
                    PermissionGrant.triggerAXPrompt()
                }
                Button("重启 Flick") {
                    PermissionGrant.relaunchSelf()
                }
                Button("重新检测") {
                    isTrusted = AXUIElement.isProcessTrusted
                }
            }
        }
        .padding(.vertical, 4)
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