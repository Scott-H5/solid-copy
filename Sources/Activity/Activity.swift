// Activity.swift
//
// What the logging services are doing right now and did lately, for
// Window > Activity (Command-2): each LoTW, QRZ Logbook, Club Log and
// eQSL sync or upload, by hand or automatic, with its latest step and
// how it ended. The window is ActivityWindowController.swift.
//
// Why: an upload of thousands of contacts can take a long time, and with
// no list you can't tell whether it's still going. Each step is also
// said as it happens (the existing progress messages); this keeps them
// in one place you can read at your own pace.
//
// Kept only while Solid Copy is open (not saved to disk), newest first,
// and capped at `limit` so a long session can't grow without bound. Each
// item records what it was for, so the window reads like a history.
//
// The quit warning (AppDelegate.swift) asks Activity whether anything is
// still running, so quitting can't stop an upload half way without asking.

import Foundation

@MainActor
final class Activity {
    static let shared = Activity()
    // Posted on every change; the window and the quit check listen.
    static let didChange = Notification.Name("Activity.didChange")
    static let limit = 200

    enum State: String {
        case running = "Running"
        case done = "Done"
        case problem = "Problem"
    }

    struct Item: Identifiable {
        let id = UUID()
        let service: String
        let what: String
        let started = Date()
        var latest = ""
        var state = State.running
        var ended: Date?
    }

    // Newest first.
    private(set) var items: [Item] = []

    var runningCount: Int { items.filter { $0.state == .running }.count }

    private func index(_ id: UUID) -> Int? { items.firstIndex { $0.id == id } }

    private func changed() { NotificationCenter.default.post(name: Self.didChange, object: nil) }

    // Starts an item and returns its ID for update and finish.
    @discardableResult
    func start(_ service: String, _ what: String) -> UUID {
        let item = Item(service: service, what: what)
        items.insert(item, at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
        changed()
        return item.id
    }

    // The latest step, as it happens.
    func update(_ id: UUID, _ latest: String) {
        guard let i = index(id) else { return }
        items[i].latest = latest
        changed()
    }

    func finish(_ id: UUID, ok: Bool, latest: String) {
        guard let i = index(id) else { return }
        items[i].state = ok ? .done : .problem
        items[i].latest = latest
        items[i].ended = Date()
        changed()
    }

    // A one-off entry that's already over: a download's first success, or
    // a problem that's new.
    func record(_ service: String, _ what: String, ok: Bool, latest: String) {
        finish(start(service, what), ok: ok, latest: latest)
    }

    // Runs `work` as one item: `work` gets a progress function for each
    // step, and `finish` says whether it went well and what to show last.
    func track<T>(_ service: String, _ what: String,
                  _ work: (_ progress: @escaping (String) -> Void) async -> T,
                  finish summary: (T) -> (ok: Bool, text: String)) async -> T {
        let id = start(service, what)
        // A step can come from any thread, so hop to the main actor
        // rather than assume we're already on it.
        let result = await work { [weak self] step in
            Task { @MainActor in self?.update(id, step) }
        }
        let outcome = summary(result)
        finish(id, ok: outcome.ok, latest: outcome.text)
        return result
    }
}
