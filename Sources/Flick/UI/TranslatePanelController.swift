import AppKit
import SwiftUI

final class TranslatePanelController {
    private let store: ConfigStore
    private weak var selectionPanel: FloatingPanelController?
    private weak var menuPanel: MenuPanelController?
    private let statusItem: NSStatusItem
    private let panel: NSPanel
    private var hostingController: NSHostingController<TranslatePanelContent>?
    private var escMonitor: Any?
    private var outsideClickMonitor: Any?
    private var statusItemAnchor: NSRect = .zero

    init(store: ConfigStore,
         selectionPanel: FloatingPanelController,
         menuPanel: MenuPanelController,
         statusItem: NSStatusItem) {
        self.store = store
        self.selectionPanel = selectionPanel
        self.menuPanel = menuPanel
        self.statusItem = statusItem

        let p = KeyablePanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.panel = p
        configure(p)
        // Hosting controller is rebuilt on every show() so the panel's `@State`
        // (input / targetCode / in-flight task) starts fresh each open.
    }

    deinit { stopMonitors() }

    var isVisible: Bool { panel.isVisible }

    func toggle(statusItemFrame: NSRect) {
        if panel.isVisible {
            hide()
        } else {
            selectionPanel?.dismiss()
            menuPanel?.hide()
            show(statusItemFrame: statusItemFrame)
        }
    }

    func hide() {
        panel.orderOut(nil)
        stopMonitors()
        inFlightTask?.cancel()
        inFlightTask = nil
    }

    private var inFlightTask: Task<Void, Never>?

    private func show(statusItemFrame: NSRect) {
        statusItemAnchor = statusItemFrame
        // Cancel any task left running from a prior show before the view that
        // owned it gets torn down by the rebuild below.
        inFlightTask?.cancel()
        inFlightTask = nil

        let content = TranslatePanelContent(
            onTranslate: { [weak self] text, target in
                guard let self else { throw CancellationError() }
                let service = OpenAICompatibleService(config: self.store.load())
                return try await service.translate(text, to: target)
            },
            onTaskStart: { [weak self] task in
                self?.inFlightTask = task
            }
        )
        let host = NSHostingController(rootView: content)
        self.hostingController = host
        panel.contentViewController = host

        sizePanelToContent()
        positionPanel()
        // An LSUIElement app can't promote a window to key on its own — the
        // window manager refuses because the app isn't on the active-app list.
        // `NSApp.activate` here briefly raises the app so the next
        // `makeKeyAndOrderFront` actually takes.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // Re-focus the input field after layout — `makeNSView` only fires once.
        DispatchQueue.main.async { [weak self] in
            self?.focusFirstTextView()
        }
        installMonitors()
    }

    private func focusFirstTextView() {
        guard let root = panel.contentView else { return }
        Self.focusFirstTextView(in: root)
    }

    private static func focusFirstTextView(in view: NSView) {
        if let textView = view as? NSTextView, textView.isEditable {
            view.window?.makeFirstResponder(textView)
            return
        }
        for sub in view.subviews {
            focusFirstTextView(in: sub)
        }
    }

    private func sizePanelToContent() {
        guard let host = hostingController?.view else { return }
        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize
        guard fitting.width > 0, fitting.height > 0 else { return }
        panel.setContentSize(fitting)
    }

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
            originX = button.midX - panelSize.width / 2
        }

        let clampedX = min(
            max(originX, screen.minX + 8),
            screen.maxX - panelSize.width - 8
        )

        let originY = button.minY - panelSize.height
        panel.setFrameOrigin(NSPoint(x: clampedX, y: originY))
    }

    private func configure(_ panel: NSPanel) {
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
    }

    /// NSPanel's default `canBecomeKey` is false (it inherits from the menu-style contract),
    /// so even after `NSApp.activate` + `makeKeyAndOrderFront` the window manager refuses to
    /// promote it — and the first responder never reaches the text view.
    private final class KeyablePanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private func installMonitors() {
        stopMonitors()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.hide()
                return nil
            }
            return event
        }
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

    private func isOutsideClick(at screenPoint: CGPoint) -> Bool {
        if panel.frame.contains(screenPoint) { return false }
        if statusItemAnchor.contains(screenPoint) { return false }
        return true
    }
}
