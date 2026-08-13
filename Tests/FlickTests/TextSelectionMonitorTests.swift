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

@Suite(.serialized) final class TextSelectionMonitorTests {
    @Test func postsNotificationWhenSelectionChanges() async {
        let fake = FakeProvider()
        fake.queue = [("hello", 1234), ("hello", 1234), ("world", 1234)]
        let monitor = TextSelectionMonitor(provider: fake, interval: 0.05)

        await confirmation("selection changed to 'world'") { confirmation in
            let token = NotificationCenter.default.addObserver(
                forName: .flickSelectionChanged, object: nil, queue: nil
            ) { note in
                if (note.userInfo?["text"] as? String) == "world" {
                    confirmation()
                }
            }
            monitor.start()
            try? await Task.sleep(for: .milliseconds(500))
            monitor.stop()
            NotificationCenter.default.removeObserver(token)
        }
    }

    @Test func doesNotPostWhenSelectionUnchanged() async {
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
        monitor.start()
        try? await Task.sleep(for: .milliseconds(200))
        monitor.stop()
        NotificationCenter.default.removeObserver(token)
        #expect(posts == 1)
    }

    @Test func ignoresEmptyAndTooLongSelections() async {
        let fake = FakeProvider()
        fake.queue = [("", 1), (String(repeating: "x", count: 5001), 1), ("ok", 1)]
        let monitor = TextSelectionMonitor(provider: fake, interval: 0.05)

        await confirmation("selection changed to 'ok'") { confirmation in
            let token = NotificationCenter.default.addObserver(
                forName: .flickSelectionChanged, object: nil, queue: nil
            ) { note in
                if (note.userInfo?["text"] as? String) == "ok" {
                    confirmation()
                }
            }
            monitor.start()
            try? await Task.sleep(for: .milliseconds(500))
            monitor.stop()
            NotificationCenter.default.removeObserver(token)
        }
    }
}