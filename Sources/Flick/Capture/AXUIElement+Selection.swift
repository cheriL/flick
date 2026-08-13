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
        // views (TextEdit, iTerm2, native macOS text fields). Often returns
        // empty/nil for WKWebView/Safari web content, where selection lives
        // behind a range parameterised attribute instead.
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

        // --- Path B: web content / Safari / Chrome. Walk down to the
        // deepest selected child, then resolve selection via range.
        if let rangeStr = selectedTextViaRange(in: focused) {
            return rangeStr
        }

        axLog.notice("no selection: selectedStatus=\(selectedStatus.rawValue, privacy: .public) role=\(Self.role(of: focused) ?? "?", privacy: .public)")
        return nil
    }

    /// Walk down the focused element's children looking for one that has a
    /// non-empty `kAXSelectedTextRangeAttribute`. Web content typically
    /// exposes selection on a deeply-nested text node, not the web area
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