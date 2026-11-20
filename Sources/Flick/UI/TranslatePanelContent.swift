import SwiftUI

struct TranslatePanelContent: View {
    let onTranslate: (String, Locale.Language, @escaping (String) -> Void) async throws -> TranslationResult
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
                    ScrollView(.vertical) {
                        resultArea
                    }
                    .frame(maxHeight: 240)
                    .fixedSize(horizontal: false, vertical: true)
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
        if case .partial = state { return true }
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
            Picker("Translate to", selection: $targetCode) {
                ForEach(Self.languages, id: \.code) { lang in
                    Text(lang.label).tag(lang.code)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity)

            Button(action: triggerTranslate) {
                Text("Translate")
                    .frame(minWidth: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(trimmedInput.isEmpty || isLoading)
        }
        .padding(.top, 10)
    }

    private func readingRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
            SelectableText(text: value,
                           color: .secondary,
                           font: NSFont.systemFont(ofSize: 12),
                           maxHeight: nil)
        }
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
        case .success(let result):
            VStack(alignment: .leading, spacing: 6) {
                SelectableText(text: result.translation,
                               color: .primary,
                               font: NSFont.systemFont(ofSize: 13),
                               maxHeight: nil)
                if let source = result.sourcePronunciation {
                    readingRow(label: "Source", value: source)
                }
                if let target = result.targetPronunciation {
                    readingRow(label: "Translation", value: target)
                }
            }
        case .partial(let text):
            SelectableText(text: text,
                           color: .primary,
                           font: NSFont.systemFont(ofSize: 13),
                           maxHeight: nil)
        case .failure(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry") { triggerTranslate() }
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
        var lastShown: String?
        var lastRender = Date.distantPast
        let task = Task {
            do {
                let result = try await onTranslate(text, target) { partial in
                    guard let presentable = Provider.partialTranslation(from: partial),
                          presentable != lastShown,
                          Date().timeIntervalSince(lastRender) >= 0.05 else { return }
                    lastShown = presentable
                    lastRender = Date()
                    let snapshot = presentable
                    Task { @MainActor in
                        state = .partial(snapshot)
                    }
                }
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
    /// Translation still streaming in — rendered like the final text, without
    /// pronunciation rows (those are only known once the full response is parsed).
    case partial(String)
    case success(TranslationResult)
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
