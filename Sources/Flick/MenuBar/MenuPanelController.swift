import AppKit
import SwiftUI

/// Owns and manages the menu-bar popup panel.
///
/// Mirrors `FloatingPanelController`'s architecture on purpose — both
/// Flick popups (the trigger/result translation popups, and this menu)
/// are `NSPanel`s we create and configure ourselves. SwiftUI's
/// `MenuBarExtra` was the previous choice for this menu, but its
/// hosting panel was opaque and SwiftUI-auto-applied Liquid Glass to it
/// on macOS 26+, both unreachable from outside the scene — so neither
/// `NSVisualEffectView.blendingMode = .behindWindow` nor
/// `windowResizability` tweaks made it past SwiftUI's hosting wrapper,
/// and the menu could never achieve the Tailscale/NSMenu frosted look
/// or resize cleanly when its content height changed. Owning the
/// panel directly fixes both: `isOpaque = false` lets the visual effect
/// view sample wallpaper, and we get the full `NSPanel` lifecycle to
/// drive show/hide/position ourselves.
final class MenuPanelController {
    private let store: ConfigStore
    private let onQuit: () -> Void
    private let panel: NSPanel
    // `var` (not `let`) because we can't create the hosting controller
    // until `self` is fully initialised — its `onQuit` closure captures
    // `[weak self]`, which Swift's stored-property rule forbids before
    // every `let` is set. See `init` for the two-phase build.
    private var hostingController: NSHostingController<MenuBarContent>?
    private var escMonitor: Any?
    private var outsideClickMonitor: Any?
    /// Anchor (screen rect) of the `NSStatusItem` button at the moment
    /// the panel was last shown. Cached so the click-outside monitor
    /// can recognise "the click landed on the status item itself" as a
    /// non-dismiss (the user is toggling the menu back open, not
    /// clicking elsewhere).
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

        // Hosting controller is built once and reused across show/hide
        // cycles so the SwiftUI `MenuBarContent`'s `@State` (the 1 Hz
        // TCC re-check timer, `isTrusted`, `selectionEnabled`) survives
        // between toggles. SwiftUI's old `MenuBarExtra` got the same
        // persistence for free; with a manual panel we have to arrange
        // it ourselves by not tearing down the view.
        //
        // The frosted-glass backdrop comes from SwiftUI's macOS 26+
        // `.glassEffect(.regular)` on the root view itself (see
        // `MenuBarContent`) — no AppKit-level visual effect view
        // needed. The previous `NSVisualEffectView` + `.behindWindow`
        // path was the right idea on macOS 13/14 but the
        // `.behindWindow` framebuffer sampling was effectively disabled
        // on macOS 26 (Liquid Glass replaced the surface behind the
        // panel before the visual effect could sample it). `.glassEffect`
        // composes against that same Liquid Glass pass, which is why
        // it works where `NSVisualEffectView` did not.
        //
        // Capture `onQuit` strongly into the closure so the body can
        // stay a one-liner — going through `[weak self]` and chaining
        // `self?.onQuit()` works too, but the strong capture makes the
        // ownership story obvious: the menu-panel's *job* is to hide
        // itself before app-quit runs, and the app-quit closure is
        // independent of `MenuPanelController`'s lifetime.
        //
        // `hostingController` is a `var` optional purely to defer this
        // assignment past the strict-init checkpoint.
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

