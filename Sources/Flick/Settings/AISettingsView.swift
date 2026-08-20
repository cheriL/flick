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
        // Tailscale-style flat layout: no `Form` / `Section` containers,
        // just a plain `VStack` with section headers as bold `Text`. The
        // grouped form we had before was the reason the three inputs
        // refused to stay aligned — Form's auto-sizing kept the rounded
        // gray container expanding around whatever the TextFields asked
        // for, and the labels drifted with the placeholders.
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("OpenAI")

            VStack(alignment: .leading, spacing: 10) {
                configField("Base URL", text: $draft.baseURL)
                configField("API Key", text: $draft.apiKey, secure: true)
                configField("模型", text: $draft.model)

                HStack {
                    if let r = testResult {
                        Text(r)
                            .font(.caption)
                            .foregroundStyle(r.hasPrefix("✓") ? .green : .red)
                    }
                    Spacer()
                    Button("测试连接") { runTest() }
                        .disabled(isTesting || draft.apiKey.isEmpty)
                }
            }
            .padding(.horizontal, 20)

            sectionDivider

            sectionHeader("通用")

            VStack(alignment: .leading, spacing: 8) {
                Toggle("开机自启动", isOn: Binding(
                    get: { autoStartEnabled },
                    set: { newValue in setAutoStart(newValue) }
                ))
                if let err = autoStartError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
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

    /// Bold section title used as a flat, non-rounded header (Tailscale
    /// doesn't put section bodies in inset cards). The top padding gives
    /// the title the same breathing room the section header had inside
    /// the previous `Form` `Section`.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    /// Hairline rule between sections. We use `Color.primary.opacity(0.10)`
    /// — the same value the menu bar uses — so the settings panel and
    /// the menu bar share one separator style.
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
            // Reflect the actual OS state — if register() threw, the
            // toggle is still off. Keep the user's intended value out of
            // the UI so they see what's really true.
            autoStartEnabled = AutoStart.isEnabled
            autoStartError = "无法更改自启动设置：\(error.localizedDescription)"
        }
    }

    /// One row of the OpenAI config table: right-aligned label in a
    /// fixed-width column, fixed-width input on the right. Widths
    /// chosen so three rows line up under each other inside a 400pt
    /// panel — 80pt label + 12pt spacing + 268pt input = 360pt, which
    /// exactly fills the 20pt horizontal padding on each side.
///
/// The frame is applied directly to the leaf `TextField`/`SecureField`
    /// (not to a wrapping `Group`). On this build SwiftUI's macOS
    /// `TextField` re-proposes its intrinsic content width when the
    /// typed string grows, and that proposal leaks through a `Group`
    /// container — the row visibly stretches when you type a long URL
    /// or key. Putting `.frame(width:height:)` on the leaf pins both
    /// axes and stops the drift.
    @ViewBuilder
    private func configField(_ label: String, text: Binding<String>, secure: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 80, alignment: .trailing)
                .foregroundStyle(.primary)
            if secure {
                SecureField("", text: text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 268, height: 22)
            } else {
                TextField("", text: text)
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
