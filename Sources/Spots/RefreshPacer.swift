// RefreshPacer.swift
//
// How often the Spots window shows new spots (its Refresh pop-up, v1.5
// item 1). DX cluster spots stream in the moment they're posted, so on a
// busy band the list changed under you every few seconds, too fast to
// follow by ear. The pacer gathers changes and shows them at most once
// per chosen interval:
//
//   Live               every change at once (as before)
//   Every 15 seconds, 30 seconds, 45 seconds, Every minute
//
// Your own changes (a filter, a band) are shown at once, whatever the
// interval: only spots arriving by themselves wait. Kept apart from the
// window, with no windows in it, so tools/check-spots.sh can test it.

import Foundation

@MainActor
final class RefreshPacer {
    // The pop-up's choices, in order: the title and the interval (nil for live).
    static let choices: [(title: String, seconds: TimeInterval?)] = [
        ("Live", nil), ("Every 15 seconds", 15), ("Every 30 seconds", 30), ("Every 45 seconds", 45),
        ("Every minute", 60),
    ]

    // nil: show each change at once.
    var interval: TimeInterval? {
        didSet {
            timer?.invalidate()
            timer = nil
            // Changes waiting under the old interval: shown now.
            if pending { showNow() }
        }
    }

    private let show: () -> Void
    private var pending = false
    private var timer: Timer?

    init(interval: TimeInterval?, show: @escaping () -> Void) {
        self.interval = interval
        self.show = show
    }

    // Something changed by itself (new spots): shown now, or at the next tick.
    func changed() {
        guard let interval else { return show() }
        pending = true
        guard timer == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // A little slack lets macOS group wake-ups, which saves power.
        timer.tolerance = min(1, interval / 10)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // Shown now (a filter you changed), and nothing left waiting.
    func showNow() {
        pending = false
        show()
    }

    private func tick() {
        guard pending else {
            // Nothing new since the last tick: stop until something comes.
            timer?.invalidate()
            timer = nil
            return
        }
        showNow()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pending = false
    }
}
