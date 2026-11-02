import AppKit
import Foundation
import Testing
@testable import Flick

final class FakeProvider: SelectionProvider {
    var queue: [(String, pid_t)] = []
    private var idx = 0
    func currentSelection() -> (text: String, pid: pid_t)? {
        guard idx < queue.count else { return nil }
        defer { idx += 1 }
        let (t, p) = queue[idx]
        return (t, p)
    }
}

/// Serialized: the tests observe the global `flickSelectionChanged` notification
/// and would see each other's posts if run in parallel.
@Suite(.serialized) @MainActor final class TextSelectionMonitorTests {
    /// Reference box — the observer closure can't append across a value-type
    /// return boundary.
    private final class TextsBox {
        var values: [String] = []
    }

    private func collectTexts() -> (box: TextsBox, token: NSObjectProtocol) {
        let box = TextsBox()
        let token = NotificationCenter.default.addObserver(
            forName: .flickSelectionChanged, object: nil, queue: nil
        ) { note in
            if let text = note.userInfo?["text"] as? String {
                box.values.append(text)
            }
        }
        return (box, token)
    }

    @Test func postsNotificationWhenSelectionChanges() {
        let fake = FakeProvider()
        fake.queue = [("hello", 1234), ("hello", 1234), ("world", 1234)]
        let monitor = TextSelectionMonitor(provider: fake, interval: 0.05)

        let (box, token) = collectTexts()
        defer { NotificationCenter.default.removeObserver(token) }

        monitor.poll()
        monitor.poll()
        monitor.poll()
        #expect(box.values == ["hello", "world"])
    }

    @Test func doesNotPostWhenSelectionUnchanged() {
        // First selection is posted (we want the button to appear even
        // when Flick starts up with text already selected), subsequent
        // identical selections are deduplicated. So three identical
        // polls → exactly one notification.
        let fake = FakeProvider()
        fake.queue = [("hello", 1), ("hello", 1), ("hello", 1)]
        let monitor = TextSelectionMonitor(provider: fake, interval: 0.05)

        var posts = 0
        let token = NotificationCenter.default.addObserver(
            forName: .flickSelectionChanged, object: nil, queue: nil
        ) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        monitor.poll()
        monitor.poll()
        monitor.poll()
        #expect(posts == 1)
    }

    @Test func ignoresEmptyAndTooLongSelections() {
        let fake = FakeProvider()
        fake.queue = [("", 1), (String(repeating: "x", count: 5001), 1), ("ok", 1)]
        let monitor = TextSelectionMonitor(provider: fake, interval: 0.05)

        let (box, token) = collectTexts()
        defer { NotificationCenter.default.removeObserver(token) }

        monitor.poll()
        monitor.poll()
        monitor.poll()
        #expect(box.values == ["ok"])
    }
}
