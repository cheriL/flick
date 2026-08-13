import Foundation
import ServiceManagement

/// Manages the "launch Flick at login" toggle.
///
/// Uses `SMAppService.mainApp` (macOS 13+), which adds the current bundle
/// to the user's Login Items. Note: registration only succeeds for apps
/// in a stable location (e.g. `/Applications`). When Flick is run from
/// the developer's `.build/` directory the call fails with a status the
/// caller can surface to the user.
enum AutoStart {
    /// Whether Flick is currently registered as a login item.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Register Flick as a login item. Throws if the OS refuses — common
    /// causes are: app not in `/Applications`, app is not signed, or the
    /// user denied the prompt in System Settings.
    static func enable() throws {
        try SMAppService.mainApp.register()
    }

    /// Unregister Flick from login items.
    static func disable() throws {
        try SMAppService.mainApp.unregister()
    }
}
