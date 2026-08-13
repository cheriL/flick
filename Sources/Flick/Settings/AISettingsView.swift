import SwiftUI
import ServiceManagement

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
    @State private var autoStartEnabled: Bool = AutoStart.isEnabled
    @State private var autoStartError: String?

    init(store: ConfigStore, onDismiss: @escaping () -> Void = {}) {
        self.store = store
        self.onDismiss = onDismiss
        _draft = State(initialValue: store.load())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("OpenAI") {
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
                }

                Section("通用") {
                    Toggle("开机自启动", isOn: Binding(
                        get: { autoStartEnabled },
                        set: { newValue in
                            setAutoStart(newValue)
                        }
                    ))
                    if let err = autoStartError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 440)
    }

    private func setAutoStart(_ enabled: Bool) {
        do {
            if enabled { try AutoStart.enable() } else { try AutoStart.disable() }
            autoStartEnabled = AutoStart.isEnabled
            autoStartError = nil
        } catch {
            // Reflect the actual OS state — if register() threw, the
            // toggle is still off. Keep the user's intended value out of
            // the UI so they see what's really true.
            autoStartEnabled = AutoStart.isEnabled
            autoStartError = "无法更改自启动设置：\(error.localizedDescription)"
        }
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

    private func save() {
        store.save(draft)
        onDismiss()
    }
}
