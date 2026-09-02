import AppKit
import SwiftUI

/// Owns the menu-bar popup `NSPanel`. We host it directly (rather than via SwiftUI's
/// `MenuBarExtra`) so we control show/hide/position and the visual-effect backdrop.
final class MenuPanelController {
    private let store: ConfigStore
    private let onQuit: () -> Void
    private let panel: NSPanel
    // `var` because the hosting controller's onQuit captures `self`, which Swift forbids
    // before all `let` fields are set.
    private var hostingController: NSHostingController<MenuBarContent>?
    private var escMonitor: Any?
    private var outsideClickMonitor: Any?
    /// Status-item button frame at the moment of the last show. Cached so the click-outside
    /// monitor can treat clicks on the button as inside clicks (deferring dismissal to the
    /// button's own toggle action).
    private var statusItemAnchor: NSRect = .zero

    init(store: ConfigStore, onQuit: @escaping () -> Void) {
        self.store = store
        self.onQuit = onQuit

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.panel = panel
        configure(panel)

        // Hosting controller is reused across toggles so `MenuBarContent` `@State` (the 1 Hz
        // TCC timer, `isTrusted`, `selectionEnabled`) survives. `onQuit` is captured strongly:
        // the panel's job is to hide itself before app-quit runs.
        let quitHandler = onQuit
        let content = MenuBarContent(store: store, onQuit: { [weak self] in
            self?.hide()
            quitHandler()
        })
        let host = NSHostingController(rootView: content)
        self.hostingController = host
        panel.contentViewController = host
    }

    deinit {
        stopMonitors()
    }

    // MARK: - Public API

    /// Toggle the menu. `statusItemFrame` is in screen coordinates (callers get it from
    /// `button.convertToScreen`); alignment depends on which side has room (see `positionPanel`).
    func toggle(statusItemFrame: NSRect) {
        if panel.isVisible {
            hide()
        } else {
            // Menu wins — dismiss the translation popup so the user sees one panel at a time.
            FloatingPanelController.shared?.dismiss()
            show(statusItemFrame: statusItemFrame)
        }
    }

    func hide() {
        panel.orderOut(nil)
        stopMonitors()
    }

    // MARK: - Private

    private func show(statusItemFrame: NSRect) {
        statusItemAnchor = statusItemFrame
        sizePanelToContent()
        positionPanel()
        panel.orderFrontRegardless()
        installMonitors()
    }

    /// Resize the `NSPanel` to match `MenuBarContent`'s intrinsic size
    /// (`.frame(width: 210)` + VStack-laid height).
    private func sizePanelToContent() {
        guard let host = hostingController?.view else { return }
        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize
        guard fitting.width > 0, fitting.height > 0 else { return }
        panel.setContentSize(fitting)
    }

    /// Place the panel below the status item: left edge meets button's left edge by default;
    /// flip to right-align if the panel would overflow the screen's right edge.
    private func positionPanel() {
        let panelSize = panel.frame.size
        let button = statusItemAnchor
        let screen = PanelPositioning.screenFrame(
            for: NSPoint(x: button.midX, y: button.midY),
            in: NSScreen.screens.map(\.frame),
            fallback: NSScreen.main?.frame ?? .zero
        )

        let roomRight = screen.maxX - button.maxX
        let roomLeft = button.minX - screen.minX
        let fitsRight = roomRight >= panelSize.width + 8
        let fitsLeft = roomLeft >= panelSize.width + 8

        let originX: CGFloat
        if fitsRight {
            originX = button.minX
        } else if fitsLeft {
            originX = button.maxX - panelSize.width
        } else {
            // Neither side fits — center on the button and let it spill.
            originX = button.midX - panelSize.width / 2
        }

        // 8pt margin so the panel never sits flush against the screen border.
        let clampedX = min(
            max(originX, screen.minX + 8),
            screen.maxX - panelSize.width - 8
        )

        let originY = button.minY - panelSize.height
        panel.setFrameOrigin(NSPoint(x: clampedX, y: originY))
    }

    private func configure(_ panel: NSPanel) {
        panel.isFloatingPanel = true
        // `.popUpMenu` floats above regular windows but below modals — what menu-bar popovers want.
        panel.level = .popUpMenu
        // `.transient` auto-hides on app deactivate (NSMenu behavior); `.ignoresCycle` keeps it
        // out of the Window > Window menu.
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        // Clear background + non-opaque is required for the backdrop to sample wallpaper.
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
    }

    private func installMonitors() {
        stopMonitors()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.hide()
                return nil
            }
            return event
        }
        // Global mouse-down dismisses on outside click — `.nonactivatingPanel` never takes key
        // so `didResignKey` doesn't fire. Status-item clicks aren't "outside" (they'd race the toggle).
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            let click = NSEvent.mouseLocation
            if self.isOutsideClick(at: click) {
                self.hide()
            }
        }
    }

    private func stopMonitors() {
        if let m = escMonitor { NSEvent.removeMonitor(m) }
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m) }
        escMonitor = nil
        outsideClickMonitor = nil
    }

    /// True if `screenPoint` is outside both the menu panel and the status-item button.
    private func isOutsideClick(at screenPoint: CGPoint) -> Bool {
        if panel.frame.contains(screenPoint) { return false }
        if statusItemAnchor.contains(screenPoint) { return false }
        return true
    }
}

private extension FloatingPanelController {
    /// `MenuPanelController` uses this to dismiss the translation popup when the menu takes over.
    /// The instance is owned by `AppDelegate.shared`; resolving lazily lets the menu panel init
    /// in any order.
    static var shared: FloatingPanelController? {
        AppDelegate.shared.panel
    }
}