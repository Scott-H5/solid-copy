// BandWarning.swift
//
// The out-of-band warning (v1.6 item 5): when the radio settles outside
// your privileges, or in a mode your class may not use there, Solid Copy
// plays the warning sound and says so, once:
//
//   "Outside your Extra privileges: 14.3520 MHz. Nearest: 14.225 to 14.350."
//   "Phone isn't allowed at 14.100 MHz for Extra. Phone: 14.150 to 14.350."
//
// It waits until the radio has stayed there 1.5 seconds, so tuning
// across a band edge doesn't chatter, and says nothing more until you're
// somewhere else that's wrong (back inside, it's quiet). Far from any
// band (broadcast stations, say) it says nothing: that's listening.
//
// The radio's mode: CW, data (its data modes, or any mode while WSJT-X
// has said what it's doing in the last 2 minutes, since many run FT8 in
// plain USB), or phone. It warns about where you are, not what you
// transmit: Solid Copy can't tell a contact from listening.
//
// Needs a license class (Settings > Band Plan), and can be turned off
// there. The plan is read from its file when settings change.

import AppKit

@MainActor
final class BandWarning {
    static let shared = BandWarning()
    static let settleSeconds: TimeInterval = 1.5

    // Read from the folder when first needed (the checks give their own
    // with use(_:) instead, so they never touch the folder).
    private var loadedPlan: BandPlan?
    var plan: BandPlan {
        if let loadedPlan { return loadedPlan }
        let plan = BandPlanList.current(named: Settings.bandPlanName, in: BandPlanList.load())
        loadedPlan = plan
        return plan
    }
    private var lastWarned: String?
    private var pending: Task<Void, Never>?
    // The kind the pending warning is waiting on. The radio is read
    // several times a second, and each reading lands here: the wait must
    // not start again for the same trouble, or it never ends (found
    // 22 November 2026: no warning at 14.356 with a real radio).
    private var pendingKind: String?
    // How it's said; the checks listen in.
    var say: (String) -> Void = { text in
        Speaker.Cue.warning.play()
        Speaker.announce(text)
    }
    // What the radio is doing; the checks give their own.
    var reading: () -> RadioReading? = { RadioMonitor.shared.reading }
    var settle: TimeInterval = settleSeconds

    func start() {
        NotificationCenter.default.addObserver(forName: RadioMonitor.didChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { BandWarning.shared.radioChanged() }
        }
        NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { BandWarning.shared.reloadPlan() }
        }
    }

    func reloadPlan() {
        loadedPlan = BandPlanList.current(named: Settings.bandPlanName, in: BandPlanList.load())
        lastWarned = nil
    }

    // Uses `plan` for the checks without the folder.
    func use(_ plan: BandPlan) {
        loadedPlan = plan
        lastWarned = nil
    }

    // The radio's mode as the plan's: data while WSJT-X is working.
    static func mode(of reading: RadioReading, now: Date = Date()) -> BandPlan.Mode? {
        if let digital = RadioReading.digitalMode, now.timeIntervalSince(digital.said) < 120 { return .data }
        return BandPlan.mode(ofRadioMode: reading.mode)
    }

    // What's wrong where the radio is, in words, with its kind: one
    // warning per kind ("outside" with its nearest range, or the mode and
    // where it's allowed; the frequency left out, so tuning within the
    // same trouble isn't said again). Nil if nothing's wrong.
    func problem(now: Date = Date()) -> (text: String, kind: String)? {
        let licenseClass = Settings.licenseClass
        guard Settings.bandWarning, !licenseClass.isEmpty, let reading = reading() else { return nil }
        let here = BandPlan.megahertz(reading.hertz)
        switch plan.verdict(at: reading.hertz, mode: Self.mode(of: reading, now: now), for: licenseClass) {
        case .allowed, .notNearABand:
            return nil
        case .outsidePrivileges(let nearest):
            return ("Outside your \(licenseClass) privileges: \(here) MHz." + (nearest.isEmpty ? "" : " \(nearest)."),
                    "outside \(nearest)")
        case .modeNotAllowed(let mode, let allowed, let whereAllowed):
            let name = mode == .cw ? "CW" : mode.rawValue.capitalized
            return ("\(name) isn't allowed at \(here) MHz for \(licenseClass); here it's \(BandPlan.spoken(allowed))."
                    + (whereAllowed.isEmpty ? "" : " \(name): \(whereAllowed)."), "mode \(name) \(whereAllowed)")
        }
    }

    func radioChanged() {
        guard let kind = problem()?.kind else {
            pending?.cancel()
            pending = nil
            pendingKind = nil
            lastWarned = nil
            return
        }
        // The same trouble as last said, or already waiting to be: quiet.
        guard kind != lastWarned, kind != pendingKind else { return }
        pending?.cancel()
        pendingKind = kind
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.settle ?? 1.5) * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.pendingKind = nil
            guard let now = self.problem(), now.kind == kind else { return }
            self.lastWarned = kind
            self.say(now.text)
            Activity.shared.record("Radio", "Band plan", ok: false, latest: now.text)
        }
    }
}
