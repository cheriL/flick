import AppKit
import SwiftUI

final class MenuBarController {
    private let store: ConfigStore
    private let panel: FloatingPanelController
    private let menuPanel: MenuPanelController
    private let monitor: TextSelectionMonitor
    private var subscription: NSObjectProtocol?
    private var clearedSubscription: NSObjectProtocol?
    private var enabledSubscription: NSObjectProtocol?
    private var currentTask: Task<Void, Never>?
    private var lastText: String?

    private let statusItem: NSStatusItem

    init(store: ConfigStore, panel: FloatingPanelController) {
        self.store = store
        self.panel = panel
        self.monitor = TextSelectionMonitor(provider: AXSelectionProvider())
        // Seed the monitor with the persisted toggle so default-ON matches UserDefaults.
        self.monitor.isEnabled = store.isSelectionEnabled
        // Menu popup mirrors FloatingPanelController's popup architecture.
        self.menuPanel = MenuPanelController(store: store, onQuit: { NSApp.terminate(nil) })
        // Status item is created eagerly so the icon is set before any placeholder can flash.
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
        if let icon = MenuBarIcon.nsImage() {
            button.image = icon
        } else {
            button.image = NSImage(systemSymbolName: "character.bubble.fill",
                                   accessibilityDescription: "Flick")
        }
        // Routing the click through `action` gives us standard AppKit status-item toggle semantics.
        button.toolTip = "Flick"
    }

    @objc private func toggleMenu() {
        // Menu wins over any translation popup — user wants the menu, not a half-visible panel.
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

    // MARK: - Private

    private func handle(_ note: Notification) {
        guard let info = note.userInfo,
              let text = info["text"] as? String,
              let cursorValue = info["cursor"] as? NSValue else { return }
        let isAI = (info["isAI"] as? Bool) ?? false
        let cursor = cursorValue.pointValue

        // Selection in another app while the menu is open = user moved on. Dismiss menu first.
        menuPanel.hide()

        // Show trigger button first; the actual translation happens on tap.
        panel.showTrigger(at: cursor, text: text, isAI: isAI) { [weak self] in
            // Mark selection consumed so ⌘ toggles / flag changes don't re-show the trigger
            // over the result panel that's about to appear.
            self?.monitor.markConsumed()
            self?.runTranslation(text: text, at: cursor, isAI: isAI)
        }
    }

    private func runTranslation(text: String, at cursor: CGPoint, isAI: Bool) {
        currentTask?.cancel()
        // Show loading synchronously — `showResult` hides the trigger in the same runloop tick
        // as the click. Deferring into the Task leaves the trigger up long enough for a follow-up
        // click to dismiss the popup before the result appears.
        panel.showResult(original: text, state: .loading, at: cursor, isAI: isAI, onRetry: { [weak self] in
            self?.runTranslation(text: text, at: cursor, isAI: isAI)
        })
        currentTask = Task { [weak self] in
            guard let self else { return }
            let target = Locale.Language(identifier: Locale.preferredLanguages.first ?? "en")
            let service: TranslationService = isAI
                ? OpenAICompatibleService(config: store.load())
                : AppleTranslationService()

            do {
                let translated = try await service.translate(text, to: target)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.panel.showResult(original: text, state: .success(translated), at: cursor, isAI: isAI, onRetry: { [weak self] in
                        self?.runTranslation(text: text, at: cursor, isAI: isAI)
                    })
                }
            } catch {
                if Task.isCancelled { return }
                let msg = (error as? TranslationError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    self.panel.showResult(original: text, state: .failure(msg), at: cursor, isAI: isAI, onRetry: { [weak self] in
                        self?.runTranslation(text: text, at: cursor, isAI: isAI)
                    })
                }
            }
        }
    }
}