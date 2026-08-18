import SwiftUI

enum ResultState: Equatable {
    case loading
    case success(String)
    case failure(String)
}

struct ResultWindowView: View {
    let original: String
    let state: ResultState
    let isAI: Bool
    let onRetry: () -> Void

    // MARK: - Test hooks
    //
    // SwiftUI renders `Image(systemName:)` into private view classes that
    // don't expose the symbol name. We expose what each branch would draw
    // so tests can assert icon selection and accent-bar visibility without
    // walking the rendered tree.

    /// `true` if the loading branch renders the AI sparkle icon, `false` if
    /// it falls back to `ProgressView`. Only meaningful for `.loading`.
    var loadingIconName: String? {
        guard isAI else { return nil }
        return "sparkles"
    }

    /// Label shown in the loading branch.
    var loadingLabel: String { isAI ? "AI 翻译中…" : "翻译中…" }

    /// SF Symbol shown next to the failure message.
    var failureIconName: String? { "xmark.circle" }

    /// `true` when the AI gradient bar should appear at the top of the panel.
    var showsAIAccentBar: Bool { isAI }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isAI {
                LinearGradient(
                    colors: [.purple, .blue, .green],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 3)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(original)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Divider().opacity(0.4)

                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(width: 360)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            HStack(spacing: 8) {
                if isAI {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundStyle(.purple)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(loadingLabel)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        case .success(let text):
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .failure(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 6) {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                    Button("重试", action: onRetry)
                        .controlSize(.small)
                }
            }
        }
    }
}