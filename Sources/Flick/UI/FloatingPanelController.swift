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
    private var escMonitor: Any?
    private var outsideClickMonitor: Any?

    init() {
        configure(triggerPanel)
        configure(resultPanel)
        resultPanel.isReleasedWhenClosed = false
        triggerPanel.isReleasedWhenClosed = false
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
        installMonitors()
    }

    func dismiss() {
        triggerPanel.orderOut(nil)
        resultPanel.orderOut(nil)
        stopMonitors()
    }

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
        if panel === resultPanel {
            panel.hasShadow = false
        } else {
            panel.hasShadow = true
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
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
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
