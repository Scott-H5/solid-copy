// RotorControl.swift
//
// Turning the antenna, from the Radio menu (v1.5 item 3):
//
//   Turn Rotor to Station   Control-Shift-Command-T  the bearing to the
//                           call in the logging form (from its lookup)
//   Turn Rotor Long Path    Control-Shift-Command-L  the opposite way
//   Turn Rotor To…          Control-Shift-Command-E  a heading you type
//   Rotor Heading           Control-Shift-Command-H  says where it points
//   Stop Rotor              Control-Shift-Command-S  stops at once
//
// Through a rotctld you run (RotctldClient.swift), turned on in Settings >
// Radio. The rotor only ever moves when you choose one of these: nothing
// turns it by itself.
//
// A turn is said as it starts ("Turning from 120 to 285 degrees, west")
// and when it's over: arrived ("Rotor at 285 degrees, west"), stopped
// short (a rotor that stalls, or hits its stop), or still turning after
// 3 minutes. Each turn is also a line in Window > Activity, since speech
// is only heard while Solid Copy is in front.
//
// The network calls run one at a time on a background queue, each with a
// time limit, so a stuck rotctld never freezes the app. If rotctld
// doesn't answer, that's said, and nothing tries again by itself.

import Foundation

@MainActor
final class RotorControl {
    static let shared = RotorControl()

    // Close enough to the heading asked for to count as there.
    static let arrivedWithin = 2.0
    // How often to ask where it is while it turns. (Vars so the check
    // can make them shorter.)
    static var pollSeconds: TimeInterval = 1
    // No movement for this long, short of the heading: it has stopped.
    static var stalledAfter: TimeInterval = 5
    // A turn still going after this long is reported and no longer watched.
    static let longestTurn: TimeInterval = 180

    // The last heading read, and when: logged with a contact if recent.
    private(set) var heading: Double?
    private(set) var headingAt: Date?

    // The worker that owns the connection, used only on `queue`.
    private final class Worker: @unchecked Sendable {
        var client: RotctldClient?
    }
    private let worker = Worker()
    private let queue = DispatchQueue(label: "Solid Copy rotor")

    // The turn being watched, if any.
    private struct Turn {
        var target: Double
        var activity: UUID
        var started: Date
        var lastMoved: Date
        var lastHeading: Double
    }
    private var turn: Turn?
    private var timer: Timer?

    // What's said; the check swaps in its own to hear it.
    var say: (String) -> Void = { Speaker.announce($0) }

    var isOn: Bool { Settings.rotorEnabled }

    // The heading to log with a contact: read within the last 2 minutes.
    var recentHeading: Double? {
        guard let heading, let headingAt, Date().timeIntervalSince(headingAt) < 120 else { return nil }
        return heading
    }

    // MARK: - Commands

