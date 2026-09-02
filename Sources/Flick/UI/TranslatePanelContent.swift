import SwiftUI

struct TranslatePanelContent: View {
    let onTranslate: (String, Locale.Language) async throws -> String
    let onTaskStart: (Task<Void, Never>) -> Void

    @State private var input: String = ""
    @State private var targetCode: String = "en"
    @State private var state: TranslateState = .idle

    private static let languages: [(code: String, label: String)] = [
        ("en", "English"),
        ("zh-Hans", "简体中文"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("fr", "Français"),
    ]

    var body: some View {
        GlassEffectContainer(spacing: 0) {
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
            .glassEffect(.regular, in: .rect(cornerRadius: 10))
        }
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
        TranslateTextView(text: $input)
            .frame(minHeight: 80, maxHeight: 160)
            .background(Color.primary.opacity(0.05))
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
        let task = Task {
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
        onTaskStart(task)
    }
}

enum TranslateState: Equatable {
    case idle
    case loading(String)
    case success(String)
    case failure(String)
}

/// SwiftUI's `TextEditor` doesn't promote its underlying `NSTextView` to first
/// responder when hosted in an NSPanel — the hosting controller sits between
/// the window and the SwiftUI-rendered text view in the responder chain.
private struct TranslateTextView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.focusRingType = .none
        textView.textContainerInset = NSSize(width: 5, height: 8)
        textView.string = text
        DispatchQueue.main.async { [weak textView] in
            guard let textView, let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: TranslateTextView
        init(_ parent: TranslateTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
