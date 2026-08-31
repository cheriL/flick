import SwiftUI

/// Tailscale-style row: title + subtitle on the left, custom pill toggle on the right.
/// Wrapped in a `Button` for VoiceOver; the custom button style suppresses the system
/// "selected row" tint (the pill already communicates state).
struct SelectionToggleRow: View {
    @Binding var isOn: Bool
    var onChange: (Bool) -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Flick")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(isOn ? "已启用" : "已停用")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                TogglePill(isOn: isOn)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(SelectionToggleButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Flick")
        .accessibilityValue(isOn ? "已启用" : "已停用")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func toggle() {
        isOn.toggle()
        onChange(isOn)
    }
}

/// Suppresses the system "selected menu row" tint; keeps a subtle press highlight instead.
/// Plain `.plain` leaves the focus ring visible.
struct SelectionToggleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? Color.gray.opacity(0.18) : Color.clear)
            )
    }
}

/// Standalone pill switch used by `SelectionToggleRow`. Green pill on, gray pill off,
/// white knob slides between the two ends.
struct TogglePill: View {
    let isOn: Bool

    private let width: CGFloat = 32
    private let height: CGFloat = 18
    private let knobPadding: CGFloat = 2

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.green : Color.gray.opacity(0.55))
                .frame(width: width, height: height)
            Circle()
                .fill(Color.white)
                .frame(width: height - knobPadding * 2, height: height - knobPadding * 2)
                .padding(.horizontal, knobPadding)
                .shadow(color: .black.opacity(0.12), radius: 1, x: 0, y: 0.5)
        }
        .animation(.easeInOut(duration: 0.18), value: isOn)
    }
}
