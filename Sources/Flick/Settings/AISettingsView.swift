import SwiftUI
import ServiceManagement

struct AISettingsView: View {
    let store: ConfigStore
    /// Invoked when the user dismisses the settings. We don't use `@Environment(\.dismiss)`
    /// because the view can be hosted in either a popover or a plain NSWindow.
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
        // Flat VStack with bold `Text` headers — no `Form` / `Section` containers.
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("模型配置")

            VStack(alignment: .leading, spacing: 10) {
                configField("Base URL", text: $draft.baseURL,
                            placeholder: "https://api.openai.com/v1")
                configField("API Key", text: $draft.apiKey, secure: true)
                configField("Model", text: $draft.model)

                HStack(alignment: .top, spacing: 12) {
                    Button("测试连接") { runTest() }
                        .disabled(isTesting || draft.apiKey.isEmpty)
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    if let r = testResult {
                        Text(r)
                            .font(.caption)
                            .foregroundStyle(r.hasPrefix("✓") ? .green : .red)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 20)

            sectionDivider

            sectionHeader("通用")

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("开机自启动")
                        .frame(width: 80, alignment: .trailing)
                        .foregroundStyle(.primary)
                    Toggle("", isOn: Binding(
                        get: { autoStartEnabled },
                        set: { newValue in setAutoStart(newValue) }
                    ))
                    .labelsHidden()
                }
                if let err = autoStartError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.leading, 92)
                }
            }
            .padding(.horizontal, 20)

            HStack {
                Spacer()
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 400)
    }

    /// Bold section title — flat, non-rounded header.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    /// Hairline rule between sections. Matches the menu-bar divider style.
    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(height: 1)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
    }

    private func setAutoStart(_ enabled: Bool) {
        do {
            if enabled { try AutoStart.enable() } else { try AutoStart.disable() }
            autoStartEnabled = AutoStart.isEnabled
            autoStartError = nil
        } catch {
            // Reflect actual OS state — if register() threw, the toggle is still off.
            autoStartEnabled = AutoStart.isEnabled
            autoStartError = "无法更改自启动设置：\(error.localizedDescription)"
        }
    }

    /// One row of the config table. Frame is applied to the leaf `TextField` (not a wrapping
/// `Group`) so a long URL doesn't stretch the row.
    @ViewBuilder
    private func configField(_ label: String, text: Binding<String>, secure: Bool = false,
                             placeholder: String = "") -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 80, alignment: .trailing)
                .foregroundStyle(.primary)
            if secure {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 268, height: 22)
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 268, height: 22)
            }
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
