import SwiftUI
import ApplicationServices

struct PermissionPromptView: View {
    var body: some View {
        Button("请在 系统设置 → 隐私与安全 → 辅助功能 中启用 Flick") {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
    }
}
