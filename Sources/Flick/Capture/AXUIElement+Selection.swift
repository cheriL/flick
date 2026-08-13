import AppKit
import ApplicationServices

extension AXUIElement {
    /// Returns the currently selected text in the focused UI element of the
    /// application identified by `pid`, or `nil` if unavailable / not text.
    static func selectedText(in pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)

        var focusedRef: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            app,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard focusedStatus == .success, let focusedObj = focusedRef else { return nil }
        let focused = focusedObj as! AXUIElement

        var selectedRef: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        )
        guard selectedStatus == .success,
              let str = selectedRef as? String,
              !str.isEmpty else { return nil }
        return str
    }
}