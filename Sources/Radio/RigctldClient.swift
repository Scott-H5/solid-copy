// RigctldClient.swift
//
// Talks to rigctld, hamlib's radio-control program, over a network
// connection (usually to this Mac, 127.0.0.1, port 4532).
//
// rigctld takes one-line text commands. Solid Copy uses the "extended"
// form, with a + in front, because every reply then ends with a line
// "RPRT n" (0 means it worked), so it's always clear where a reply ends:
//
//   +f                ->  get_freq:
//                         Frequency: 7025241
//                         RPRT 0
//   +l RFPOWER        ->  get_level: RFPOWER
//                         0.05
//                         RPRT 0
//
// The calls here wait for the network, so they're made from a background
// queue (RadioMonitor does that), never the main thread. Every wait has a
// time limit, so a silent radio or a stuck rigctld can't hang anything.

import Foundation

// "@unchecked Sendable": Swift can't see that this is only ever used from
// RadioMonitor's one background queue (one call at a time), so it's told.
final class RigctldClient: RadioLink, @unchecked Sendable {
    // The failures are shared with the built-in driver (RadioLink.swift).
    typealias Failure = RadioFailure

    let host: String
    let port: UInt16
    // Radios where hamlib falls short for a few settings, which are read
    // and set with the radio's own commands instead (see "Elecraft
    // radios" and "TS-590S and TS-590SG" below).
    enum Dialect {
        case standard
        case elecraft   // K3, KX3, KX2...
        case ts590      // Kenwood TS-590S and TS-590SG

        // From hamlib's model number and name.
        init(model: Int, modelName: String) {
            if modelName.hasPrefix("Elecraft") {
                self = .elecraft
            } else if [2031, 2037].contains(model) {
                self = .ts590
            } else {
                self = .standard
            }
        }
    }
    let dialect: Dialect
    private let link: HamlibSocket
    // Status questions this radio can't answer (see status()).
    private var unsupported: Set<String> = []
    // The radio's most power, in watts, on each band: hamlib asks the
    // radio where it can (15 W for the KX3 on 20 meters, less higher up),
    // and knows it for the rest (100 W for the TS-590SG). Asked once a band.
    private var maxWattsByBand: [String: Double] = [:]

    init(host: String, port: UInt16, dialect: Dialect = .standard) {
        self.host = host
        self.port = port
        self.dialect = dialect
        // rigctld waits for the radio itself, with retries, before it
        // answers, so the wait is generous.
        link = HamlibSocket(host: host, port: port, replySeconds: 8)
    }

    func disconnect() { link.disconnect() }

    // Reads frequency, mode and power. Power is optional: some radios
    // can't report it, and that's not a failure.
    func reading() throws -> RadioReading {
        if !link.isOpen { try link.connect() }
        guard let hertz = try values("+f").first.flatMap(Double.init), hertz > 0 else {
            throw Failure.notAnswering
        }
        let modeReply = try values("+m")
        guard let mode = modeReply.first, !mode.isEmpty else { throw Failure.notAnswering }
        // The mode's reply also gives the filter width ("Passband: 500").
        let passband = modeReply.count > 1 ? Int(modeReply[1]).flatMap { $0 > 0 ? $0 : nil } : nil
        var watts: Double?
        // The power setting comes as a fraction of the radio's maximum;
        // hamlib knows each radio's maximum and converts it to milliwatts.
        if let level = try? values("+l RFPOWER").first, let fraction = Double(level), fraction > 0,
           let milliwatts = try? values("+\\power2mW \(level) \(Int(hertz)) \(mode)").first.flatMap(Double.init) {
            watts = milliwatts / 1_000
        }
        let band = Bands.name(forHertz: Int(hertz)) ?? ""
        if watts != nil, maxWattsByBand[band] == nil {
            maxWattsByBand[band] = try? maxWatts(hertz: Int(hertz), mode: mode)
        }
        return RadioReading(hertz: Int(hertz), mode: mode, watts: watts, passband: passband,
                            maxWatts: watts == nil ? nil : maxWattsByBand[band])
    }

