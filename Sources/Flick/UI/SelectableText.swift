import SwiftUI
import AppKit

/// Read-only selectable text backed by AppKit — SwiftUI's `.textSelection(.enabled)`
/// drops click hit-testing on macOS 26 after the view is re-inserted or focus moves.
/// Content beyond the height cap scrolls instead of stretching the panel.
struct SelectableText: NSViewRepresentable {
    let text: String
    let color: Color
    var font: NSFont = NSFont.systemFont(ofSize: 12)
    /// `nil` = no cap (an outer ScrollView owns scrolling).
    var maxHeight: CGFloat? = 80

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.focusRingType = .none
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.sizeToFit()
        }
        textView.font = font
        textView.textColor = NSColor(color)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0,
              let textView = scroll.documentView as? NSTextView else { return nil }
        if textView.string != text {
            textView.string = text
            textView.sizeToFit()
        }
        guard !text.isEmpty else { return CGSize(width: width, height: 0) }
        let container = textView.textContainer!
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        let layout = textView.layoutManager!
        layout.ensureLayout(for: container)
        let natural = max(layout.usedRect(for: container).height, 14)
        let capped = maxHeight.map { min(natural, $0) } ?? natural
        return CGSize(width: width, height: ceil(capped))
    }
}
