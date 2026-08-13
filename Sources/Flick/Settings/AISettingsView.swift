import SwiftUI

struct AISettingsView: View {
    let store: ConfigStore
    /// Invoked when the user dismisses the settings (save button or other
    /// dismiss path). The hosting window uses this to close itself. We
    /// don't use `@Environment(\.dismiss)` because the view can be hosted
    /// in either a SwiftUI popover (where it works) or a plain NSWindow
    /// (where there's no presentation to dismiss).
    let onDismiss: () -> Void
    @State private var draft: AIConfig
    @State private var testResult: String?
    @State private var isTesting = false

    init(store: ConfigStore, onDismiss: @escaping () -> Void = {}) {
        self.store = store
        self.onDismiss = onDismiss
        _draft = State(initialValue: store.load())
    }

    var body: some View {
        Form {
            Picker("服务商", selection: $draft.provider) {
                ForEach(Provider.allCases, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            TextField("Base URL", text: $draft.baseURL)
                .textFieldStyle(.roundedBorder)
            SecureField("API Key", text: $draft.apiKey)
                .textFieldStyle(.roundedBorder)
            TextField("模型", text: $draft.model)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("测试连接") { runTest() }
                    .disabled(isTesting || draft.apiKey.isEmpty)
                if let r = testResult {
                    Text(r).font(.caption).foregroundStyle(r.hasPrefix("✓") ? .green : .red)
                }
            }

            HStack {
                Spacer()
                Button("保存") {
                    store.save(draft)
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private func runTest() {
        isTesting = true
        testResult = nil
        Task {
            let svc = OpenAICompatibleService(config: draft)
            do {
                let translated = try await svc.translate("hello", to: Locale.Language(identifier: "zh-Hans"))
                await MainActor.run {
                    testResult = "✓ \(translated)"
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = "✗ \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }
}
