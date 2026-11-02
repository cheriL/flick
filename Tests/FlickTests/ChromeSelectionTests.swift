import Foundation
import Testing
@testable import Flick

@Suite final class ChromeSelectionJSTests {
    @Test func escapesQuotesAndBackslashes() {
        let literal = ChromeSelectionJS.applescriptLiteral(for: "say \"hi\" \\ done")
        #expect(literal == "\"say \\\"hi\\\" \\\\ done\"")
    }

    @Test func leavesSingleQuotesUntouched() {
        #expect(ChromeSelectionJS.applescriptLiteral(for: "it's") == "\"it's\"")
    }

    @Test func payloadLiteralIsSingleLineWithBothBranches() {
        let literal = ChromeSelectionJS.applescriptLiteral(for: ChromeSelectionJS.payload)
        #expect(!literal.contains("\n"))
        #expect(literal.contains("getSelection()"))
        #expect(literal.contains("selectionStart"))
    }

    @Test func sourceEmbedsLiteralInTellBlock() {
        let source = ChromeSelectionJS.appleScriptSource(jsLiteral: "\"x\"")
        #expect(source.contains("tell application \"Google Chrome\" to execute front window's active tab javascript \"x\""))
        #expect(source.contains("with timeout of 2 seconds"))
    }
}

@Suite final class ChromeScriptFailureClassifierTests {
    /// Fixture captured from a real zh-CN Chrome with the dev setting off (2026-11-02).
    private static let jsDisabledFixture = ChromeScriptError(
        number: 12,
        message: "“Google Chrome”遇到一个错误：通过 AppleScript 执行 JavaScript 的功能已关闭。要开启此功能，请在菜单栏中依次转到“查看”>“开发者”>“允许 Apple 事件中的 JavaScript”。如需更多信息，请访问 https://support.google.com/chrome/?p=applescript"
    )

    @Test func classifiesKnownNumbers() {
        #expect(ChromeScriptFailureClassifier.classify(number: -1743, message: "Not authorized") == .automationDenied)
        #expect(ChromeScriptFailureClassifier.classify(number: -600, message: "x") == .chromeNotRunning)
        #expect(ChromeScriptFailureClassifier.classify(number: -1728, message: "Can't get window.") == .noWindow)
        #expect(ChromeScriptFailureClassifier.classify(number: -1712, message: "timed out") == .noWindow)
    }

    @Test func classifiesJsDisabledByNumberAndByURL() {
        #expect(ChromeScriptFailureClassifier.classify(number: 12, message: "off") == .jsDisabled)
        // Locale-stable marker for Chrome builds that report a different number.
        #expect(ChromeScriptFailureClassifier.classify(number: 0, message: Self.jsDisabledFixture.message) == .jsDisabled)
    }

    @Test func unknownFallsBack() {
        #expect(ChromeScriptFailureClassifier.classify(number: -50, message: "weird") == .unknown)
    }
}

@Suite final class ChromeSelectionEngineTests {
    private let t0 = Date(timeIntervalSince1970: 1000)

    @Test func successCachesTextUntilMaxAge() {
        var engine = ChromeSelectionEngine()
        engine.ingest(result: .success("hello"), at: t0)
        #expect(engine.status == .healthy)
        #expect(engine.cachedText(now: t0.addingTimeInterval(0.5)) == "hello")
        #expect(engine.cachedText(now: t0.addingTimeInterval(1.5)) == nil)
    }

    @Test func emptySuccessIsHealthyWithNoCachedText() {
        var engine = ChromeSelectionEngine()
        engine.ingest(result: .success(""), at: t0)
        #expect(engine.status == .healthy)
        #expect(engine.cachedText(now: t0) == nil)
    }

    @Test func noWindowStaysHealthyAndRetriesNextTick() {
        var engine = ChromeSelectionEngine()
        engine.ingest(result: .failure(ChromeScriptError(number: -1728, message: "Can't get window.")), at: t0)
        #expect(engine.status == .healthy)
        #expect(engine.cachedText(now: t0) == nil)
        #expect(engine.shouldAttempt(now: t0.addingTimeInterval(0.1)))
    }

    @Test func unavailableBacksOffPerFailure() {
        var engine = ChromeSelectionEngine()
        engine.ingest(result: .failure(ChromeScriptError(number: 12, message: "off")), at: t0)
        #expect(engine.status == .unavailable(.jsDisabled))
        #expect(!engine.shouldAttempt(now: t0.addingTimeInterval(4.9)))
        #expect(engine.shouldAttempt(now: t0.addingTimeInterval(5.0)))

        engine.ingest(result: .failure(ChromeScriptError(number: -1743, message: "denied")), at: t0)
        #expect(engine.status == .unavailable(.automationDenied))
        #expect(!engine.shouldAttempt(now: t0.addingTimeInterval(29)))
        #expect(engine.shouldAttempt(now: t0.addingTimeInterval(30)))

        engine.ingest(result: .failure(ChromeScriptError(number: -50, message: "weird")), at: t0)
        #expect(engine.status == .unavailable(.unknown))
        #expect(!engine.shouldAttempt(now: t0.addingTimeInterval(2.9)))
        #expect(engine.shouldAttempt(now: t0.addingTimeInterval(3.0)))
    }

