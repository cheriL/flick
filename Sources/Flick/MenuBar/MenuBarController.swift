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
        // Seed the monitor with the persisted toggle value so the
        // default-ON behaviour matches what's already in UserDefaults.
        self.monitor.isEnabled = store.isSelectionEnabled
        // The menu popup is owned by `MenuPanelController`, mirroring
        // the way `FloatingPanelController` owns the translation
        // popups. Both popups go through the same `NSPanel` +
        // `backgroundColor = .clear` + `isOpaque = false` configuration
        // — Flick's panels are all built on this one architecture, so
        // adding a new popup or changing the popup look both have one
        // place to look.
        self.menuPanel = MenuPanelController(store: store, onQuit: { NSApp.terminate(nil) })
        // Status item is created here (not lazily in `start`) so we can
        // configure the icon synchronously. The icon-loading helpers
        // (`MenuBarIcon.nsImage`) are pure functions of the bundle, so
        // no async work is needed — but doing this in `start` would
        // briefly show a placeholder SF Symbol in the menu bar if the
        // .icns load were slow, which is what we want to avoid for a
        // accessory app where the menu-bar icon *is* the brand.
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
        // Live-update the monitor when the user flips the menu-bar
        // toggle. The menu UI persists the value to UserDefaults and
        // posts this notification; we just forward it.
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
        // The `NSStatusItem` button routes its click to `toggleMenu`
        // (set in `start`). Sending `action` to the button itself means
        // the standard AppKit status-item click semantics fire — single
        // click toggles, no need to handle mouse-down ourselves.
        button.toolTip = "Flick"
    }

    @objc private func toggleMenu() {
        // If a translation popup is on screen (trigger button waiting
        // for tap, or result panel showing), the menu takes over — the
        // user wants the menu, not a half-visible translation panel.
        panel.dismiss()
        guard let button = statusItem.button else { return }
        // `button.frame` is in status-bar window coordinates; convert
        // to screen so the panel can place itself relative to a known
        // anchor without further coordinate math.
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

        // Selecting text while the menu is open should dismiss the
        // menu — the user has clearly moved on from "browse the menu"
        // to "translate what I just highlighted". Mirrors how
        // NSPopover menus behave in most Apple apps.
        menuPanel.hide()

        // Show trigger button first; the actual translation happens on tap.
        panel.showTrigger(at: cursor, text: text, isAI: isAI) { [weak self] in
            // Mark the selection as consumed so ⌘ toggles, flag changes,
            // or any other event that re-polls won't re-show the trigger
            // over the result panel that's about to appear.
            self?.monitor.markConsumed()
            self?.runTranslation(text: text, at: cursor, isAI: isAI)
        }
    }

    private func runTranslation(text: String, at cursor: CGPoint, isAI: Bool) {
        currentTask?.cancel()
        // Show the loading state synchronously, in the same runloop tick
        // as the click that triggered it. This is the call that hides the
        // trigger panel (via `triggerPanel.orderOut(nil)` inside
        // `showResult`). If we deferred this into the Task, the trigger
        // would still be on screen for a beat — long enough for the
        // global mouse-down monitor to pick up a follow-up click from
        // the user and dismiss the whole popup before the result ever
        // appeared.
        //
        // The subsequent `.success` / `.failure` updates still go through
        // the Task because they originate from async translation work
        // that may complete on a non-main actor.
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