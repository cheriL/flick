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
    /// Logical "is this panel the one currently displayed" flags, set
    /// when `showTrigger` / `showResult` runs and cleared in `dismiss`.
    /// We use these rather than `panel.isVisible` because `isVisible`
    /// relies on AppKit's notion of "on screen" — which is unreliable
    /// in headless test environments and after `orderFrontRegardless`
    /// without a real display attached. The predicate for click-outside
    /// dismissal is about the *logical* display state, not the
    /// graphical one.
    private var triggerActive = false
    private var resultActive = false
    private var escMonitor: Any?
    private var outsideClickMonitor: Any?

    init() {
        configure(triggerPanel)
        configure(resultPanel)
        resultPanel.isReleasedWhenClosed = false
        triggerPanel.isReleasedWhenClosed = false
        // Install both monitors at init so they're active whenever ANY
        // panel is showing — not just the result panel. Previously the
        // outside-click monitor was only registered inside `showResult`,
        // which meant the trigger button stayed on screen even when the
        // user clicked elsewhere.
        installMonitors()
    }

    deinit {
        stopMonitors()
    }

    // MARK: - Public API

    func showTrigger(at cursor: CGPoint, text: String, isAI: Bool, onTap: @escaping () -> Void) {
        let size = CGSize(width: 28, height: 28)
        let screen = screenFrame(near: cursor)
        let origin = PanelPositioning.origin(forPanel: size, near: cursor, on: screen)

        triggerPanel.setFrame(NSRect(origin: origin, size: size), display: true)
        triggerPanel.contentView = NSHostingView(
            rootView: TriggerButtonView(isAI: isAI, onTap: onTap)
        )
        triggerPanel.orderFrontRegardless()
        resultPanel.orderOut(nil)
        resultActive = false
        triggerActive = true
    }

    func showResult(original: String, state: ResultState, at cursor: CGPoint, isAI: Bool, onRetry: @escaping () -> Void) {
        let size = CGSize(width: 360, height: 140) // height grows with content via resizable mask
        let screen = screenFrame(near: cursor)
        let origin = PanelPositioning.origin(forPanel: size, near: cursor, on: screen)

        resultPanel.setFrame(NSRect(origin: origin, size: size), display: true)
        let root = ResultWindowView(original: original, state: state, isAI: isAI, onRetry: onRetry)
        let container = PanelContainerView(rootView: root)
        resultPanel.contentView = container
        resultPanel.orderFrontRegardless()
        triggerPanel.orderOut(nil)
        triggerActive = false
        resultActive = true
    }

    func dismiss() {
        triggerPanel.orderOut(nil)
        resultPanel.orderOut(nil)
        triggerActive = false
        resultActive = false
        stopMonitors()
    }

    // MARK: - Test hooks

    /// Current frame of the trigger panel (in screen coordinates, Cocoa
    /// convention). Exposed so tests can compute "inside" / "outside"
    /// points without depending on the headless NSScreen geometry that
    /// `PanelPositioning` ends up clamping to in `swift test`.
    var triggerFrameForTesting: CGRect { triggerPanel.frame }

    /// Current frame of the result panel. Same rationale as
    /// `triggerFrameForTesting`.
    var resultFrameForTesting: CGRect { resultPanel.frame }

    /// Effective appearance of the result panel. Exposed so tests can
    /// assert the panel is pinned to `.aqua` (light) regardless of the
    /// host's system appearance — see `configure(_:)` for why.
    var resultAppearanceForTesting: NSAppearance? { resultPanel.appearance }

    // MARK: - Private

    /// Frame of the display the panel should be placed on. Resolved from the
    /// cursor rather than `NSScreen.main` — see `PanelPositioning.screenFrame`
    /// for why the latter is wrong for a menu-bar accessory app.
    private func screenFrame(near cursor: CGPoint) -> CGRect {
        PanelPositioning.screenFrame(
            for: cursor,
            in: NSScreen.screens.map(\.frame),
            fallback: NSScreen.main?.frame ?? .zero
        )
    }

    private func configure(_ panel: NSPanel) {
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        // The result panel draws its own shadow on the chrome view, so we
        // only want a window-level shadow on the trigger panel.
        //
        // Both panels inherit the system appearance: the chrome
        // (`PanelChromeView`) is an adaptive `NSView` subclass that
        // paints white in light mode and dark gray in dark mode, and
        // the SwiftUI text uses `.foregroundStyle(.primary/.secondary)`
        // which auto-inverts. No pinning — the panel tracks the user's
        // system appearance.
        if panel === resultPanel {
            panel.hasShadow = false
        } else {
            // Disable the default NSWindow shadow. It renders as a
            // hard dark edge around the window frame — the user
            // reported this as a "black border" around the trigger
            // button. The button itself draws a softer SwiftUI
            // `.shadow()` instead (see `TriggerButtonView`).
            panel.hasShadow = false
        }
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
        // Global mouse-down watcher. We can't use NSPanel's built-in
        // `didResignKey` for this because the panels are
        // `.nonactivatingPanel` — they don't take key, so they don't
        // resign on outside click. We register a global monitor instead
        // (which requires Accessibility permission, which the app
        // already has for selection polling).
        //
        // The handler is **dismiss-on-outside only**: a click that lands
        // inside one of our panels must pass through to the panel's view
        // hierarchy so the user can still tap the trigger button, click
        // the result panel's retry button, scroll the translation, etc.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            let click = NSEvent.mouseLocation
            if self.isOutsideClick(at: click) {
                self.dismiss()
            }
        }
    }

    /// True if a click at `screenPoint` is "outside" every currently
    /// visible Flick panel — i.e. the click should dismiss the popup.
    /// False if the click landed inside a panel, in which case it
    /// should pass through to that panel's view.
    ///
    /// Exposed (rather than inlined in the monitor closure) so tests can
    /// exercise the predicate directly with synthetic panel states.
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

/// Stacks a `PanelChromeView` (the material + rounded corner + shadow backing)
/// under a SwiftUI `NSHostingView` that renders the actual `ResultWindowView`.
/// Set as the content view of the result panel.
private final class PanelContainerView: NSView {
    let chrome: NSHostingView<PanelChromeView>
    let host: NSHostingView<ResultWindowView>

    init(rootView: ResultWindowView) {
        self.chrome = NSHostingView(rootView: PanelChromeView())
        self.host = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        addSubview(chrome)
        addSubview(host)
        chrome.translatesAutoresizingMaskIntoConstraints = false
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: trailingAnchor),
            chrome.topAnchor.constraint(equalTo: topAnchor),
            chrome.bottomAnchor.constraint(equalTo: bottomAnchor),
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
