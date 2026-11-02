import Foundation
import os.log

private let chromeLog = Logger(subsystem: "com.cheriL.flick", category: "chrome")

// MARK: - JS payload

enum ChromeSelectionJS {
    /// One expression covering DOM/contenteditable selection (`getSelection`) and
    /// input/textarea selection (`activeElement`), which `getSelection` misses.
    static let payload = """
(function () {
  var s = document.getSelection();
  if (s && !s.isCollapsed && String(s).length > 0) { return String(s); }
  var e = document.activeElement;
  if (e && (e.tagName === 'TEXTAREA' || e.tagName === 'INPUT') &&
      typeof e.selectionStart === 'number' && e.selectionEnd > e.selectionStart) {
    return e.value.slice(e.selectionStart, e.selectionEnd);
  }
  return '';
})()
"""

    static var source: String {
        appleScriptSource(jsLiteral: applescriptLiteral(for: payload))
    }

    static func applescriptLiteral(for js: String) -> String {
        var escaped = js
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }

    static func appleScriptSource(jsLiteral: String) -> String {
        """
        with timeout of 2 seconds
            tell application "Google Chrome" to execute front window's active tab javascript \(jsLiteral)
        end timeout
        """
    }
}

// MARK: - Error classification

struct ChromeScriptError: Error, Equatable {
    let number: Int
    let message: String
}

enum ChromeScriptFailure: Equatable {
    case jsDisabled
    case automationDenied
    case chromeNotRunning
    /// Nothing to read this tick (no window, event timeout) — the path stays usable.
    case noWindow
    case unknown
}

enum ChromeScriptFailureClassifier {
    static func classify(number: Int, message: String) -> ChromeScriptFailure {
        switch number {
        case -1743: return .automationDenied
        case -600: return .chromeNotRunning
        case -1728, -1712: return .noWindow
        case 12: return .jsDisabled
        default: break
        }
        // Chrome localizes this message; the support URL is the locale-stable marker.
        if message.contains("support.google.com/chrome/?p=applescript") { return .jsDisabled }
        return .unknown
    }
}

// MARK: - Engine

/// Pure state machine: no AppleScript, no threads. All reader behaviour is testable here.
struct ChromeSelectionEngine {
    enum Status: Equatable {
        case idle
        case healthy
        case unavailable(ChromeScriptFailure)
    }

    private(set) var status: Status = .idle
    private var lastText: String = ""
    private var lastAt: Date?
    private var lastAttemptAt: Date?

    static let cacheMaxAge: TimeInterval = 1.0
    static let jsDisabledRetry: TimeInterval = 5
    static let notRunningRetry: TimeInterval = 5
    static let automationDeniedRetry: TimeInterval = 30
    static let unknownRetry: TimeInterval = 3

    mutating func ingest(result: Result<String, ChromeScriptError>, at now: Date) {
        lastAttemptAt = now
        switch result {
        case .success(let text):
            status = .healthy
            lastText = text
            lastAt = text.isEmpty ? nil : now
        case .failure(let error):
            lastText = ""
            lastAt = nil
            let failure = ChromeScriptFailureClassifier.classify(number: error.number, message: error.message)
            // Transient failures leave the path healthy so the router doesn't drop to AX
            // just because Chrome had no window open for one tick.
            status = failure == .noWindow ? .healthy : .unavailable(failure)
        }
    }

    func cachedText(now: Date, maxAge: TimeInterval = ChromeSelectionEngine.cacheMaxAge) -> String? {
        guard status == .healthy, let at = lastAt,
              now.timeIntervalSince(at) <= maxAge,
              !lastText.isEmpty else { return nil }
        return lastText
    }

    func shouldAttempt(now: Date) -> Bool {
        guard case .unavailable(let failure) = status, let at = lastAttemptAt else { return true }
        let retry: TimeInterval
        switch failure {
        case .jsDisabled, .chromeNotRunning: retry = ChromeSelectionEngine.jsDisabledRetry
        case .automationDenied: retry = ChromeSelectionEngine.automationDeniedRetry
        case .noWindow, .unknown: retry = ChromeSelectionEngine.unknownRetry
        }
        return now.timeIntervalSince(at) >= retry
    }
}

// MARK: - Runtime

protocol ChromeSelectionReading: AnyObject {
    /// Latest cached selection text, nil when stale / empty / path not healthy.
    func currentText() -> String?
    var isHealthy: Bool { get }
    /// Main-thread hint about which pid (if any) should be polled. Idempotent.
    func setActive(pid: pid_t?)
}

/// Polls Chrome's active-tab selection on a background queue and caches it for the
/// synchronous `SelectionProvider` to read. `NSAppleScript.executeAndReturnError` blocks
/// with a default reply timeout near a minute, so it must never run on the main thread.
final class ChromeSelectionReader: ChromeSelectionReading {
    typealias Executor = (String) throws -> String

    static let liveExecutor: Executor = { source in
        guard let script = NSAppleScript(source: source) else {
            throw ChromeScriptError(number: 0, message: "NSAppleScript init failed")
        }
        var errorInfo: NSDictionary?
        let output = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let number = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? ""
            throw ChromeScriptError(number: number, message: message)
        }
        return output.stringValue ?? ""
    }

    private let executor: Executor
    private let interval: TimeInterval
    private let clock: () -> Date
    private let queue = DispatchQueue(label: "com.cheriL.flick.chrome-selection")
    private var timer: DispatchSourceTimer?
    private var activePID: pid_t?
    private var engine = ChromeSelectionEngine()
    private var lastLoggedStatus: ChromeSelectionEngine.Status = .idle
    private let lock = NSLock()

    init(executor: @escaping Executor = ChromeSelectionReader.liveExecutor,
         interval: TimeInterval = 0.3,
         clock: @escaping () -> Date = Date.init) {
        self.executor = executor
        self.interval = interval
        self.clock = clock
    }

    var isHealthy: Bool {
        lock.lock(); defer { lock.unlock() }
        return engine.status == .healthy
    }

    func currentText() -> String? {
        lock.lock(); defer { lock.unlock() }
        return engine.cachedText(now: clock())
    }

    func setActive(pid: pid_t?) {
        queue.async { [weak self] in
            guard let self else { return }
            self.activePID = pid
            self.updateTimer()
        }
    }

    private func updateTimer() {
        timer?.cancel()
        timer = nil
        guard activePID != nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func tick() {
        guard let pid = activePID else { return }
        // `tell application` relaunches a quit target — guard the pid before every send.
        guard kill(pid, 0) == 0 else {
            record(result: .failure(ChromeScriptError(number: -600, message: "pid gone")))
            return
        }
        lock.lock()
        let attempt = engine.shouldAttempt(now: clock())
        lock.unlock()
        guard attempt else { return }
        let result: Result<String, ChromeScriptError>
        do {
            let raw = try executor(ChromeSelectionJS.source)
            result = .success(String(raw.prefix(10_000)))
        } catch let error as ChromeScriptError {
            result = .failure(error)
        } catch {
            result = .failure(ChromeScriptError(number: 0, message: error.localizedDescription))
        }
        record(result: result)
    }

    private func record(result: Result<String, ChromeScriptError>) {
        lock.lock()
        engine.ingest(result: result, at: clock())
        let status = engine.status
        let changed = status != lastLoggedStatus
        lastLoggedStatus = status
        lock.unlock()
        guard changed else { return }
        switch result {
        case .success:
            chromeLog.notice("chrome path healthy")
        case .failure(let error):
            chromeLog.notice("chrome path \(String(describing: status), privacy: .public) error=\(error.number, privacy: .public) \(error.message, privacy: .public)")
        }
    }
}