    // Changes something on the radio: "F 7025300" (frequency in hertz),
    // "M CW 500" (mode and filter width), "L KEYSPD 22" (keyer speed).
    // Throws if the radio doesn't take it.
    func set(_ command: String) throws {
        if !link.isOpen { try link.connect() }
        // "W 100": a filter width for the mode in use. rigctld has no width-only
        // command, so the mode is read and sent with it (as "M").
        if command.hasPrefix("W "), let width = Int(command.dropFirst(2)) {
            guard let mode = try values("+m").first, !mode.isEmpty else { throw Failure.rejected }
            _ = try values("+M \(mode) \(width)")
            return
        }
        // "POWER 5": watts, as the fraction of the radio's most power on
        // this band that hamlib's RFPOWER level takes. Worked out here, not
        // with hamlib's mW2power: for the KX3 that assumes 10 watts at most
        // when the radio's is 15, so 5 watts became 7.5, and anything over
        // 10 was an error that made rigctld drop the connection (found
        // with Scott's KX3's radio log, 15 November 2026).
        if command.hasPrefix("POWER "), let watts = Double(command.dropFirst(6)) {
            guard let hertz = try values("+f").first.flatMap(Double.init), let mode = try values("+m").first else {
                throw Failure.rejected
            }
            let most = try maxWatts(hertz: Int(hertz), mode: mode)
            let fraction = min(max(watts / most, 0), 1)
            _ = try values("+L RFPOWER " + String(format: "%.4f", fraction))
            return
        }
        switch dialect {
        case .standard: _ = try values("+" + command)
        case .elecraft: _ = try values("+" + Self.elecraftCommand(for: command))
        case .ts590: _ = try values("+" + Self.ts590Command(for: command))
        }
    }

    // MARK: - TS-590S and TS-590SG
    //
    // hamlib's AGC command for these never reaches the radio, and its AGC
    // reading is only what it was last told to set (found 15 November
    // 2026, asking Scott's TS-590SG directly). So AGC uses Kenwood's own
    // GC command, sent with "W" like the Elecraft ones below:
    //   GC0;   off
    //   GC1;   slow
    //   GC2;   fast
    //   GC3;   on again, at the last speed. The radio refuses to go
    //          straight from off to a speed ("?;"), so a speed is sent as
    //          GC3; then the speed.
    // There's no medium: the TS-590SG has slow and fast (each with its own
    // time constant, set in the radio's menu).
    private static func ts590Command(for command: String) throws -> String {
        guard command.hasPrefix("L AGC ") else { return command }
        // hamlib's numbers: 0 off, 2 fast, 3 slow.
        switch Int(command.dropFirst(6)) {
        case 0: return "W GC0;ID; ;"
        case 2: return "W GC3;GC2;ID; ;"
        case 3: return "W GC3;GC1;ID; ;"
        default: throw Failure.rejected
        }
    }

    // MARK: - Elecraft radios
    //
    // Through hamlib, the KX3 can't read or set its noise blanker or AGC,
    // reads its noise reduction *level* (never 0, so it always seemed on)
    // rather than whether it's on. Its own commands do these in about 30
    // ms (the preamp too, for one way of doing all four). rigctld
    // passes them on with "W": "W NR; ;" sends NR; and reads up to the ;
    // ("NR0;"). A change must be followed by a question, or the KX3
    // ignores it (found with Radio > Record Radio Log, 15 November 2026),
    // so "W PA1;ID; ;" sends PA1; then ID; and reads the answer to ID.
    // From Elecraft's KX3 Programmer's Reference, tried on Scott's KX3:
    //   PA0; PA1;    preamp off, on
    //   NB0; NB1;    noise blanker off, on (read back as "NB00;", "NB10;":
    //                the first digit on or off)
    //   GT002; GT004;  AGC fast, slow (read back as "GT0021;", "GT0041;")
    //   NR0; NR1;    noise reduction off, on; reads, but the KX3 ignores
    //                NR1 from the cable, so Solid Copy says it didn't
    //                change
    //   SB0; SB1;    dual watch off, on

    // hamlib's command for a setting, or Elecraft's own. Throws `rejected`
    // for a setting the radio hasn't got (AGC medium or off).
    private static func elecraftCommand(for command: String) throws -> String {
        let words = command.split(separator: " ").map(String.init)
        guard words.count == 3, let value = Double(words[2]) else { return command }
        let on = value > 0 ? 1 : 0
        switch (words[0], words[1]) {
        case ("L", "PREAMP"): return "W PA\(on);ID; ;"
        case ("U", "NR"): return "W NR\(on);ID; ;"
        case ("U", "NB"): return "W NB\(on);ID; ;"
        // The KX3's dual watch is its "sub receiver" switch.
        case ("U", "DUAL_WATCH"): return "W SB\(on);ID; ;"
        case ("L", "NR"): throw Failure.rejected   // "U NR" does it
        case ("L", "AGC"):
            // hamlib's numbers: 2 fast, 3 slow.
            switch Int(value) {
            case 2: return "W GT002;ID; ;"
            case 3: return "W GT004;ID; ;"
            default: throw Failure.rejected
            }
        default: return command
        }
    }

    // Tries each command in turn until the radio takes one, and returns
    // it. For settings radios do differently: a preamp is 12 dB on one
    // and 10 on another, and hamlib refuses a value the radio hasn't got
    // (at once, without asking the radio). Throws if none is taken.
    func setFirst(of commands: [String]) throws -> String {
        for command in commands {
            do {
                try set(command)
                return command
            } catch Failure.rejected {
                continue
            }
        }
        throw Failure.rejected
    }