    // Turns to a heading. `toward` says what it's for ("to W1AW").
    func turn(to target: Double, toward: String = "") {
        guard ready() else { return }
        let target = Rotor.normalized(target)
        let what = "Turn to \(Rotor.spoken(target))" + (toward.isEmpty ? "" : " \(toward)")
        run({ client -> Double in
            let from = try client.azimuth()
            try client.turn(to: target)
            return from
        }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let from):
                self.noteHeading(from)
                self.finishTurn((true, "Turned elsewhere instead."))
                let activity = Activity.shared.start("Rotor", what)
                if Rotor.apart(from, target) <= Self.arrivedWithin {
                    let words = "Rotor already at \(Rotor.spoken(from))."
                    Activity.shared.finish(activity, ok: true, latest: words)
                    return self.say(words)
                }
                let words = "Turning from \(Int(from.rounded()) % 360) to \(Rotor.spoken(target))."
                Activity.shared.update(activity, words)
                self.say(words)
                let now = Date()
                self.turn = Turn(target: target, activity: activity, started: now, lastMoved: now, lastHeading: from)
                self.startWatching()
            case .failure(let failure):
                self.report(failure, doing: what)
            }
        }
    }

    func stop() {
        guard ready() else { return }
        run({ client -> Double in
            try client.stop()
            return try client.azimuth()
        }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let at):
                self.noteHeading(at)
                let words = "Rotor stopped at \(Rotor.spoken(at))."
                self.finishTurn((false, words))
                self.say(words)
            case .failure(let failure):
                self.report(failure, doing: "Stop the rotor")
            }
        }
    }

    func sayHeading() {
        guard ready() else { return }
        run({ try $0.azimuth() }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let at):
                self.noteHeading(at)
                self.say("Rotor at \(Rotor.spoken(at))" + (self.turn != nil ? ", turning." : "."))
            case .failure(let failure):
                self.report(failure, doing: "Read the rotor's heading")
            }
        }
    }

    // Settings changed (on, off, or a new address): start afresh.
    func settingsChanged() {
        finishTurn((false, "No longer watched: the rotor settings changed."))
        heading = nil
        headingAt = nil
        let worker = self.worker
        queue.async {
            worker.client?.disconnect()
            worker.client = nil
        }
    }

    // MARK: - Watching a turn

    private func startWatching() {
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.pollSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private var polling = false

    private func poll() {
        guard turn != nil, !polling else { return }
        polling = true
        run({ try $0.azimuth() }) { [weak self] result in
            guard let self else { return }
            self.polling = false
            guard var turn = self.turn else { return }
            switch result {
            case .success(let at):
                self.noteHeading(at)
                let now = Date()
                if Rotor.apart(at, turn.target) <= Self.arrivedWithin {
                    let words = "Rotor at \(Rotor.spoken(at))."
                    self.finishTurn((true, words))
                    return self.say(words)
                }
                if Rotor.apart(at, turn.lastHeading) >= 0.5 {
                    turn.lastMoved = now
                    turn.lastHeading = at
                    self.turn = turn
                } else if now.timeIntervalSince(turn.lastMoved) >= Self.stalledAfter {
                    let words = "The rotor stopped at \(Rotor.spoken(at)), short of \(Int(turn.target.rounded()) % 360)."
                    self.finishTurn((false, words))
                    return self.say(words)
                }
                if now.timeIntervalSince(turn.started) >= Self.longestTurn {
                    let words = "The rotor is still turning after 3 minutes. It's at \(Rotor.spoken(at))."
                    self.finishTurn((false, words))
                    self.say(words)
                }
            case .failure(let failure):
                self.finishTurn(nil)
                self.report(failure, doing: "Watch the rotor turn", activity: turn.activity)
            }
        }
    }

    // Ends the watched turn, if any, with its last words in Activity.
    private func finishTurn(_ outcome: (ok: Bool, words: String)?) {
        timer?.invalidate()
        timer = nil
        if let turn, let outcome { Activity.shared.finish(turn.activity, ok: outcome.ok, latest: outcome.words) }
        turn = nil
    }

    // MARK: - Helpers

    // Says so if no rotor is set up.
    func ready() -> Bool {
        guard isOn else {
            say("No rotor is set up. Turn it on in Settings > Radio, Rotor.")
            return false
        }
        return true
    }

    private func noteHeading(_ degrees: Double) {
        heading = degrees
        headingAt = Date()
    }

    // Runs `work` with the client on the rotor's queue, then `done` here.
    private func run<T: Sendable>(_ work: @escaping @Sendable (RotctldClient) throws -> T,
                                  done: @escaping @MainActor (Result<T, RadioFailure>) -> Void) {
        let address = RotctldClient.address(Settings.rotorAddress)
        let worker = self.worker
        queue.async {
            if worker.client.map({ $0.host != address.host || $0.port != address.port }) ?? true {
                worker.client?.disconnect()
                worker.client = RotctldClient(host: address.host, port: address.port)
            }
            let result: Result<T, RadioFailure>
            do { result = .success(try work(worker.client!)) } catch let failure as RadioFailure {
                worker.client?.disconnect()
                result = .failure(failure)
            } catch {
                worker.client?.disconnect()
                result = .failure(.notAnswering)
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { done(result) } }
        }
    }

    private func report(_ failure: RadioFailure, doing what: String, activity: UUID? = nil) {
        let address = RotctldClient.address(Settings.rotorAddress)
        let words: String
        switch failure {
        case .notRunning:
            words = "No rotctld is answering at \(address.host) port \(address.port). Start rotctld for your rotor, "
                + "then try again."
        case .rejected:
            words = "rotctld refused that. The rotor may not turn that far, or can't do it."
        default:
            words = "rotctld didn't answer. Check that the rotor's controller is on and connected."
        }
        if let activity {
            Activity.shared.finish(activity, ok: false, latest: words)
        } else {
            Activity.shared.record("Rotor", what, ok: false, latest: words)
        }
        say(words)
    }
}
