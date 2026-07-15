import AppKit
import F2QuickNoteCore

/// Polls the general pasteboard once per second and remembers when it last
/// changed, so the capture flow can decide whether the content is fresh.
final class ClipboardTracker {
    private var lastChangeCount: Int
    private(set) var lastChangeDate: Date?
    private var timer: Timer?

    init() {
        // Baseline: whatever is on the pasteboard at launch has an unknown
        // age, so lastChangeDate stays nil (treated as stale).
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let count = NSPasteboard.general.changeCount
        if count != lastChangeCount {
            lastChangeCount = count
            lastChangeDate = Date()
        }
    }

    func isFresh(within window: TimeInterval) -> Bool {
        // If the pasteboard changed since the last poll tick, count it as a
        // change happening "now" so a copy immediately followed by F2 works.
        if NSPasteboard.general.changeCount != lastChangeCount {
            poll()
        }
        return ClipboardFreshness.isFresh(lastChange: lastChangeDate, window: window)
    }
}
