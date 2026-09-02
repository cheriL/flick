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

        let p = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.panel = p
        configure(p)

        let content = TranslatePanelContent(onTranslate: { [weak self] text, target in
            guard let self else { throw CancellationError() }
            let service = OpenAICompatibleService(config: self.store.load())
            return try await service.translate(text, to: target)
        })
        let host = NSHostingController(rootView: content)
        self.hostingController = host
        p.contentViewController = host
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
    }

    private func show(statusItemFrame: NSRect) {
        statusItemAnchor = statusItemFrame
        sizePanelToContent()
        positionPanel()
        panel.orderFrontRegardless()
        installMonitors()
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
