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

    /// Opens System Settings directly to the Accessibility privacy pane.
    /// URL scheme is documented Apple behaviour (macOS 13+).
    static func openSystemSettingsAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}