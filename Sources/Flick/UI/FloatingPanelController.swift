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

    init() {
        configure(triggerPanel)
        configure(resultPanel)
        resultPanel.isReleasedWhenClosed = false
        triggerPanel.isReleasedWhenClosed = false
        // Install both monitors at init so they're active whenever any panel is showing.
        installMonitors()
    }

    deinit {
        stopMonitors()
    }

    // MARK: - Public API

    func showTrigger(at cursor: CGPoint, text: String, onTap: @escaping () -> Void) {
        let size = CGSize(width: 28, height: 28)
        let screen = screenFrame(near: cursor)
        let origin = PanelPositioning.origin(forPanel: size, near: cursor, on: screen)

        triggerPanel.setFrame(NSRect(origin: origin, size: size), display: true)
        triggerPanel.contentView = NSHostingView(
            rootView: TriggerButtonView(onTap: onTap)
        )
        triggerPanel.orderFrontRegardless()
        resultPanel.orderOut(nil)
        resultActive = false
        triggerActive = true
    }

    func showResult(original: String, state: ResultState, at cursor: CGPoint, onRetry: @escaping () -> Void) {
        let size = CGSize(width: 360, height: 140) // height grows with content via resizable mask
        let screen = screenFrame(near: cursor)
        let origin = PanelPositioning.origin(forPanel: size, near: cursor, on: screen)

        resultPanel.setFrame(NSRect(origin: origin, size: size), display: true)
        let root = ResultWindowView(original: original, state: state, onRetry: onRetry)
        let container = PanelContainerView(rootView: root)
        resultPanel.contentView = container
        resultPanel.orderFrontRegardless()
        triggerPanel.orderOut(nil)
        triggerActive = false
        resultActive = true
    }

    /// Notified when `dismiss()` runs, after panels are hidden and monitors are
    /// torn down. Set once by the owning controller.
    var onDismiss: (() -> Void)?

    func dismiss() {
        triggerPanel.orderOut(nil)
        resultPanel.orderOut(nil)
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

    /// Screen rect to place the panel on. Resolved from the cursor, not `NSScreen.main`
    /// (see `PanelPositioning.screenFrame`).
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
        // Both panels: no window shadow (the chrome / SwiftUI shadow handles depth).
        // Both inherit system appearance via the adaptive chrome view.
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

/// Stacks a `PanelChromeView` (material + rounded corner + shadow backing) under the
/// SwiftUI hosting view that renders `ResultWindowView`. Set as the result panel's content view.
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
