import AppKit
import Foundation
import os.log

private let monLog = Logger(subsystem: "com.cheriL.flick", category: "monitor")

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
    /// Posted when the previously-observed selection has cleared (e.g. the
    /// user clicked into an empty area, switched to an app that doesn't
    /// expose selection, or the frontmost app's selection went empty). The
    /// controller uses this to dismiss the lingering trigger button so it
    /// doesn't stay stuck on the screen at an old position.
    static let flickSelectionCleared = Notification.Name("Flick.selectionCleared")
}

final class TextSelectionMonitor {
    private let provider: SelectionProvider
    private let interval: TimeInterval
    private var timer: Timer?
    private var lastText: String?
    private var lastFrontmostPID: pid_t = 0
    private var tickCount: Int = 0

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
        tickCount += 1
        let frontmost = NSWorkspace.shared.frontmostApplication
        let frontName = frontmost?.localizedName ?? "?"
        let frontPID = frontmost?.processIdentifier ?? 0

        // Log when frontmost changes — that's the signal a new app was
        // activated. Also log every ~3s so a stuck-on-one-app state is
        // visible in the log.
        if frontPID != lastFrontmostPID {
            monLog.notice("frontmost -> \(frontName, privacy: .public) (pid \(frontPID, privacy: .public))")
            lastFrontmostPID = frontPID
        } else if tickCount % 10 == 0 {
            monLog.debug("still frontmost: \(frontName, privacy: .public) (pid \(frontPID, privacy: .public))")
        }

        guard let (text, _) = provider.currentSelection() else {
            // No selection in the frontmost app. If we previously had a
            // selection, signal the controller to dismiss the lingering
            // trigger panel so it doesn't sit at an old position forever.
            if lastText != nil {
                lastText = nil
                NotificationCenter.default.post(name: .flickSelectionCleared, object: nil)
            }
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && trimmed.count <= 5000 else {
            // Whitespace-only or too long — treat as cleared so the next
            // real selection isn't masked by an equal `lastText`.
            if lastText != nil {
                lastText = nil
                NotificationCenter.default.post(name: .flickSelectionCleared, object: nil)
            }
            return
        }
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