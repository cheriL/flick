import Foundation
import ServiceManagement

/// Manages the "launch Flick at login" toggle via `SMAppService.mainApp` (macOS 13+).
/// Registration only succeeds for apps in a stable location (e.g. `/Applications`) — fails when
/// run from `.build/` and the caller surfaces the error.
enum AutoStart {
    /// Whether Flick is currently registered as a login item.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Register Flick as a login item. Throws if the OS refuses (app not in `/Applications`,
    /// not signed, or user denied the prompt).
    static func enable() throws {
        try SMAppService.mainApp.register()
    }

    /// Unregister Flick from login items.
    static func disable() throws {
        try SMAppService.mainApp.unregister()
    }
}
