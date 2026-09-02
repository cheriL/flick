import AppKit
import SwiftUI

/// Owns the menu-bar popup `NSPanel`. We host it directly (rather than via SwiftUI's
/// `MenuBarExtra`) so we control show/hide/position and the visual-effect backdrop.
final class MenuBarController {
    private let store: ConfigStore
    private let panel: FloatingPanelController
    private let menuPanel: MenuPanelController
    private let translatePanel: TranslatePanelController
    private let monitor: TextSelectionMonitor
    private var subscription: NSObjectProtocol?
    private var clearedSubscription: NSObjectProtocol?
    private var enabledSubscription: NSObjectProtocol?
    private var currentTask: Task<Void, Never>?

    private let statusItem: NSStatusItem

    init(store: ConfigStore, panel: FloatingPanelController) {
        self.store = store
        self.panel = panel
        self.monitor = TextSelectionMonitor(provider: AXSelectionProvider())
        // Seed the monitor with the persisted toggle so default-ON matches UserDefaults.
        self.monitor.isEnabled = store.isSelectionEnabled
        // Status item is created eagerly so the icon is set before any placeholder can flash.
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Menu popup mirrors FloatingPanelController's popup architecture.
        let mp = MenuPanelController(store: store, onQuit: { NSApp.terminate(nil) })
        self.menuPanel = mp
        self.translatePanel = TranslatePanelController(
            store: store,
            selectionPanel: panel,
            menuPanel: menuPanel,
            statusItem: statusItem
        )
        mp.onOpenTranslate = { [weak self] in self?.openTranslatePanel() }
        configureStatusItem()
    }

    func start() {
        monitor.start()
        subscription = NotificationCenter.default.addObserver(
            forName: .flickSelectionChanged, object: nil, queue: .main
        ) { [weak self] note in
            self?.handle(note)
        }
        clearedSubscription = NotificationCenter.default.addObserver(
            forName: .flickSelectionCleared, object: nil, queue: .main
        ) { [weak self] _ in
            self?.panel.dismiss()
        }
        // Forward the menu-bar toggle notification into the monitor.
        enabledSubscription = NotificationCenter.default.addObserver(
            forName: .flickSelectionEnabledChanged, object: nil, queue: .main
        ) { [weak self] note in
            let enabled = (note.userInfo?["enabled"] as? Bool) ?? self?.store.isSelectionEnabled ?? true
            self?.monitor.isEnabled = enabled
        }
        // Cancel the in-flight Task so the result doesn't pop back up after dismissal mid-loading.
        panel.onDismiss = { [weak self] in
            self?.currentTask?.cancel()
        }
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleMenu)
    }

    func stop() {
        monitor.stop()
        if let s = subscription { NotificationCenter.default.removeObserver(s) }
        if let s = clearedSubscription { NotificationCenter.default.removeObserver(s) }
        if let s = enabledSubscription { NotificationCenter.default.removeObserver(s) }
        subscription = nil
        clearedSubscription = nil
        enabledSubscription = nil
        currentTask?.cancel()
        panel.dismiss()
        menuPanel.hide()
    }

    // MARK: - Status item

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "f.square.fill",
                               accessibilityDescription: "Flick")
        // `NSImage(systemSymbolName:)` defaults to `isTemplate = true`, so the menu bar
        // renders the glyph as a monochrome mask against light/dark backgrounds.
        // Routing the click through `action` gives us standard AppKit status-item toggle semantics.
        button.toolTip = "Flick"
    }

    @objc private func toggleMenu() {
        // Menu wins over any translation popup — user wants the menu, not a half-visible panel.
        translatePanel.hide()
        panel.dismiss()
        guard let button = statusItem.button else { return }
        // Convert from status-bar window coords to screen coords for the panel anchor.
        let anchor: NSRect
        if let win = button.window {
            anchor = win.convertToScreen(button.frame)
        } else {
            anchor = button.frame
        }
        menuPanel.toggle(statusItemFrame: anchor)
    }

    func openTranslatePanel() {
        guard let button = statusItem.button, let win = button.window else { return }
        let anchor = win.convertToScreen(button.frame)
        translatePanel.toggle(statusItemFrame: anchor)
    }

    // MARK: - Private

    private func handle(_ note: Notification) {
        // User is in the manual translate panel — selecting text inside its
        // input field (or anywhere while it's up) is part of the manual flow
        // and shouldn't fire the auto-translate popup or dismiss the panel.
        if translatePanel.isVisible { return }

        guard let info = note.userInfo,
              let text = info["text"] as? String,
              let cursorValue = info["cursor"] as? NSValue else { return }
        let cursor = cursorValue.pointValue

        // Selection in another app while the menu is open = user moved on. Dismiss menu first.
        menuPanel.hide()

        // Show trigger button first; the actual translation happens on tap.
        panel.showTrigger(at: cursor, text: text) { [weak self] in
            // Mark selection consumed so re-polls don't re-show the trigger
            // over the result panel that's about to appear.
            self?.monitor.markConsumed()
            self?.runTranslation(text: text, at: cursor)
        }
    }

    private func runTranslation(text: String, at cursor: CGPoint) {
        currentTask?.cancel()
        // Show loading synchronously — `showResult` hides the trigger in the same runloop tick
        // as the click. Deferring into the Task leaves the trigger up long enough for a follow-up
        // click to dismiss the popup before the result appears.
        panel.showResult(original: text, state: .loading, at: cursor, onRetry: { [weak self] in
            self?.runTranslation(text: text, at: cursor)
        })
        currentTask = Task { [weak self] in
            guard let self else { return }
            let target = Locale.Language(identifier: Locale.preferredLanguages.first ?? "en")
            let service = OpenAICompatibleService(config: store.load())

            do {
                let translated = try await service.translate(text, to: target)
                if Task.isCancelled { return }
                await MainActor.run {
                    if Task.isCancelled { return }
                    self.panel.showResult(original: text, state: .success(translated), at: cursor, onRetry: { [weak self] in
                        self?.runTranslation(text: text, at: cursor)
                    })
                }
            } catch {
                if Task.isCancelled { return }
                let msg = (error as? TranslationError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    if Task.isCancelled { return }
                    self.panel.showResult(original: text, state: .failure(msg), at: cursor, onRetry: { [weak self] in
                        self?.runTranslation(text: text, at: cursor)
                    })
                }
            }
        }
    }
}