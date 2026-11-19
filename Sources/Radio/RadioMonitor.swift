// RadioMonitor.swift
//
// Keeps Solid Copy connected to the radio, and never gives up.
//
// Every second while connected, it reads frequency, mode and power. When
// it isn't connected, it tries again every 3 seconds, for as long as the
// app is open, whatever order things are switched on in. It also tries
// at once when you start typing a callsign, so the contact gets the
// radio's frequency even if the radio was switched on a moment ago.
//
// With Solid Copy's own rigctld (the usual way), it also looks after
// rigctld:
//   - The radio's USB port missing (the TS-590SG's disappears when the
//     radio is off): rigctld is stopped, and the state is "off or
//     unplugged". When the port comes back, rigctld is started again.
//   - rigctld stopped (it can stop if the radio vanishes under it): it's
//     started again.
//   - The radio not answering: rigctld is restarted, in case it's
//     holding on to a port that went away and came back. After 10
//     seconds the first time, then 30, then once a minute, so a radio
//     that's simply off (the KX3, whose port is in its cable and stays
//     when the radio is off) doesn't keep rigctld starting over.
//
// After a minute without an answer, it looks every 15 seconds instead
// of 3: each look at a silent radio ties rigctld up for some 20 seconds
// of trying. Typing a callsign still tries at once.
//
// Each change of state is spoken once (rule 12 of the accessibility
// contract), and trouble only once until the radio connects or its
// port goes, however often Solid Copy tries again. It names the radio: "Kenwood TS-590SG connected, 7.025
// megahertz, CW", "Kenwood TS-590SG off or unplugged", "Elecraft KX3 not
// answering". A change of frequency isn't spoken;
// Command-R says the radio's state when you want it.

import AppKit

@MainActor
final class RadioMonitor {
    static let shared = RadioMonitor()

    // Sent when the state or the reading changes.
    static let didChange = Notification.Name("SolidCopyRadioDidChange")

    enum State: Equatable {
        // No radio in use.
        case none
        // The radio in use needs its model or port chosen.
        case needsSetup
        // The radio's USB port isn't there: the radio is off or unplugged.
        case portMissing
        // rigctld has just been started, and is opening the radio.
        case starting
        // Nothing is listening at the rigctld address.
        case notRunning
        // rigctld is running, but the radio doesn't answer.
        case notAnswering
        case connected(RadioReading)
    }

    private(set) var state: State = .none

    // The latest reading, only while connected.
    // While you tune, the frequency you've tuned to, ahead of the radio
    // confirming it, so the screen and speech keep up with the keys.
    var reading: RadioReading? {
        guard case .connected(var reading) = state else { return nil }
        if let tuneTarget { reading.hertz = tuneTarget }
        return reading
    }

    // The settings on the status line (keyer speed, RIT, AGC, ...), read
    // every 5 seconds while connected. nil until the first read.
    // A change is announced to the window like any other, so the status
    // line updates even when the frequency hasn't changed.
    private(set) var status: RadioStatus? {
        didSet { if status != oldValue { NotificationCenter.default.post(name: Self.didChange, object: nil) } }
    }

    // Tuning: the frequency asked for, and whether a change is on its way
    // to the radio. Keys pressed faster than the radio takes them only
    // move the target; the radio is sent the latest when it's ready.
    private var tuneTarget: Int?
    private var tuneUnderWay = false
    // The same for the RIT or XIT offset (the Offset control).
    private var offsetTarget: Int?
    private var offsetUnderWay = false

    // Power, RF gain and squelch: the Power, RF gain and Squelch controls
    // (Tab from Offset). Like tuning, quick presses only move the target,
    // and the radio is sent the latest when it's ready.
    enum Level: CaseIterable {
        case power, rfGain, squelch, volume

        // What VoiceOver calls its control, and the words for the radio's
        // refusal ("The radio didn't take that power"). Volume has no
        // slider; its keys are in the Radio menu.
        var name: String {
            switch self {
            case .power: "power"
            case .rfGain: "RF gain"
            case .squelch: "squelch"
            case .volume: "volume"
            }
        }
    }
    private var levelTargets: [Level: Double] = [:]
    private var levelsUnderWay: Set<Level> = []
    // Levels the radio has been sent, waiting for it to report them. A
    // radio may answer with its old value for a moment (the KX3), or set
    // its nearest (rounding 0.85 to 0.83, say), so the control keeps
    // showing what you asked for until the radio reports it, or for 3
    // seconds; then the radio's own value shows, and is said if it's not
    // what you asked for.
    private var levelsSettling: [Level: Date] = [:]
    private static let settleSeconds: TimeInterval = 3

