import SwiftUI

/// Tailscale-style menu-bar row: title + subtitle on the left, custom
/// pill toggle on the right. Used as the global on/off switch for the
/// selection-to-translate feature.
///
/// Why custom rather than a plain `Toggle`:
/// 1. `MenuBarExtra` with `.menu` style bridges SwiftUI to NSMenuItems,
///    where a stock `Toggle` renders as a checkmark — not the look the
///    brief asked for. We force `.window` style in `App.swift` so this
///    view gets to render itself.
/// 2. The visual (rounded pill, color tints, two-line label) is
///    specific enough that a stock `.switch` style wouldn't match
///    either.
///
/// We deliberately wrap in a `Button` (not a plain tappable view) so
/// VoiceOver announces it as a button. The custom button style below
/// suppresses the macOS "selected row" tint that SwiftUI otherwise
/// applies to buttons inside a `MenuBarExtra` `.window` panel — that
/// tint is the blue rectangle the user complained about. The pill
/// already communicates state; we don't need a second visual cue.
struct SelectionToggleRow: View {
    @Binding var isOn: Bool
    var onChange: (Bool) -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Flick")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(isOn ? "已启用" : "已停用")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                TogglePill(isOn: isOn)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
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

/// Suppresses the system "selected menu row" tint (`Color.accentColor`
/// rectangle) that `MenuBarExtra` `.window` adds to every Button, and
/// keeps a subtle press feedback instead. Plain `.plain` isn't enough
/// — it leaves the focus ring visible on the panel background.
struct SelectionToggleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? Color.gray.opacity(0.18) : Color.clear)
            )
    }
}

/// Standalone pill switch used by `SelectionToggleRow`. Green pill on,
/// gray pill off, white knob slides between the two ends. Sized to
/// match the visual weight of the 12pt title beside it — the 38pt
/// version was proportionally too big once the title shrank.
struct TogglePill: View {
    let isOn: Bool

    private let width: CGFloat = 28
    private let height: CGFloat = 16
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
