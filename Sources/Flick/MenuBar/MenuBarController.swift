import AppKit
import SwiftUI
import Translation

final class MenuBarController {
    private let store: ConfigStore
    private let panel: FloatingPanelController
    private let monitor: TextSelectionMonitor
    private var subscription: NSObjectProtocol?
    private var clearedSubscription: NSObjectProtocol?
    private var enabledSubscription: NSObjectProtocol?
    private var currentTask: Task<Void, Never>?
    private var lastText: String?

    /// Hidden 1×1 borderless window that hosts the SwiftUI `HiddenTranslationHost`,
    /// which keeps an Apple Translation session alive without showing any UI.
    ///
    /// NOTE: API deviation from brief — the brief stored the host eagerly as
    /// `NSHostingController(rootView: HiddenTranslationHost(session: TranslationSession(source: nil, target: ...)))`.
    /// The macOS SDK on this build host only exposes
    /// `TranslationSession(installedSource:target:)` (macOS 26+), and
    /// `HiddenTranslationHost` is itself `@available(macOS 26.0, *)`, so the host can
    /// only be constructed behind an availability check. It is therefore stored as an
    /// optional window that stays nil on macOS < 26.
    private var translationHostWindow: NSWindow?

    init(store: ConfigStore, panel: FloatingPanelController) {
        self.store = store
        self.panel = panel
        self.monitor = TextSelectionMonitor(provider: AXSelectionProvider())
        // Seed the monitor with the persisted toggle value so the
        // default-ON behaviour matches what's already in UserDefaults.
        self.monitor.isEnabled = store.isSelectionEnabled
        mountHiddenHost()
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
    }

    // MARK: - Private

    private func mountHiddenHost() {
        // See note on `translationHostWindow`: on macOS < 26 the Apple translation path
        // is unavailable at runtime (matching `AppleTranslationService.translate`, which
        // throws `.unsupportedLanguagePair` there), so we mount nothing.
        guard #available(macOS 26.0, *) else { return }

        let session = TranslationSession(
            installedSource: Locale.current.language,
            target: .init(identifier: "zh-Hans")
        )
        let host = NSHostingController(rootView: HiddenTranslationHost(session: session))
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = host
        window.orderBack(nil)
        translationHostWindow = window
    }

    private func handle(_ note: Notification) {
        guard let info = note.userInfo,
              let text = info["text"] as? String,
              let cursorValue = info["cursor"] as? NSValue else { return }
        let isAI = (info["isAI"] as? Bool) ?? false
        let cursor = cursorValue.pointValue

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
        currentTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.panel.showResult(original: text, state: .loading, at: cursor, isAI: isAI, onRetry: { [weak self] in
                    self?.runTranslation(text: text, at: cursor, isAI: isAI)
                })
            }

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