    // The slower-changing settings shown on the status line: VFO, keyer
    // speed, RIT, XIT, split, AGC, preamp, attenuator, noise blanker,
    // noise reduction and audio peak filter. Each is asked for
    // separately; one the radio (or hamlib) doesn't have is remembered
    // and not asked for again, so a radio is only asked what it can say.
    // `mode` is the radio's mode now: the audio peak filter is only asked
    // about in CW, as it's a CW setting and the KX3 doesn't answer the
    // question in other modes (hamlib then retries for 6 seconds).
    func status(mode: String) throws -> RadioStatus {
        if !link.isOpen { try link.connect() }
        var status = RadioStatus()
        func ask(_ command: String) throws -> [String]? {
            guard !unsupported.contains(command) else { return nil }
            do {
                return try values(command)
            } catch Failure.rejected {
                unsupported.insert(command)
                return nil
            }
        }
        func on(_ command: String) throws -> Bool? { try ask(command)?.first.map { $0 != "0" } }
        status.vfo = try ask("+v")?.first
        status.keyerWPM = try ask("+l KEYSPD")?.first.flatMap(Int.init)
        status.ritOn = try on("+u RIT")
        status.xitOn = try on("+u XIT")
        status.ritHertz = try ask("+j")?.first.flatMap(Int.init)
        status.xitHertz = try ask("+z")?.first.flatMap(Int.init)
        status.split = try on("+s")
        status.attenuatorDB = try ask("+l ATT")?.first.flatMap(Int.init)
        if mode.uppercased().hasPrefix("CW") { status.peakFilter = try on("+u APF") }
        // RF gain, squelch and audio volume: fractions from 0 to 1. Squelch
        // is only asked about in FM, where it's used (and shown).
        status.rfGain = try ask("+l RF")?.first.flatMap(Double.init)
        status.audioGain = try ask("+l AF")?.first.flatMap(Double.init)
        if mode.uppercased().contains("FM") { status.squelch = try ask("+l SQL")?.first.flatMap(Double.init) }
        // The radio's own reading: "NR0;" -> "0", the digits after the
        // command's name.
        func own(_ name: String) throws -> String? {
            try ask("+W \(name); ;")?.first.map { String($0.dropFirst(name.count).prefix { $0 != ";" }) }
        }
        if dialect == .elecraft {
            // A preamp that's just on or off is 1 (hamlib does the same).
            status.preampDB = try own("PA").map { $0 == "0" ? 0 : 1 }
            status.noiseReduction = try own("NR").map { $0 != "0" }
            status.noiseBlanker = try own("NB").map { $0.first != "0" }
            status.agc = try own("GT").flatMap { Int($0.prefix(3)) }.map { $0 == 2 ? 2 : 3 }
            status.dualWatch = try own("SB").map { $0 != "0" }
            return status
        }
        if dialect == .ts590 {
            // GC0, 1, 2 (off, slow, fast) in hamlib's numbers: 0, 3, 2.
            status.agc = try own("GC").flatMap(Int.init).flatMap { [0: 0, 1: 3, 2: 2][$0] }
        } else {
            status.agc = try ask("+l AGC")?.first.flatMap(Int.init)
        }
        status.preampDB = try ask("+l PREAMP")?.first.flatMap(Int.init)
        status.dualWatch = try on("+u DUAL_WATCH")
        status.noiseBlanker = try on("+u NB")
        // Noise reduction is a switch on most radios; on some hamlib only
        // offers its level, where more than 0 means on.
        status.noiseReduction = try on("+u NR")
        if status.noiseReduction == nil {
            status.noiseReduction = try ask("+l NR")?.first.flatMap(Double.init).map { $0 > 0 }
        }
        return status
    }

    // The most power the radio has here, in watts: hamlib's power2mW of
    // the whole RFPOWER range (1).
    private func maxWatts(hertz: Int, mode: String) throws -> Double {
        guard let milliwatts = try values("+\\power2mW 1 \(hertz) \(mode)").first.flatMap(Double.init),
              milliwatts > 0 else { throw Failure.rejected }
        return milliwatts / 1_000
    }

    // The S-meter: decibels above S9 (hamlib's STRENGTH; -54 is S0, 0 is
    // S9, and each S unit is 6 dB). Asked only when you ask.
    func strength() throws -> Int {
        if !link.isOpen { try link.connect() }
        guard let value = try values("+l STRENGTH").first.flatMap(Int.init) else { throw Failure.rejected }
        return value
    }

    // Sends one command and returns the values in its reply, in order:
    // "Frequency: 7025241" gives "7025241"; a bare "0.05" gives "0.05".
    // A reply of "RPRT" with an error number means the radio didn't do it.
    // The conversation itself (HamlibSocket.swift), shared with the
    // rotor's rotctld (RotctldClient.swift).
    private func values(_ command: String) throws -> [String] { try link.values(command) }
}
