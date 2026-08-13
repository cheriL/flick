import SwiftUI
import AppKit
import ApplicationServices

struct MenuBarContent: View {
    let store: ConfigStore
    let onQuit: () -> Void

    @State private var showingAISettings = false

    var body: some View {
        // TimelineView re-evaluates the closure every second while the menu
        // is visible, which makes `AXIsProcessTrusted()` re-check itself —
        // no `@State` round-trip needed. The view is torn down when the menu
        // closes, so there's no background cost.
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if !AXUIElement.isProcessTrusted {
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
                    // No-op: TimelineView already re-checks every second.
                    // Kept as a discoverable affordance for users who'd
                    // rather not wait up to a second.
                }
            }
        }
        .padding(.vertical, 4)
    }
}

enum PermissionGrant {
    /// Triggers the system "Flick wants to control your computer" prompt.
    /// Belt-and-suspenders: the prompt fires automatically on the very
    /// first AX call, but on some macOS versions it does not appear if
    /// the user previously dismissed it. This re-shows it.
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