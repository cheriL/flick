import SwiftUI

struct MenuBarContent: View {
    let store: ConfigStore
    @State private var showingAISettings = false
    let onQuit: () -> Void

    var body: some View {
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
}
