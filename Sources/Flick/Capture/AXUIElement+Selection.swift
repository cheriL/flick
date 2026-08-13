import AppKit
import ApplicationServices
import os.log

private let axLog = Logger(subsystem: "com.cheriL.flick", category: "ax")

// ApplicationServices' Swift overlay does not bridge this symbol. Declare
// the C signature so we can call it from Swift. (The actual C name in the
// SDK is `AXUIElementCopyParameterizedAttributeValue` — the parameterised
// sibling of `AXUIElementCopyAttributeValue`.)
@_silgen_name("AXUIElementCopyParameterizedAttributeValue")
private func _AXUIElementCopyParameterizedAttributeValue(
    _ element: AXUIElement,
    _ parameterizedAttribute: CFString,
    _ parameter: CFTypeRef,
    _ result: UnsafeMutablePointer<CFTypeRef?>
) -> AXError

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
                axLog.notice("focused fetch status=\(focusedStatus.rawValue, privacy: .public)")
            }
            return nil
        }
        let focused = focusedRef as! AXUIElement

        // --- Path A: standard `kAXSelectedTextAttribute`. Works for NSText
        // views (TextEdit, iTerm2, native macOS text fields like the
        // Safari address bar). Often returns empty for WKWebView/Safari
        // web content — Path B handles that.
        var selectedRef: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        )
        if selectedStatus == .success,
           let str = selectedRef as? String,
           !str.isEmpty {
            return str
        }

        // --- Path B: web content. WKWebView exposes the full visible text
        // as `kAXValueAttribute` and the selection as a CFRange. Substring
        // the value with the range. This is the documented approach for
        // Safari / Chrome pages.
        if let webStr = selectedTextViaValuePlusRange(in: focused) {
            return webStr
        }

        // --- Path C: deep web content where the focused element is a
        // higher-level container and the actual selected node is a child
        // (some Safari web components behave this way).
        if let rangeStr = selectedTextViaRange(in: focused) {
            return rangeStr
        }

        axLog.notice("no selection: selectedStatus=\(selectedStatus.rawValue, privacy: .public) role=\(Self.role(of: focused) ?? "?", privacy: .public)")
        return nil
    }

    /// Read full text via `kAXValueAttribute`, slice it with the range
    /// reported by `kAXSelectedTextRangeAttribute`. This is what WKWebView
    /// web content exposes.
    private static func selectedTextViaValuePlusRange(in element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        let valueStatus = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueRef
        )
        guard valueStatus == .success, let full = valueRef as? String, !full.isEmpty else {
            return nil
        }
        var rangeRef: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        )
        guard rangeStatus == .success, let axVal = rangeRef else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axVal as! AXValue, .cfRange, &range),
              range.length > 0,
              range.location >= 0,
              range.location + range.length <= full.utf16.count
        else { return nil }

        // CFRange uses UTF-16 code units (matches the AX API), so slice
        // via the UTF-16 view and re-bridge back to String.
        let utf16 = Array(full.utf16)
        let slice = Array(utf16[range.location ..< range.location + range.length])
        return String(utf16CodeUnits: slice, count: slice.count)
    }

    /// Walk down the focused element's children looking for one that has a
    /// non-empty `kAXSelectedTextRangeAttribute`. Some web components
    /// expose selection on a deeply-nested text node, not the web area
    /// itself. Resolves the range with `kAXStringForRangeParameterizedAttribute`.
    private static func selectedTextViaRange(in root: AXUIElement) -> String? {
        var queue: [AXUIElement] = [root]
        var seen = Set<ObjectIdentifier>()
        let maxDepth = 8

        for _ in 0..<maxDepth {
            guard let node = queue.first else { return nil }
            queue.removeFirst()
            let id = ObjectIdentifier(node)
            if seen.contains(id) { continue }
            seen.insert(id)

            // Does this node have a non-empty selection range?
            if let text = textFromSelectionRange(in: node) {
                return text
            }

            // BFS into children.
            var childrenRef: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(
                node,
                kAXChildrenAttribute as CFString,
                &childrenRef
            )
            if status == .success, let arr = childrenRef as? [AXUIElement] {
                queue.append(contentsOf: arr)
            }
        }
        return nil
    }

    private static func textFromSelectionRange(in element: AXUIElement) -> String? {
        var rangeRef: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        )
        guard rangeStatus == .success,
              let axVal = rangeRef
        else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axVal as! AXValue, .cfRange, &range),
              range.length > 0
        else { return nil }

        var strRef: CFTypeRef?
        let strStatus = _AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            range as CFTypeRef,
            &strRef
        )
        guard strStatus == .success,
              let str = strRef as? String,
              !str.isEmpty
        else { return nil }
        return str
    }

    private static func role(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &ref) == .success,
              let s = ref as? String
        else { return nil }
        return s
    }
}