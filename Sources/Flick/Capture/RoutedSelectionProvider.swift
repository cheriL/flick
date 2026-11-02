import AppKit

/// Routes selection capture by frontmost app: Chrome reads via AppleScript (no AX tree
/// needed), everything else reads via AX. When the AppleScript path is unavailable the
/// router falls back to full AX, matching the pre-routing single-provider behaviour.
final class RoutedSelectionProvider: SelectionProvider {
    static let chromeBundleID = "com.google.Chrome"

    typealias FrontmostInfo = (bundleID: String?, pid: pid_t?)

    private let frontmost: () -> FrontmostInfo?
    private let chromeReader: ChromeSelectionReading
    private let axProvider: SelectionProvider
    private let nativeSupplement: (pid_t) -> String?

    init(
        frontmost: @escaping () -> FrontmostInfo? = {
            NSWorkspace.shared.frontmostApplication.map { ($0.bundleIdentifier, $0.processIdentifier) }
        },
        chromeReader: ChromeSelectionReading,
        axProvider: SelectionProvider = AXSelectionProvider(),
        nativeSupplement: @escaping (pid_t) -> String? = { AXUIElement.selectedTextInFocusedNativeElement(of: $0) }
    ) {
        self.frontmost = frontmost
        self.chromeReader = chromeReader
        self.axProvider = axProvider
        self.nativeSupplement = nativeSupplement
    }

    func currentSelection() -> (text: String, pid: pid_t)? {
        guard let front = frontmost(), let pid = front.pid else {
            chromeReader.setActive(pid: nil)
            return nil
        }
        guard front.bundleID == Self.chromeBundleID else {
            chromeReader.setActive(pid: nil)
            return axProvider.currentSelection()
        }
        chromeReader.setActive(pid: pid)
        if let text = chromeReader.currentText(), !text.isEmpty {
            return (text, pid)
        }
        if chromeReader.isHealthy {
            // Healthy page with no script-visible selection: only the focused native element
            // (omnibox) can still hold one. Never fall through to full AX here — without the
            // renderer flag its windows-walk fires on every poll.
            if let native = nativeSupplement(pid) {
                return (native, pid)
            }
            return nil
        }
        return axProvider.currentSelection()
    }
}
