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
        let appName = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid })?.localizedName ?? "?"

        var focusedRef: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            app,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        // NSWorkspace.frontmostApplication returns the main Chrome process
        // (which owns the window), but Chrome's actual AX tree for the
        // web content lives in a renderer helper process. When the focused
        // element fetch on the main process fails or returns an empty
        // role, also try the SystemWide focused-application attribute,
        // which resolves to the *real* foreground app element — including
        // helpers for multi-process browsers. And as a last resort, walk
        // the app's windows and grab the AXWebArea directly.
        if focusedStatus != .success || focusedRef == nil {
            axLog.notice("[\(appName, privacy: .public)] focused fetch status=\(focusedStatus.rawValue, privacy: .public), trying fallbacks")
            if let sysResult = selectedTextViaSystemWideFocused() {
                return sysResult
            }
            if let walkResult = selectedTextViaWindowsWalk(pid: pid) {
                return walkResult
            }
            return nil
        }
        let focused = focusedRef as! AXUIElement
        let role = Self.role(of: focused) ?? "?"

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
        let aType = selectedRef.map { CFGetTypeID($0) } ?? 0
        let aStrLen = (selectedRef as? String)?.count ?? -1
        axLog.notice("[\(appName, privacy: .public) role=\(role, privacy: .public)] A: status=\(selectedStatus.rawValue, privacy: .public) typeID=\(aType, privacy: .public) strLen=\(aStrLen, privacy: .public)")
        if selectedStatus == .success,
           let str = selectedRef as? String,
           !str.isEmpty {
            return str
        }

        // --- Path B: web content. WKWebView exposes the full visible text
        // as `kAXValueAttribute` and the selection as a CFRange. Substring
        // the value with the range. This is the documented approach for
        // Safari / Chrome pages.
        let bResult = selectedTextViaValuePlusRange(in: focused, log: true)
        if let webStr = bResult {
            axLog.notice("B: HIT len=\(webStr.count, privacy: .public)")
            return webStr
        }

        // --- Path C: deep web content where the focused element is a
        // higher-level container and the actual selected node is a child
        // (some Safari web components behave this way).
        let cResult = selectedTextViaRange(in: focused, log: true)
        if let rangeStr = cResult {
            axLog.notice("C: HIT len=\(rangeStr.count, privacy: .public)")
            return rangeStr
        }

        // --- Path D: modern Safari / WKWebView use the TextMarker-based
        // API. `kAXSelectedTextAttribute` and `kAXValueAttribute` both
        // return kAXErrorAttributeUnsupported on the AXWebArea, and the
        // BFS into kAXChildren doesn't reach the actual selected node —
        // web content exposes selection via an opaque marker range that
        // must be resolved with a parameterised attribute.
        if let markerStr = selectedTextViaTextMarker(in: focused, log: true) {
            axLog.notice("D: HIT len=\(markerStr.count, privacy: .public)")
            return markerStr
        }

        axLog.notice("no selection: app=\(appName, privacy: .public) role=\(role, privacy: .public)")
        return nil
    }

    /// Read full text via `kAXValueAttribute`, slice it with the range
    /// reported by `kAXSelectedTextRangeAttribute`. This is what WKWebView
    /// web content exposes.
    private static func selectedTextViaValuePlusRange(in element: AXUIElement, log: Bool = false) -> String? {
        var valueRef: CFTypeRef?
        let valueStatus = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueRef
        )
        let valueTypeID = valueRef.map { CFGetTypeID($0) } ?? 0
        let valueLen = (valueRef as? String)?.count ?? -1
        if log { axLog.notice("B: value status=\(valueStatus.rawValue, privacy: .public) typeID=\(valueTypeID, privacy: .public) len=\(valueLen, privacy: .public)") }
        guard valueStatus == .success, let full = valueRef as? String, !full.isEmpty else {
            return nil
        }
        var rangeRef: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        )
        var range = CFRange(location: 0, length: 0)
        var rangeOK = false
        if rangeStatus == .success, let axVal = rangeRef {
            rangeOK = AXValueGetValue(axVal as! AXValue, .cfRange, &range)
        }
        if log {
            axLog.notice("B: range status=\(rangeStatus.rawValue, privacy: .public) ok=\(rangeOK, privacy: .public) loc=\(range.location, privacy: .public) len=\(range.length, privacy: .public) fullLen=\(full.count, privacy: .public)")
        }
        guard rangeOK,
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

    /// Modern Safari / WKWebView expose selection through opaque text
    /// markers. Pull the marker range via kAXSelectedTextMarkerRangeAttribute,
    /// then resolve it to a string via the parameterised
    /// kAXStringForTextMarkerRangeAttribute. The string constants are
    /// NOT in the macOS SDK headers (the AX framework treats them as
    /// semi-private), but they are stable, documented behaviour — every
    /// macOS accessibility tool that handles browser content uses them.
    private static func selectedTextViaTextMarker(in element: AXUIElement, log: Bool = false) -> String? {
        let markerRangeAttr = "AXSelectedTextMarkerRange" as CFString
        let stringForMarkerRangeAttr = "AXStringForTextMarkerRange" as CFString

        var markerRangeRef: CFTypeRef?
        let mrStatus = AXUIElementCopyAttributeValue(
            element, markerRangeAttr, &markerRangeRef
        )
        if log { axLog.notice("D: markerRange status=\(mrStatus.rawValue, privacy: .public) refNil=\(markerRangeRef == nil, privacy: .public)") }
        guard mrStatus == .success, let markerRange = markerRangeRef else { return nil }

        var stringRef: CFTypeRef?
        let sStatus = _AXUIElementCopyParameterizedAttributeValue(
            element,
            stringForMarkerRangeAttr,
            markerRange,
            &stringRef
        )
        if log { axLog.notice("D: stringForRange status=\(sStatus.rawValue, privacy: .public) typeID=\(stringRef.map { CFGetTypeID($0) } ?? 0, privacy: .public) len=\((stringRef as? String)?.count ?? -1, privacy: .public)") }
        guard sStatus == .success,
              let str = stringRef as? String,
              !str.isEmpty
        else { return nil }
        return str
    }

    /// Multi-process browsers (Chrome, Edge, Brave) often return a focused
    /// element on the main process that doesn't actually carry the
    /// selection — the AX tree for the page lives in a renderer helper.
    /// `kAXFocusedApplicationAttribute` on the SystemWide AXUIElement
    /// resolves to whichever process actually owns the foreground UI, and
    /// we re-run the standard extraction against it.
    private static func selectedTextViaSystemWideFocused() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var appRef: CFTypeRef?
        let appStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &appRef
        )
        guard appStatus == .success, let appObj = appRef else {
            axLog.notice("SystemWide focused app status=\(appStatus.rawValue, privacy: .public)")
            return nil
        }
        let focusedApp = appObj as! AXUIElement
        var pid: pid_t = 0
        let pidStatus = AXUIElementGetPid(focusedApp, &pid)
        guard pidStatus == .success, pid != 0 else {
            axLog.notice("SystemWide pid status=\(pidStatus.rawValue, privacy: .public)")
            return nil
        }
        let name = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid })?.localizedName ?? "?"
        axLog.notice("SystemWide resolved app=\(name, privacy: .public) pid=\(pid, privacy: .public)")
        let appElem = AXUIElementCreateApplication(pid)
        var fRef: CFTypeRef?
        let fStatus = AXUIElementCopyAttributeValue(
            appElem,
            kAXFocusedUIElementAttribute as CFString,
            &fRef
        )
        guard fStatus == .success, let fRef else { return nil }
        let focused = fRef as! AXUIElement
        let role = Self.role(of: focused) ?? "?"
        axLog.notice("SystemWide focused role=\(role, privacy: .public)")

        // Reuse the same Path A/B/C/D extraction the caller would have
        // used. We can't easily call back into selectedText(in:) because
        // it would re-query the SystemWide element (infinite loop), so
        // we just try Path A and Path D here — those are the ones that
        // work in practice for browser content.
        if let s = Self.extractViaSelectedText(in: focused) { return s }
        if let s = Self.extractViaTextMarker(in: focused) { return s }
        return nil
    }

    private static func extractViaSelectedText(in element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &ref
        )
        guard status == .success, let s = ref as? String, !s.isEmpty else { return nil }
        return s
    }

    private static func extractViaTextMarker(in element: AXUIElement) -> String? {
        let markerRangeAttr = "AXSelectedTextMarkerRange" as CFString
        let stringForMarkerRangeAttr = "AXStringForTextMarkerRange" as CFString
        var markerRangeRef: CFTypeRef?
        let mrStatus = AXUIElementCopyAttributeValue(element, markerRangeAttr, &markerRangeRef)
        guard mrStatus == .success, let markerRange = markerRangeRef else { return nil }
        var stringRef: CFTypeRef?
        let sStatus = _AXUIElementCopyParameterizedAttributeValue(
            element, stringForMarkerRangeAttr, markerRange, &stringRef
        )
        guard sStatus == .success, let str = stringRef as? String, !str.isEmpty else { return nil }
        return str
    }

    /// Chrome (and a few other multi-process browsers) don't expose
    /// `kAXFocusedUIElementAttribute` from the main app element — the
    /// focused element lives in a renderer helper. Their app AXUIElement
    /// DOES expose `kAXWindowsAttribute`, so we walk the windows, find
    /// the AXWebArea, and try Path D against it.
    private static func selectedTextViaWindowsWalk(pid: pid_t) -> String? {
        let appElem = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let winStatus = AXUIElementCopyAttributeValue(
            appElem,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )
        guard winStatus == .success, let windows = windowsRef as? [AXUIElement] else {
            axLog.notice("windows walk: kAXWindows status=\(winStatus.rawValue, privacy: .public)")
            return nil
        }
        axLog.notice("windows walk: \(windows.count, privacy: .public) windows")
        for window in windows {
            // Look for AXWebArea in the window tree (BFS, capped depth).
            if let webArea = findRole(.webArea, in: window, maxDepth: 12) {
                if let str = extractViaTextMarker(in: webArea) {
                    axLog.notice("windows walk: HIT via AXWebArea len=\(str.count, privacy: .public)")
                    return str
                }
            }
        }
        return nil
    }

    private enum TargetRole { case webArea }

    private static func findRole(_ target: TargetRole, in root: AXUIElement, maxDepth: Int) -> AXUIElement? {
        var queue: [AXUIElement] = [root]
        var seen = Set<ObjectIdentifier>()
        for _ in 0..<maxDepth {
            guard let node = queue.first else { return nil }
            queue.removeFirst()
            let id = ObjectIdentifier(node)
            if seen.contains(id) { continue }
            seen.insert(id)

            let role = Self.role(of: node) ?? ""
            if target == .webArea && role == "AXWebArea" {
                return node
            }

            var childrenRef: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(
                node, kAXChildrenAttribute as CFString, &childrenRef
            )
            if status == .success, let arr = childrenRef as? [AXUIElement] {
                queue.append(contentsOf: arr)
            }
        }
        return nil
    }

    /// Walk down the focused element's children looking for one that has a
    /// non-empty `kAXSelectedTextRangeAttribute`. Some web components
    /// expose selection on a deeply-nested text node, not the web area
    /// itself. Resolves the range with `kAXStringForRangeParameterizedAttribute`.
    private static func selectedTextViaRange(in root: AXUIElement, log: Bool = false) -> String? {
        if log { axLog.notice("C: BFS start") }
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
                if log { axLog.notice("C: BFS expanded by \(arr.count, privacy: .public)") }
                queue.append(contentsOf: arr)
            }
        }
        if log { axLog.notice("C: BFS exhausted") }
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