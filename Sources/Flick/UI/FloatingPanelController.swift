import AppKit
import SwiftUI

final class FloatingPanelController {
    private let triggerPanel = NSPanel(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered, defer: false
    )
    private let resultPanel = NSPanel(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel, .resizable],
        backing: .buffered, defer: false
    )
    /// Logical flags so the click-outside predicate works in headless tests, where
/// `panel.isVisible` is unreliable.
    private var triggerActive = false
    private var resultActive = false
    private var escMonitor: Any?
    private var outsideClickMonitor: Any?
    /// Bumped on every show/dismiss so a fade-out completion can tell whether
    /// the panel it's about to orderOut is still the dismissed one (a re-show
    /// during the fade must not be hidden by the stale completion).
    private var fadeGeneration = 0

    init() {
        configure(triggerPanel)
        configure(resultPanel)
        // The result panel's depth comes from a window shadow over the glass;
        // the trigger glyph paints its own SwiftUI shadow.
        resultPanel.hasShadow = true
        resultPanel.isReleasedWhenClosed = false
        triggerPanel.isReleasedWhenClosed = false
        installMonitors()
    }

    deinit {
        stopMonitors()
    }

    // MARK: - Public API

    func showTrigger(at cursor: CGPoint, text: String, onTap: @escaping () -> Void) {
        installMonitors()
        let size = CGSize(width: 28, height: 28)
        let screen = screenFrame(near: cursor)
        let origin = PanelPositioning.origin(forPanel: size, near: cursor, on: screen)

        triggerPanel.contentView = NSHostingView(
            rootView: TriggerButtonView(onTap: onTap)
        )
        fadeGeneration += 1
        PanelTransitions.present(triggerPanel, frame: NSRect(origin: origin, size: size))
        resultPanel.orderOut(nil)
        resultActive = false
        triggerActive = true
    }

    func showResult(original: String, state: ResultState, at cursor: CGPoint, onRetry: @escaping () -> Void) {
        installMonitors()
        let screen = screenFrame(near: cursor)

        // Update on an already-visible panel (loading → result, then streaming
        // refreshes every ~50ms): swap the root view in place and resize 1:1,
        // unanimated, from the top-left anchor. Easing re-targeted at ~20Hz
        // reads as a pulse — a direct step per refresh reads as the panel
        // honestly following its content.
        if resultActive, resultPanel.isVisible,
           let existing = resultPanel.contentView as? NSHostingView<ResultWindowView> {
            existing.rootView = ResultWindowView(original: original, state: state, onRetry: onRetry)
            existing.layoutSubtreeIfNeeded()
            let size = clampedResultSize(of: existing.fittingSize, on: screen)
            let current = resultPanel.frame
            var origin = NSPoint(x: current.minX, y: current.maxY - size.height)
            origin.y = max(origin.y, screen.minY)
            origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
            resultPanel.setFrame(NSRect(origin: origin, size: size), display: true)
            triggerPanel.orderOut(nil)
            triggerActive = false
            return
        }

        let host = makeResultHost(original: original, state: state, onRetry: onRetry)
        // Content must be attached and laid out before positioning: the panel's
        // real size comes from the hosting view's fitting size, and positioning
        // with a placeholder rect lets the content-driven resize extend past the
        // screen bottom (behind the Dock) without ever being re-clamped.
        host.layoutSubtreeIfNeeded()
        let size = clampedResultSize(of: host.fittingSize, on: screen)
        let origin = PanelPositioning.origin(forPanel: size, near: cursor, on: screen)
        resultPanel.contentView = host
        fadeGeneration += 1
        PanelTransitions.present(resultPanel, frame: NSRect(origin: origin, size: size))
        triggerPanel.orderOut(nil)
        triggerActive = false
        resultActive = true
    }

    private func clampedResultSize(of fitting: CGSize, on screen: CGRect) -> CGSize {
        let fallback = CGSize(width: 360, height: 140)
        var size = fitting
        if size.width <= 0 { size.width = fallback.width }
        if size.height <= 0 { size.height = fallback.height }
        return CGSize(width: size.width, height: min(size.height, screen.height - 24))
    }

    /// Notified when `dismiss()` runs, after panels are hidden and monitors are
    /// torn down. Set once by the owning controller.
    var onDismiss: (() -> Void)?

    func dismiss() {
        fadeGeneration += 1
        let gen = fadeGeneration
        let isValid = { [weak self] in self?.fadeGeneration == gen }
        PanelTransitions.dismissAnimated(triggerPanel, isValid: isValid)
        PanelTransitions.dismissAnimated(resultPanel, isValid: isValid)
        triggerActive = false
        resultActive = false
        stopMonitors()
        onDismiss?()
    }

    // MARK: - Test hooks

    /// Trigger panel frame in screen coordinates. Exposed so tests can compute "inside" / "outside"
    /// points without depending on the headless NSScreen geometry `PanelPositioning` clamps to.
    var triggerFrameForTesting: CGRect { triggerPanel.frame }

    /// Result panel frame. Same rationale as `triggerFrameForTesting`.
    var resultFrameForTesting: CGRect { resultPanel.frame }

    /// Result panel's effective appearance — tests assert the panel is pinned to `.aqua`.
    var resultAppearanceForTesting: NSAppearance? { resultPanel.appearance }

    // MARK: - Private

    /// Hosts `ResultWindowView` on the glass panel. Same layer recipe as
    /// TranslatePanelController: transparent hosting view (an opaque backing
    /// shows through the glass as a rectangular black line) rounded to the
    /// glass shape to clip any straggling rectangular artifact.
    private func makeResultHost(original: String, state: ResultState, onRetry: @escaping () -> Void) -> NSHostingView<ResultWindowView> {
        let host = NSHostingView(
            rootView: ResultWindowView(original: original, state: state, onRetry: onRetry)
        )
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.layer?.cornerRadius = 10
        host.layer?.masksToBounds = true
        return host
    }

    /// Screen rect to place the panel on. Resolved from the cursor, not `NSScreen.main`
    /// (see `PanelPositioning.screenFrame`). Uses `visibleFrame` — the raw `frame`
    /// includes the Dock and menu-bar strips, so clamping against it parks panels
    /// behind the Dock at screen edges.
    private func screenFrame(near cursor: CGPoint) -> CGRect {
        PanelPositioning.screenFrame(
            for: cursor,
            in: NSScreen.screens.map(\.visibleFrame),
            fallback: NSScreen.main?.visibleFrame ?? .zero
        )
    }

    private func configure(_ panel: NSPanel) {
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
    }

    private func installMonitors() {
        stopMonitors()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.dismiss()
                return nil
            }
            return event
        }
        // Global mouse-down dismisses on outside click — `.nonactivatingPanel` never takes key
        // so `didResignKey` doesn't fire. Inside clicks must pass through to the panel's view.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            let click = NSEvent.mouseLocation
            if self.isOutsideClick(at: click) {
                self.dismiss()
            }
        }
    }

    /// True if a click at `screenPoint` is outside every visible Flick panel. Exposed so tests
    /// can exercise the predicate with synthetic panel states.
    func isOutsideClick(at screenPoint: CGPoint) -> Bool {
        if triggerActive, triggerPanel.frame.contains(screenPoint) { return false }
        if resultActive, resultPanel.frame.contains(screenPoint) { return false }
        return true
    }

    private func stopMonitors() {
        if let m = escMonitor { NSEvent.removeMonitor(m) }
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m) }
        escMonitor = nil
        outsideClickMonitor = nil
    }
}
