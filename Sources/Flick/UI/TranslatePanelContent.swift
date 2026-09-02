import SwiftUI

struct TranslatePanelContent: View {
    let onTranslate: (String, Locale.Language) async throws -> String

    @State private var input: String = ""
    @State private var targetCode: String = "en"
    @State private var state: TranslateState = .idle
    @State private var task: Task<Void, Never>?

    private static let languages: [(code: String, label: String)] = [
        ("en", "English"),
        ("zh-Hans", "简体中文"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("fr", "Français"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inputArea
            controlRow
            if !isIdle {
                Divider().padding(.vertical, 8)
                resultArea
            }
        }
        .padding(12)
        .frame(width: 320)
        .onDisappear { task?.cancel() }
    }

    private var isIdle: Bool {
        if case .idle = state { return true }
        return false
    }
    private var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }
    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var inputArea: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $input)
                .font(.body)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            if input.isEmpty {
                Text("输入原文")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 5)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 80, maxHeight: 160)
        .background(Color.primary.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            Picker("翻译成", selection: $targetCode) {
                ForEach(Self.languages, id: \.code) { lang in
                    Text(lang.label).tag(lang.code)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity)

            Button(action: triggerTranslate) {
                Text("翻译")
                    .frame(minWidth: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(trimmedInput.isEmpty || isLoading)
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private var resultArea: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading(let original):
            HStack(alignment: .top, spacing: 8) {
                ProgressView().controlSize(.small)
                Text(original)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .lineLimit(3)
            }
        case .success(let translation):
            Text(translation)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .failure(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button("重试") { triggerTranslate() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func triggerTranslate() {
        let text = trimmedInput
        guard !text.isEmpty else { return }
        let target = Locale.Language(identifier: targetCode)
        state = .loading(text)
        task?.cancel()
        task = Task {
            do {
                let result = try await onTranslate(text, target)
                if Task.isCancelled { return }
                await MainActor.run { state = .success(result) }
            } catch {
                if Task.isCancelled { return }
                let msg = (error as? TranslationError)?.errorDescription
                    ?? error.localizedDescription
                await MainActor.run { state = .failure(msg) }
            }
        }
    }
}

enum TranslateState: Equatable {
    case idle
    case loading(String)
    case success(String)
    case failure(String)
}
