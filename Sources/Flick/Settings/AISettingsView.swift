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
            sectionHeader("Model")

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text("Base URL")
                        .frame(width: 108, alignment: .trailing)
                        .foregroundStyle(.primary)
                    PresetComboBox(text: $draft.baseURL, items: BaseURLPresets.all)
                        .frame(width: 280, height: 22)
                }
                configField("API Key", text: $draft.apiKey, secure: true)
                configField("Model", text: $draft.model)

                HStack(spacing: 12) {
                    Text("Reasoning")
                        .frame(width: 108, alignment: .trailing)
                        .foregroundStyle(.primary)
                    Toggle("", isOn: Binding(
                        get: { !draft.disableThinking },
                        set: { draft.disableThinking = !$0 }
                    ))
                    .labelsHidden()
                }

                HStack(alignment: .center, spacing: 12) {
                    SelectableText(
                        text: testResult ?? "",
                        color: testResult.map { $0.hasPrefix("✓") ? Color.green : Color.red } ?? .primary
                    )
                    .padding(.leading, 120)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("Test") { runTest() }
                            .disabled(isTesting || draft.apiKey.isEmpty)
                    }
                }
            }
            .padding(.horizontal, 20)

            sectionDivider

            sectionHeader("General")

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text("Auto Start")
                        .frame(width: 108, alignment: .trailing)
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
                        .padding(.leading, 120)
                }

                HStack(spacing: 12) {
                    Text("Chrome AX Mode")
                        .frame(width: 108, alignment: .trailing)
                        .foregroundStyle(.primary)
                    Button("Launch") {
                        ChromeLaunch.launchWithAccessibilityFlag()
                    }
                }
            }
            .padding(.horizontal, 20)

            HStack {
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 440)
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
            autoStartError = "Failed to change Auto Start: \(error.localizedDescription)"
        }
    }

    /// One row of the config table. Frame is applied to the leaf `TextField` (not a wrapping
/// `Group`) so a long URL doesn't stretch the row.
    @ViewBuilder
    private func configField(_ label: String, text: Binding<String>, secure: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 108, alignment: .trailing)
                .foregroundStyle(.primary)
            if secure {
                SecureField("", text: text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280, height: 22)
            } else {
                TextField("", text: text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280, height: 22)
            }
        }
    }

    private func runTest() {
        isTesting = true
        testResult = nil
        Task {
            let svc = OpenAICompatibleService(config: draft)
            do {
                let translated = try await svc.translate("你好", to: Locale.Language(identifier: "en"))
                await MainActor.run {
                    testResult = "✓ \(translated.translation)"
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

/// Launches Chrome with `--force-renderer-accessibility` so its renderer exposes web content
/// to AX. Fallback for when Chrome's AppleScript path is unavailable (dev setting off /
/// Automation denied); without the flag Chrome's AX tree has no `AXWebArea`.
enum ChromeLaunch {
    static func launchWithAccessibilityFlag() {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "open -a \"Google Chrome\" --args --force-renderer-accessibility"]
        try? task.run()
    }
}

/// Built-in OpenAI-compatible endpoints. Each carries its version prefix — the
/// endpoint builder appends only `/chat/completions`.
enum BaseURLPresets {
    static let all = [
        "https://api.openai.com/v1",
        "https://api.deepseek.com/v1",
        "https://open.bigmodel.cn/api/paas/v4",
        "https://open.bigmodel.cn/api/coding/paas/v4",
    ]
}

/// NSComboBox wrapper — preset endpoints in the dropdown, free-form typing still
/// works. SwiftUI has no native combo box.
private struct PresetComboBox: NSViewRepresentable {
    @Binding var text: String
    let items: [String]

    func makeNSView(context: Context) -> NSComboBox {
        let box = NSComboBox()
        box.addItems(withObjectValues: items)
        box.isEditable = true
        box.completes = false
        box.placeholderString = "https://api.openai.com/v1"
        box.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        box.numberOfVisibleItems = items.count
        box.delegate = context.coordinator
        box.stringValue = text
        return box
    }

    func updateNSView(_ box: NSComboBox, context: Context) {
        context.coordinator.parent = self
        if box.stringValue != text {
            box.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: PresetComboBox
        init(_ parent: PresetComboBox) { self.parent = parent }

        // List pick: read the selected item, not stringValue — the action-based
        // sync raced AppKit and saved the pre-pick value.
        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let box = notification.object as? NSComboBox else { return }
            let idx = box.indexOfSelectedItem
            if idx >= 0, idx < parent.items.count {
                parent.text = parent.items[idx]
            } else {
                parent.text = box.stringValue
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let box = notification.object as? NSComboBox else { return }
            parent.text = box.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let box = notification.object as? NSComboBox else { return }
            parent.text = box.stringValue
        }
    }
}
