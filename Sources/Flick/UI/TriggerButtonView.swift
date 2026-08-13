import SwiftUI

struct TriggerButtonView: View {
    let isAI: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(isAI ? "AI" : "译")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(.regularMaterial)
                )
                .overlay(
                    Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .help(isAI ? "AI 翻译" : "普通翻译")
    }
}