    // A level now (watts for power, 0 to 1 for the others), ahead of the
    // radio while it's being changed. nil if the radio doesn't report it,
    // and squelch outside FM, so its control is hidden.
    func level(_ level: Level) -> Double? {
        guard let now = radioLevel(level) else { return nil }
        return levelTargets[level] ?? now
    }

    // A level as the radio last reported it.
    private func radioLevel(_ level: Level) -> Double? {
        guard let reading else { return nil }
        switch level {
        case .power: return reading.watts
        case .rfGain: return status?.rfGain
        case .squelch: return reading.mode.uppercased().contains("FM") ? status?.squelch : nil
        case .volume: return status?.audioGain
        }
    }

    // "5 watts", "80 percent".
    static func spoken(_ level: Level, _ value: Double) -> String {
        if level == .power { return "\(RadioReading.wattsText(value)) \(value == 1 ? "watt" : "watts")" }
        return "\(Int((value * 100).rounded())) percent"
    }

    // Each second: a level the radio now reports as asked is done; one
    // it still doesn't after settleSeconds is shown as the radio has it,
    // and said ("The radio set power to 6 watts").
    private func settleLevels() {
        for (level, since) in levelsSettling {
            guard let target = levelTargets[level] else { levelsSettling[level] = nil; continue }
            let now = radioLevel(level)
            // Close enough: a tenth of a watt, or half a percent.
            let close = now.map { abs($0 - target) < (level == .power ? 0.05 : 0.005) } ?? false
            guard close || Date().timeIntervalSince(since) >= Self.settleSeconds else { continue }
            levelsSettling[level] = nil
            levelTargets[level] = nil
            NotificationCenter.default.post(name: Self.didChange, object: nil)
            if !close, let now {
                Speaker.announce("The radio set \(level.name) to \(Self.spoken(level, now)).")
            }
        }
    }

    // The radio's last frequency and mode on each band this session, for
    // Band Up and Band Down on radios that can't change band themselves.
    var lastOnBand: [String: (hertz: Int, mode: String)] = [:]

    // The RIT or XIT offset in hertz, ahead of the radio while it's being
    // changed. nil if the radio doesn't report one.
    var offsetHertz: Int? {
        guard reading != nil else { return nil }
        return offsetTarget ?? status?.offsetHertz
    }

    // How long the radio may be silent before rigctld is restarted: the
    // first time, the second, and every time after that. (The check in
    // tools/radio-check shortens these.)
    static var restartDelays: [TimeInterval] = [10, 30, 60]
    // How long a connected radio may go without answering before it's
    // called lost. A radio sometimes misses one read and answers the
    // next: restarting VoiceOver with a USB braille display plugged in
    // makes a TS-590SG miss about one second's read (watched 19 November
    // 2026: the USB port stayed, rigctld kept it, one read timed out),
    // and calling that "lost" then "back" is a false alarm. A radio
    // really switched off is still said within a few seconds.
    static var missedAnswerGrace: TimeInterval = 4
    // Without a reading for this long, look every slowEvery seconds.
    static var slowAfter: TimeInterval = 60
    static var slowEvery = 15
    // Where announcements go: VoiceOver (the check listens in here).
    static var say: @MainActor (String) -> Void = Speaker.announce
    // The lost and back tones (the checks listen in here too).
    static var tone: @MainActor (Tone) -> Void = { $0.play() }

    private var settings: RadioSettings?
    private var client: RigctldClient?
    // The network calls wait, so they're made here, one at a time.
    private let queue = DispatchQueue(label: "Solid Copy radio")
    private var polling = false
    private var timer: Timer?
    private var tick = 0
    private var rigctld: Process?
    private var rigctldStarted = Date.distantPast
    private var notAnsweringSince: Date?
    // rigctld starts since the last good reading.
    private(set) var startsWithoutReading = 0
    // Restarts because the radio was silent, since the last good reading.
    private var silentRestarts = 0
    // The last good reading, or when this radio was chosen.
    private var lastReading = Date()
    // The kind of state last announced (see set(_:)).
    private var spokenKind: String?
    // The kind last listed in Window > Activity (see set(_:)).
    private var listedKind: String?

