// tools/activity-check/main.swift
//
// Checks Window > Activity's list (Sources/Activity/Activity.swift) with no
// internet and no uploads:
//   - an item starts running, takes steps, and ends Done or Problem;
//   - newest first, and the list stops growing at its limit;
//   - track() records a run, passes its result through, and ends the item
//     as the caller's summary says;
//   - each change is announced, so the window refreshes.
//
// Run it with:  bash tools/check-activity.sh

import AppKit

func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }

@MainActor
func run() async {
    let activity = Activity.shared

    var announced = 0
    let observer = NotificationCenter.default.addObserver(forName: Activity.didChange, object: nil, queue: nil) { _ in
        MainActor.assumeIsolated { announced += 1 }
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    let first = activity.start("LoTW", "Upload 2 contacts")
    check(activity.items.first?.id == first && activity.items.first?.state == .running, "a new item starts running, at the top")
    check(activity.runningCount == 1, "one running item is counted")
    activity.update(first, "Uploading 2 contacts with TQSL.")
    check(activity.items.first?.latest == "Uploading 2 contacts with TQSL.", "a step is kept as the latest")
    activity.finish(first, ok: true, latest: "2 contacts sent.")
    check(activity.items.first?.state == .done && activity.items.first?.ended != nil, "finish marks it Done with an end time")
    check(activity.runningCount == 0, "nothing is running after finish")

    let second = activity.start("QRZ Logbook", "Upload 1 contact")
    activity.finish(second, ok: false, latest: "QRZ couldn't be reached.")
    check(activity.items.first?.state == .problem, "a failed run is a Problem, not Done")
    check(activity.items.count >= 2 && activity.items[1].id == first, "newest first: the earlier run is second")

    // track() runs the work, passes each step to the list, and ends the item
    // as the summary says.
    let result = await activity.track("eQSL", "Upload 3 contacts", { progress in
        progress("Sending 3 contacts.")
        return 42
    }, finish: { (ok: $0 == 42, text: "Got \($0).") })
    check(result == 42, "track() returns the work's result")
    check(activity.items.first?.service == "eQSL" && activity.items.first?.state == .done, "track() records a Done item")
    check(activity.items.first?.latest == "Got 42.", "track() shows the summary as the latest")

    // record() is a one-off entry that's already over.
    activity.record("DX cluster", "Connection", ok: false, latest: "Couldn't connect to dx.example.")
    check(activity.items.first?.state == .problem && activity.items.first?.ended != nil, "record() makes a finished entry")

    // The list stops at its limit, so a long session can't grow forever.
    for n in 0..<(Activity.limit + 5) { activity.start("Club Log", "Upload \(n)") }
    check(activity.items.count == Activity.limit, "the list is capped at \(Activity.limit) items")
    check(activity.items.first?.what == "Upload \(Activity.limit + 4)", "the cap drops the oldest, keeping the newest")

    check(announced > 0, "changes are announced for the window to refresh")
}

await run()
print("All activity checks passed.")