    @Test func recoveryClearsBackoff() {
        var engine = ChromeSelectionEngine()
        engine.ingest(result: .failure(ChromeScriptError(number: -1743, message: "denied")), at: t0)
        engine.ingest(result: .success("back"), at: t0)
        #expect(engine.status == .healthy)
        #expect(engine.shouldAttempt(now: t0))
    }
}

@Suite final class ChromeSelectionReaderTests {
    final class Counter {
        private let lock = NSLock()
        private var value = 0
        var count: Int {
            lock.lock(); defer { lock.unlock() }
            return value
        }
        func increment() {
            lock.lock(); defer { lock.unlock() }
            value += 1
        }
    }

    /// Regression: the router calls setActive on every monitor tick. If that re-arms the
    /// poll timer, the timer perpetually postpones its first fire and never polls.
    @Test func duplicateSetActiveDoesNotStarvePollTimer() async {
        let counter = Counter()
        let reader = ChromeSelectionReader(
            executor: { _ in
                counter.increment()
                return ""
            },
            interval: 0.02
        )
        reader.setActive(pid: getpid())
        for _ in 0..<8 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            reader.setActive(pid: getpid())
        }
        #expect(counter.count >= 3)
    }
}

@Suite final class RoutedSelectionProviderTests {
    final class SpyReader: ChromeSelectionReading {
        var text: String?
        var healthy = false
        private(set) var activeCalls: [pid_t?] = []
        func currentText() -> String? { text }
        var isHealthy: Bool { healthy }
        func setActive(pid: pid_t?) { activeCalls.append(pid) }
    }

    final class SpyProvider: SelectionProvider {
        var result: (String, pid_t)?
        private(set) var callCount = 0
        func currentSelection() -> (text: String, pid: pid_t)? {
            callCount += 1
            return result
        }
    }

    private func makeRouter(front: RoutedSelectionProvider.FrontmostInfo?,
                            reader: SpyReader,
                            ax: SpyProvider,
                            supplement: @escaping (pid_t) -> String? = { _ in nil }) -> RoutedSelectionProvider {
        RoutedSelectionProvider(frontmost: { front }, chromeReader: reader, axProvider: ax, nativeSupplement: supplement)
    }

    @Test func chromeHealthyReturnsScriptTextWithoutAX() {
        let reader = SpyReader()
        reader.text = "网页选区"
        reader.healthy = true
        let ax = SpyProvider()
        let sel = makeRouter(front: ("com.google.Chrome", 42), reader: reader, ax: ax).currentSelection()
        #expect(sel?.text == "网页选区")
        #expect(sel?.pid == 42)
        #expect(ax.callCount == 0)
        #expect(reader.activeCalls == [42])
    }

    @Test func chromeHealthyEmptyFallsToNativeSupplement() {
        let reader = SpyReader()
        reader.healthy = true
        let ax = SpyProvider()
        var supplementPids: [pid_t] = []
        let router = RoutedSelectionProvider(
            frontmost: { ("com.google.Chrome", 7) },
            chromeReader: reader,
            axProvider: ax
        ) { pid in
            supplementPids.append(pid)
            return "地址栏文本"
        }
        let sel = router.currentSelection()
        #expect(sel?.text == "地址栏文本")
        #expect(sel?.pid == 7)
        #expect(supplementPids == [7])
        #expect(ax.callCount == 0)
    }

    @Test func chromeHealthyEmptyWithoutSupplementReturnsNilNotAX() {
        let reader = SpyReader()
        reader.healthy = true
        let ax = SpyProvider()
        #expect(makeRouter(front: ("com.google.Chrome", 7), reader: reader, ax: ax).currentSelection() == nil)
        #expect(ax.callCount == 0)
    }

    @Test func chromeUnavailableFallsBackToAX() {
        let reader = SpyReader()
        let ax = SpyProvider()
        ax.result = ("AX text", 42)
        let sel = makeRouter(front: ("com.google.Chrome", 42), reader: reader, ax: ax).currentSelection()
        #expect(sel?.text == "AX text")
        #expect(ax.callCount == 1)
        #expect(reader.activeCalls == [42])
    }

    @Test func nonChromeUsesAXAndDeactivatesReader() {
        let reader = SpyReader()
        reader.text = "stale"
        reader.healthy = true
        let ax = SpyProvider()
        ax.result = ("Safari text", 9)
        let sel = makeRouter(front: ("com.apple.Safari", 9), reader: reader, ax: ax).currentSelection()
        #expect(sel?.text == "Safari text")
        #expect(ax.callCount == 1)
        #expect(reader.activeCalls == [nil])
    }

    @Test func nilFrontmostReturnsNil() {
        let reader = SpyReader()
        let ax = SpyProvider()
        #expect(makeRouter(front: nil, reader: reader, ax: ax).currentSelection() == nil)
        #expect(ax.callCount == 0)
    }
}