    // Uses this radio (or none): the one in use (Settings.currentRadio).
    // Nothing happens if it's the same as before.
    func use(_ newSettings: RadioSettings?) {
        guard newSettings != settings else { return }
        stopRigctld()
        settings = newSettings
        client = newSettings.map {
            RigctldClient(host: $0.hostAndPort.host, port: $0.hostAndPort.port,
                          dialect: .init(model: $0.model, modelName: $0.modelName))
        }
        notAnsweringSince = nil
        startsWithoutReading = 0
        silentRestarts = 0
        lastReading = Date()
        spokenKind = nil
        rigctldStarted = .distantPast
        status = nil
        tuneTarget = nil
        offsetTarget = nil
        levelTargets = [:]
        levelsSettling = [:]
        lastOnBand = [:]
        timer?.invalidate()
        timer = nil
        guard newSettings != nil else { return set(.none) }
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { RadioMonitor.shared.everySecond() }
        }
        // A little slack lets macOS group wake-ups, which saves power.
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // The first try is a second from now, so "Portable profile" (say)
        // is heard before anything about the radio.
        set(.starting)
    }

    // Radio > Record Radio Log: rigctld writes everything it sends the
    // radio and everything the radio sends back, with times, to
    // ~/Library/Containers/io.github.scott-h5.solidcopy/Data/Library/Logs/
    // rigctld.log, for finding out what's going wrong. Off whenever Solid
    // Copy starts (the log grows fast); turning it on starts a fresh log
    // and restarts rigctld, with the log or without.
    var recordsLog = false {
        didSet {
            guard recordsLog != oldValue else { return }
            if recordsLog { try? FileManager.default.removeItem(at: Self.logURL) }
            reconnect()
        }
    }

    // The pid (process number) of the rigctld Solid Copy started, while
    // it runs. A force-quit (or a crash, or the accessibility audit
    // ending Solid Copy) leaves rigctld running with the radio's port
    // open, and macOS has no way to stop a child when its parent goes.
    // So the next start stops it first.
    static var pidURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Solid Copy rigctld.pid")
    }

    private static func stopLeftoverRigctld() {
        guard let text = try? String(contentsOf: pidURL, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 else { return }
        try? FileManager.default.removeItem(at: pidURL)
        // Only if it's still a Solid Copy rigctld: the number may have
        // been given to another program since.
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return }
        // (macOS gives the real place, so a shortcut such as Homebrew's
        // /opt/homebrew/bin/rigctld is followed before comparing.)
        let running = String(cString: path)
        guard running == RadioModels.rigctld.resolvingSymlinksInPath().path
                || running.hasSuffix(".app/Contents/Helpers/rigctld") else { return }
        kill(pid, SIGTERM)
        // Give it a moment to let go of the port.
        for _ in 0..<20 where kill(pid, 0) == 0 { usleep(50_000) }
    }

    static var logURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/rigctld.log")
    }

    // Where rigctld's messages go: the log, added to, or nowhere.
    private func rigctldOutput() -> FileHandle {
        guard recordsLog else { return FileHandle.nullDevice }
        let url = Self.logURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let file = try? FileHandle(forWritingTo: url) else { return FileHandle.nullDevice }
        file.seekToEndOfFile()
        return file
    }

    // Tries straight away (when you start typing a callsign, say), unless
    // a try is already under way.
    func checkNow() {
        if reading == nil { check() }
    }

    // Radio > Reconnect: starts again from scratch.
    func reconnect() {
        let current = settings
        settings = nil
        use(current)
    }

    // Stops Solid Copy's rigctld, when Solid Copy quits.
    func stop() {
        timer?.invalidate()
        stopRigctld()
    }

    // MARK: - Words

    // The radio's name: "Kenwood TS-590SG".
    var radioName: String { settings?.name ?? "Radio" }

    // For the screen and for Command-R.
    var stateText: String {
        switch state {
        case .none: return ""
        case .needsSetup: return "Choose its model and port in Settings, Radio."
        case .portMissing: return "Off or unplugged. Waiting for it."
        case .starting: return "Connecting…"
        case .notRunning:
            if let settings, !settings.usesOwnRigctld {
                return "Nothing answering at \(settings.address). Is rigctld running? Trying again."
            }
            return "rigctld stopped. Starting it again."
        case .notAnswering: return "Not answering. Trying again."
        case .connected(let reading): return reading.shown
        }
    }

    // Said once when the state changes.
    private var announcement: String? {
        switch state {
        case .none, .starting: return nil
        case .needsSetup: return "\(radioName) not set up."
        case .portMissing: return "\(radioName) off or unplugged."
        case .notRunning: return "\(radioName) connection not running."
        case .notAnswering: return "\(radioName) not answering."
        case .connected(let reading): return "\(radioName) connected, \(reading.spoken)."
        }
    }

    // MARK: - Trying

    private func everySecond() {
        tick += 1
        // Every second while connected (or just started); every 3 seconds
        // otherwise (looking for a port that's gone costs next to
        // nothing); every 15 when the radio has been silent a minute.
        let silent = state == .notAnswering || state == .notRunning
        let every = silent && Date().timeIntervalSince(lastReading) >= Self.slowAfter ? Self.slowEvery : 3
        if reading != nil || state == .starting || tick % every == 0 { check() }
        settleLevels()
    }

    private func check() {
        guard let settings, let client, !polling else { return }
        if settings.usesOwnRigctld {
            guard settings.isComplete else { return set(.needsSetup) }
            guard FileManager.default.fileExists(atPath: settings.port) else {
                stopRigctld()
                return set(.portMissing)
            }
            if rigctld?.isRunning != true {
                // Not more than once every 3 seconds, if it keeps stopping.
                guard Date().timeIntervalSince(rigctldStarted) >= 3 else { return }
                startRigctld(settings)
                // Started twice without a reading: say so (it keeps
                // trying). The model or speed may be wrong.
                return set(rigctld == nil || startsWithoutReading > 2 ? .notRunning : .starting)
            }
            // Give rigctld a moment to open the radio.
            if Date().timeIntervalSince(rigctldStarted) < 1 { return }
        }
        polling = true
        // The status line's settings every 5 seconds (and at once, after
        // connecting). They change less, and each is a question to the
        // radio, so the serial port is kept quiet.
        // (RF gain and squelch are status settings: while one is waiting
        // for the radio to report it, they're read every second.)
        let settling = levelsSettling.keys.contains { $0 != .power }
        let wantStatus = status == nil || tick % 5 == 0 || settling
        queue.async {
            let result = Result { try client.reading() }
            let status = wantStatus ? (try? result.get()).flatMap { try? client.status(mode: $0.mode) } : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let status, client === RadioMonitor.shared.client { RadioMonitor.shared.status = status }
                    RadioMonitor.shared.finished(result, from: client)
                }
            }
        }
    }

    // MARK: - Changing the radio

    // Sends a change ("F 7025300", "M CW 500", "L KEYSPD 22"), then reads
    // the radio back, so what's shown and said is what the radio actually
    // did (it may round a filter width, say). `done` gets the new reading,
    // or nil if the radio didn't take it or isn't connected.
    func change(_ command: String, done: @escaping @MainActor (RadioReading?) -> Void) {
        change([command]) { reading, _ in done(reading) }
    }

    // The same, trying each command until the radio takes one (see
    // RigctldClient.setFirst). `done` also gets the one taken. Anything
    // but a frequency or mode also reads the status line's settings
    // again, so they're up to date when `done` says what changed.
    func change(_ commands: [String], done: @escaping @MainActor (RadioReading?, String?) -> Void) {
        guard let client, case .connected = state else { return done(nil, nil) }
        let wantsStatus = !commands.allSatisfy { $0.hasPrefix("F ") || $0.hasPrefix("M ") }
        queue.async {
            let taken = try? client.setFirst(of: commands)
            let reading = taken != nil ? try? client.reading() : nil
            let status = wantsStatus ? reading.flatMap { try? client.status(mode: $0.mode) } : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let monitor = RadioMonitor.shared
                    guard client === monitor.client else { return done(nil, nil) }
                    if let status { monitor.status = status }
                    if let reading { monitor.set(.connected(reading)) }
                    done(reading, reading == nil ? nil : taken)
                }
            }
        }
    }

    // Tunes to a frequency, in hertz. The screen follows at once.
    func tune(toHertz hertz: Int) {
        guard reading != nil, hertz > 0 else { return }
        tuneTarget = hertz
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        if !tuneUnderWay { sendTune() }
    }

    private func sendTune() {
        guard let target = tuneTarget else { return }
        tuneUnderWay = true
        change("F \(target)") { reading in
            let monitor = RadioMonitor.shared
            monitor.tuneUnderWay = false
            if reading == nil {
                // Not taken (out of the radio's range, say): show what the
                // radio is really on.
                monitor.tuneTarget = nil
                NotificationCenter.default.post(name: Self.didChange, object: nil)
                Speaker.announce("The radio didn't take that frequency.")
            } else if monitor.tuneTarget != target {
                // More keys pressed meanwhile: send the latest.
                monitor.sendTune()
            } else {
                monitor.tuneTarget = nil
            }
        }
    }

    // Sets the RIT (or XIT) offset, in hertz. Like tuning, the screen
    // follows at once and quick changes are sent as one.
    func setOffset(toHertz hertz: Int) {
        guard reading != nil, status?.offsetHertz != nil else { return }
        offsetTarget = hertz
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        if !offsetUnderWay { sendOffset() }
    }

    private func sendOffset() {
        guard let target = offsetTarget, let command = status?.offsetCommand else { return }
        offsetUnderWay = true
        change("\(command) \(target)") { reading in
            let monitor = RadioMonitor.shared
            monitor.offsetUnderWay = false
            if reading == nil {
                monitor.offsetTarget = nil
                NotificationCenter.default.post(name: Self.didChange, object: nil)
                Speaker.announce("The radio didn't take that offset.")
            } else if monitor.offsetTarget != target {
                monitor.sendOffset()
            } else {
                monitor.offsetTarget = nil
            }
        }
    }

    // Changes a level by a step (watts, or a fraction for RF gain and
    // squelch), within what the radio has: power from 0.1 watt to the
    // radio's most; the others from 0 to 1.
    func changeLevel(_ level: Level, by step: Double) {
        guard let current = self.level(level) else {
            return Speaker.announce(reading == nil ? notConnectedText : "\(radioName) doesn't report its \(level.name).")
        }
        let top = level == .power ? reading?.maxWatts ?? 100 : 1
        let bottom = level == .power ? 0.1 : 0
        // Rounded to the step's size, so 5 watts plus 1 is 6, not 6.000001.
        let target = ((min(max(current + step, bottom), top)) * 100).rounded() / 100
        guard target != current else {
            NSSound.beep()
            return Speaker.announce(target == top ? "Most \(level.name)." : "Least \(level.name).")
        }
        levelTargets[level] = target
        levelsSettling[level] = nil
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        if !levelsUnderWay.contains(level) { sendLevel(level) }
    }

    private func sendLevel(_ level: Level) {
        guard let target = levelTargets[level] else { return }
        levelsUnderWay.insert(level)
        let command: String
        switch level {
        case .power: command = "POWER \(target)"
        case .rfGain: command = "L RF \(target)"
        case .squelch: command = "L SQL \(target)"
        case .volume: command = "L AF \(target)"
        }
        change(command) { reading in
            let monitor = RadioMonitor.shared
            monitor.levelsUnderWay.remove(level)
            if reading == nil {
                monitor.levelTargets[level] = nil
                NotificationCenter.default.post(name: Self.didChange, object: nil)
                Speaker.announce("The radio didn't take that \(level.name).")
            } else if monitor.levelTargets[level] != target {
                monitor.sendLevel(level)
            } else {
                // Sent: wait for the radio to report it (settleLevels).
                monitor.levelsSettling[level] = Date()
                monitor.settleLevels()
            }
        }
    }

    // Radio > Signal Strength (Option-Command-S): the S-meter, said once,
    // "S 7" or "S 9 plus 10 dB". Always said in full: you asked.
    func sayStrength() {
        guard let client, reading != nil else { return Speaker.announce(notConnectedText) }
        queue.async {
            let decibels = try? client.strength()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let decibels else {
                        return Speaker.announce("\(RadioMonitor.shared.radioName) doesn't report its signal strength.")
                    }
                    Speaker.announce(Self.sMeterText(decibels) + ".")
                }
            }
        }
    }

    // hamlib's decibels above S9 in S units: -54 is S0, 0 is S9, each S
    // unit 6 dB. "S 7", "S 9", "S 9 plus 10 dB".
    static func sMeterText(_ decibels: Int) -> String {
        if decibels > 0 { return "S 9 plus \(decibels) dB" }
        return "S \(max(0, 9 + Int((Double(decibels) / 6).rounded())))"
    }

    private func finished(_ result: Result<RadioReading, Error>, from client: RigctldClient) {
        polling = false
        // From a radio that's since been changed in Settings: ignore it.
        guard client === self.client, let settings else { return }
        switch result {
        case .success(let reading):
            notAnsweringSince = nil
            startsWithoutReading = 0
            silentRestarts = 0
            lastReading = Date()
            set(.connected(reading))
        case .failure(let error):
            let failure = error as? RigctldClient.Failure ?? .notAnswering
            // Just started: rigctld can take a few seconds to open the
            // radio. Not worth announcing yet.
            if settings.usesOwnRigctld, Date().timeIntervalSince(rigctldStarted) < 5 {
                return set(.starting)
            }
            if failure == .notAnswering || failure == .rejected {
                let since = notAnsweringSince ?? Date()
                notAnsweringSince = since
                let delays = Self.restartDelays
                if settings.usesOwnRigctld,
                   Date().timeIntervalSince(since) >= delays[min(silentRestarts, delays.count - 1)] {
                    // Next try starts a fresh rigctld.
                    stopRigctld()
                    notAnsweringSince = nil
                    silentRestarts += 1
                }
                // Still connected, as far as anyone hears, for a missed
                // read or two (missedAnswerGrace).
                if case .connected = state, Date().timeIntervalSince(since) < Self.missedAnswerGrace { return }
                set(.notAnswering)
            } else {
                notAnsweringSince = nil
                set(.notRunning)
            }
        }
    }

    // Speaks a state when its kind differs from the last one spoken.
    // "Starting" is never spoken, so restarting rigctld for a silent radio
    // doesn't bring "not answering" round again.
    private func set(_ newState: State) {
        guard newState != state else { return }
        state = newState
        if case .connected(let reading) = newState, let band = reading.band {
            lastOnBand[band] = (reading.hertz, reading.mode)
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        let kind = Self.kind(newState)
        // Window > Activity: each change of kind (connected, or trouble),
        // not each reading or retry. "Starting" and "No Radio" aren't listed.
        if newState != .starting, newState != .none, kind != listedKind, let text = announcement {
            listedKind = kind
            Activity.shared.record("Radio", radioName, ok: kind == "connected", latest: text)
        }
        guard newState != .starting, kind != spokenKind, let announcement else { return }
        // Lost (last heard connected, now not, other than choosing No
        // Radio) and back (connected after something else was heard) have
        // their own tones, so they stand out from every other sound
        // (Tone.swift). Settings > Speech > Radio lost or back: the tone
        // and the words, or the tone alone. Both go by what was last
        // *heard*, not the state just before: the radio often passes
        // through "starting" (never spoken) on its way down, when rigctld
        // stops first, and that used to swallow the lost tone.
        let heardConnected = spokenKind == "connected"
        let lost = heardConnected && newState != .none
        let back = kind == "connected" && spokenKind != nil && !heardConnected
        spokenKind = kind
        if lost || back {
            Self.tone(lost ? .radioLost : .radioBack)
            if Speaker.level(for: .connection) == .sound { return }
        }
        Self.say(announcement)
    }

    // States that differ only in the reading are the same kind: a new
    // frequency isn't announced. "Not running" and "not answering" are one
    // kind, trouble: a silent radio swaps between them as rigctld gives up
    // on it and is started again. (The screen and Command-R tell them
    // apart.)
    private static func kind(_ state: State) -> String {
        switch state {
        case .connected: return "connected"
        case .notRunning, .notAnswering: return "trouble"
        default: return "\(state)"
        }
    }

    // MARK: - Solid Copy's own rigctld

    private func startRigctld(_ settings: RadioSettings) {
        Self.stopLeftoverRigctld()
        let process = Process()
        process.executableURL = RadioModels.rigctld
        // -T 127.0.0.1: listen on this Mac only, not the network.
        process.arguments = ["-m", "\(settings.model)", "-r", settings.port, "-s", "\(settings.baud)",
                             "-T", "127.0.0.1", "-t", "\(RadioSettings.ownPort)"]
            // Recording: everything (-vvvvv), each line timed (-Z).
            + (recordsLog ? ["-vvvvv", "-Z"] : [])
        process.standardOutput = FileHandle.nullDevice
        process.standardError = rigctldOutput()
        rigctldStarted = Date()
        startsWithoutReading += 1
        do {
            try process.run()
            rigctld = process
            try? "\(process.processIdentifier)".write(to: Self.pidURL, atomically: true, encoding: .utf8)
        } catch {
            rigctld = nil
        }
    }

    private func stopRigctld() {
        if let rigctld, rigctld.isRunning { rigctld.terminate() }
        if rigctld != nil { try? FileManager.default.removeItem(at: Self.pidURL) }
        rigctld = nil
        // The connection was to that rigctld: drop it (on the queue, so it
        // can't happen in the middle of a reading).
        if let client { queue.async { client.disconnect() } }
    }
}
