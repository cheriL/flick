import AppKit
import Foundation

protocol SelectionProvider {
    /// Returns the currently selected text and the owning process id, or nil.
    func currentSelection() -> (text: String, pid: pid_t)?
}

struct AXSelectionProvider: SelectionProvider {
    func currentSelection() -> (text: String, pid: pid_t)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        guard let text = AXUIElement.selectedText(in: app.processIdentifier) else { return nil }
        return (text, app.processIdentifier)
    }
}

extension Notification.Name {
    static let flickSelectionChanged = Notification.Name("Flick.selectionChanged")
}

final class TextSelectionMonitor {
    private let provider: SelectionProvider
    private let interval: TimeInterval
    private var timer: Timer?
    private var lastText: String?
    private var hasSeenValid = false

    init(provider: SelectionProvider, interval: TimeInterval = 0.3) {
        self.provider = provider
        self.interval = interval
    }

    func start() {
        stop()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard let (text, _) = provider.currentSelection() else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isValid = !trimmed.isEmpty && trimmed.count <= 5000

        // The first valid selection just establishes the baseline —
        // we can't tell if it "changed" or was already this way when we started.
        if !hasSeenValid {
            hasSeenValid = true
            if isValid { lastText = trimmed }
            return
        }

        guard isValid else { return }
        if trimmed == lastText { return }
        lastText = trimmed

        let cmdHeld = NSEvent.modifierFlags.contains(.command)
        let mouse = NSEvent.mouseLocation

        NotificationCenter.default.post(
            name: .flickSelectionChanged,
            object: nil,
            userInfo: [
                "text": trimmed,
                "isAI": cmdHeld,
                "cursor": NSValue(point: mouse),
            ]
        )
    }
}