import AppKit
import ApplicationServices
import os.log

private let axLog = Logger(subsystem: "com.cheriL.flick", category: "ax")

extension AXUIElement {
    /// Returns true if the current process has been granted Accessibility
    /// permission. Centralised so callers don't have to import ApplicationServices.
    static var isProcessTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Returns the currently selected text in the focused UI element of the
    /// application identified by `pid`, or `nil` if unavailable / not text /
    /// the process lacks Accessibility permission.
    static func selectedText(in pid: pid_t) -> String? {
        // Short-circuit when we know AX will refuse us. Without this the
        // monitor polls 3x/s producing one kAXErrorAPIDisabled per tick —
        // noisy in logs and wasteful.
        guard AXIsProcessTrusted() else { return nil }

        let app = AXUIElementCreateApplication(pid)

        var focusedRef: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            app,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard focusedStatus == .success, let focusedRef else {
            if focusedStatus != .success {
                axLog.debug("selectedText pid=\(pid): focused status=\(focusedStatus.rawValue, privacy: .public)")
            }
            return nil
        }
        let focused = focusedRef as! AXUIElement

        var selectedRef: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        )
        if selectedStatus != .success {
            axLog.debug("selectedText pid=\(pid): selected status=\(selectedStatus.rawValue, privacy: .public)")
            return nil
        }
        guard let str = selectedRef as? String, !str.isEmpty else { return nil }
        return str
    }
}