    /// Show the menu anchored beneath the given status-item button, or
    /// hide it if it's already visible. `statusItemFrame` is in screen
    /// coordinates (callers get this from `button.convertToScreen`).
    /// The panel is left- or right-aligned to the button depending on
    /// which side has more room (see `positionPanel()`).
    func toggle(statusItemFrame: NSRect) {
        if panel.isVisible {
            hide()
        } else {
            // A new show may overlap the trigger/result translation
            // popup. Menu wins — dismiss the translation popup first so
            // the user sees one panel at a time.
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

    /// Resize the `NSPanel` to match the SwiftUI content's intrinsic
    /// size. `MenuBarContent` declares `.frame(width: 210)` and lets
    /// the height fall out of its `VStack`, so this is the one place
    /// that ties the panel frame to the SwiftUI layout — equivalent to
    /// the `.windowResizability(.contentSize)` modifier the
    /// `MenuBarExtra` version used to rely on.
    private func sizePanelToContent() {
        guard let host = hostingController?.view else { return }
        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize
        guard fitting.width > 0, fitting.height > 0 else { return }
        panel.setContentSize(fitting)
    }

    /// Place the panel just below the status item button. By default the
    /// panel's left edge meets the button's left edge (panel extends
    /// to the right of the button), which is what users expect for a
    /// status item anywhere except the very right edge of the menu bar.
/// If the panel would overflow the right edge of its screen, we flip
/// to right-aligning (panel extends to the left of the button) — the
/// same fallback `NSPopover` uses, and what we want for status items
/// pinned against the screen's right edge (like the system wifi /
/// battery icons, where there's no room to the right).
///
/// Earlier versions of this method tried to pick alignment by which
/// half of the screen the button was on. That read right at first
/// glance but failed for status items in the *middle* of a wide
/// menu bar: the panel would left-extend past the button toward the
/// screen centre, ending up on the wrong side of where the user
/// clicked (user feedback: "位置还是不对，出现在了左半边"). The
/// space-based rule is the same rule every macOS popover follows.
private func positionPanel() {
        let panelSize = panel.frame.size
        let button = statusItemAnchor
        let screen = PanelPositioning.screenFrame(
            for: NSPoint(x: button.midX, y: button.midY),
            in: NSScreen.screens.map(\.frame),
            fallback: NSScreen.main?.frame ?? .zero
        )

        // Default: panel's left edge meets the button's left edge.
        // Fallback (panel won't fit to the right of the button):
        // panel's right edge meets the button's right edge.
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
            // Neither side fits the whole panel — center it on the
            // button and let it spill into whichever side has more
            // room. (Doesn't happen for a 220pt panel on a 1512pt
            // screen, but the code is general.)
            originX = button.midX - panelSize.width / 2
        }

        // Clamp inside the screen edge with an 8pt margin so the
        // panel never sits flush against the screen border.
        let clampedX = min(
            max(originX, screen.minX + 8),
            screen.maxX - panelSize.width - 8
        )

        let originY = button.minY - panelSize.height - 1
        panel.setFrameOrigin(NSPoint(x: clampedX, y: originY))
    }

    private func configure(_ panel: NSPanel) {
        panel.isFloatingPanel = true
        // `.popUpMenu` is the same level macOS uses for menu-bar
        // popovers — it floats above regular app windows but below
        // modal dialogs, which is what we want.
        panel.level = .popUpMenu
        // `.transient` makes AppKit auto-hide the panel when the app
        // deactivates (matches NSMenu behavior). `.ignoresCycle` keeps
        // it out of the Window > Window menu.
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        // Clear background + non-opaque panel is what lets the
        // `NSVisualEffectView`'s `.behindWindow` sample wallpaper
        // pixels. Without both, the visual effect has nothing real to
        // blur and degrades to a flat tinted block — same failure mode
        // we hit under `MenuBarExtra`.
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
        // Global mouse-down watcher: dismiss the menu on outside click.
        // `NSPanel` doesn't fire `didResignKey` for click-outside on
        // `.nonactivatingPanel` (the panel never takes key in the first
        // place), so we install a global monitor like
        // `FloatingPanelController` does for the translation popups.
        //
        // Clicks on the status item itself are *not* "outside" — the
        // user's next action is to toggle the menu via the same button,
        // which would race against the monitor and dismiss the menu as
        // it tries to open.
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

    /// True if `screenPoint` is outside the menu panel *and* outside
    /// the status item button (so a click on the button is treated as
    /// an inside click — the monitor defers dismissal to the button's
    /// own action, which `MenuBarController` handles).
    private func isOutsideClick(at screenPoint: CGPoint) -> Bool {
        if panel.frame.contains(screenPoint) { return false }
        if statusItemAnchor.contains(screenPoint) { return false }
        return true
    }
}

private extension FloatingPanelController {
    /// Convenience for `MenuPanelController` to dismiss the translation
    /// popup when the menu takes over the focus slot. The instance is
    /// owned by `AppDelegate.shared`, which the MenuBarController wires
    /// up at `applicationDidFinishLaunching`. We resolve it lazily so
    /// `MenuPanelController` can be initialised in any order.
    static var shared: FloatingPanelController? {
        AppDelegate.shared.panel
    }
}