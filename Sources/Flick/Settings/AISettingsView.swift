import SwiftUI

struct AISettingsView: View {
    let store: ConfigStore
    @State private var draft: AIConfig
    @State private var testResult: String?
    @State private var isTesting = false
    @Environment(\.dismiss) private var dismiss

    init(store: ConfigStore) {
        self.store = store
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
                    dismiss()
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
