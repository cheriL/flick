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
    /// Posted when the previously-observed selection has cleared. Controller uses this to
    /// dismiss a lingering trigger button at an old position.
    static let flickSelectionCleared = Notification.Name("Flick.selectionCleared")
    /// Posted when the user flips the menu-bar "selection enabled" switch. Controller forwards
    /// the new value to the monitor so polling stops/starts immediately.
    static let flickSelectionEnabledChanged = Notification.Name("Flick.selectionEnabledChanged")
}

final class TextSelectionMonitor {
    private let provider: SelectionProvider
    private let interval: TimeInterval
    private var timer: Timer?
    private var flagsMonitor: Any?
    private var lastText: String?
    private var lastIsAI: Bool = false
    /// Cursor position at the moment the current `lastText` was first seen. Frozen across ⌘ toggles
    /// so the trigger button doesn't jump when the cursor moves between selection and modifier change.
    private var lastCursor: NSPoint = .zero
    /// Set when the user taps the trigger button (or a translation finishes). While set, the monitor
    /// suppresses all notifications for that text — the user has already acted on it. Cleared when
    /// the selection is dropped.
    private var consumedText: String?
    private var lastFrontmostPID: pid_t = 0
    private var tickCount: Int = 0
    /// Global kill-switch from the menu-bar toggle. When `false` the monitor still ticks (so
    /// `flagsMonitor` keeps responding to ⌘ toggles), but `poll` short-circuits before AX or
    /// notifications, and any previously-seen selection is forgotten.
    var isEnabled: Bool = true

    init(provider: SelectionProvider, interval: TimeInterval = 0.3) {
        self.provider = provider
        self.interval = interval
    }

    /// Mark the current selection as "consumed" — typically called from
    /// the trigger button's tap handler. The monitor will not emit
    /// another `flickSelectionChanged` for this text until the selection
    /// is cleared and a new one is made.
    func markConsumed() {
        consumedText = lastText
    }

    func start() {
        stop()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // React to ⌘ / ⇧ / ⌥ / ⌃ changes immediately so the trigger button's "AI" vs "译" label updates
        // when the user toggles ⌘ after selecting.
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.poll()
            return event
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
        flagsMonitor = nil
    }

    private func poll() {
        tickCount += 1
        // Toggle off: skip AX, drop any lingering selection so the trigger doesn't stay on screen.
        guard isEnabled else {
            if lastText != nil {
                lastText = nil
                lastIsAI = false
                consumedText = nil
                NotificationCenter.default.post(name: .flickSelectionCleared, object: nil)
            }
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let frontName = frontmost?.localizedName ?? "?"
        let frontPID = frontmost?.processIdentifier ?? 0

        // Log frontmost changes (new app activated) and every ~3s as a heartbeat.
        if frontPID != lastFrontmostPID {
            monLog.notice("frontmost -> \(frontName, privacy: .public) (pid \(frontPID, privacy: .public))")
            lastFrontmostPID = frontPID
        } else if tickCount % 10 == 0 {
            monLog.debug("still frontmost: \(frontName, privacy: .public) (pid \(frontPID, privacy: .public))")
        }

        let cmdHeld = NSEvent.modifierFlags.contains(.command)

        guard let (text, _) = provider.currentSelection() else {
            // No selection — signal the controller to dismiss the lingering trigger panel.
            if lastText != nil {
                lastText = nil
                lastIsAI = false
                consumedText = nil
                NotificationCenter.default.post(name: .flickSelectionCleared, object: nil)
            }
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && trimmed.count <= 5000 else {
            // Whitespace-only or too long — treat as cleared so the next real selection isn't masked.
            if lastText != nil {
                lastText = nil
                lastIsAI = false
                consumedText = nil
                NotificationCenter.default.post(name: .flickSelectionCleared, object: nil)
            }
            return
        }
        // Suppress notifications for a "consumed" selection — the user has already acted on it.
        if trimmed == consumedText { return }
        // Diff on (text, ⌘ held) so the label switches between "AI" and "译" on ⌘ toggle.
        if trimmed == lastText && cmdHeld == lastIsAI { return }

        // Capture cursor on the first poll for a given text; ⌘ toggles reuse the original
        // position so the button doesn't jump if the cursor drifts between selection and toggle.
        let cursor: NSPoint
        if trimmed == lastText {
            cursor = lastCursor
        } else {
            cursor = NSEvent.mouseLocation
            lastCursor = cursor
        }
        lastText = trimmed
        lastIsAI = cmdHeld

        NotificationCenter.default.post(
            name: .flickSelectionChanged,
            object: nil,
            userInfo: [
                "text": trimmed,
                "isAI": cmdHeld,
                "cursor": NSValue(point: cursor),
            ]
        )
    }
}