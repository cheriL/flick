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
        let screen = NSScreen.main?.frame ?? .zero
        let origin = PanelPositioning.origin(forPanel: size, near: cursor, on: screen)

        triggerPanel.setFrame(NSRect(origin: origin, size: size), display: true)
        triggerPanel.contentView = NSHostingView(
            rootView: TriggerButtonView(isAI: isAI, onTap: onTap)
        )
        triggerPanel.orderFrontRegardless()
        resultPanel.orderOut(nil)
    }

    func showResult(original: String, state: ResultState, at cursor: CGPoint, isAI: Bool = false, onRetry: @escaping () -> Void) {
        let size = CGSize(width: 360, height: 140) // height grows with content via resizable mask
        let screen = NSScreen.main?.frame ?? .zero
        let origin = PanelPositioning.origin(forPanel: size, near: cursor, on: screen)

        resultPanel.setFrame(NSRect(origin: origin, size: size), display: true)
        resultPanel.contentView = NSHostingView(
            rootView: ResultWindowView(original: original, state: state, isAI: isAI, onRetry: onRetry)
        )
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

    private func configure(_ panel: NSPanel) {
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
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
