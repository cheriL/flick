import SwiftUI

enum ResultState: Equatable {
    case loading
    case success(String)
    case failure(String)
}

struct ResultWindowView: View {
    let original: String
    let state: ResultState
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(original)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Divider().opacity(0.4)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(width: 360)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("翻译中…").font(.system(size: 14)).foregroundStyle(.secondary)
            }
        case .success(let text):
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .failure(let message):
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
