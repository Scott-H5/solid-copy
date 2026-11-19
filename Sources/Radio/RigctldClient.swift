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
final class RigctldClient: @unchecked Sendable {
    enum Failure: Error, Equatable {
        // Nothing is listening at the address: rigctld isn't running.
        case notRunning
        // rigctld is there, but the radio didn't answer (it's off, or the
        // speed or model is wrong).
        case notAnswering
        // The radio (or hamlib) said no: it can't do that, or not now.
        case rejected
    }

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
    private var socket: Int32 = -1
    private var buffer: [UInt8] = []
    // Status questions this radio can't answer (see status()).
    private var unsupported: Set<String> = []
    // The radio's most power, in watts, on each band: hamlib asks the
    // radio where it can (15 W for the KX3 on 20 meters, less higher up),
    // and knows it for the rest (100 W for the TS-590SG). Asked once a band.
    private var maxWattsByBand: [String: Double] = [:]

    // How long to wait for rigctld. It waits for the radio itself, with
    // retries, before it answers, so this is generous.
    private static let replySeconds = 8
    private static let connectMilliseconds: Int32 = 2_000

    init(host: String, port: UInt16, dialect: Dialect = .standard) {
        self.host = host
        self.port = port
        self.dialect = dialect
    }

    deinit { disconnect() }

    func disconnect() {
        if socket >= 0 { Darwin.close(socket) }
        socket = -1
        buffer.removeAll()
    }

    // Reads frequency, mode and power. Power is optional: some radios
    // can't report it, and that's not a failure.
    func reading() throws -> RadioReading {
        if socket < 0 { try connect() }
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
        if socket < 0 { try connect() }
        // "POWER 5": watts, as the fraction of the radio's most power on
        // this band that hamlib's RFPOWER level takes. Worked out here, not
        // with hamlib's mW2power: for the KX3 that assumes 10 watts at most
        // when the radio's is 15, so 5 watts became 7.5, and anything over
        // 10 was an error that made rigctld drop the connection (found
        // with the author's KX3's radio log, 15 November 2026).
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
    // 2026, asking the author's TS-590SG directly). So AGC uses Kenwood's own
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
    // From Elecraft's KX3 Programmer's Reference, tried on the author's KX3:
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
        if socket < 0 { try connect() }
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
        if socket < 0 { try connect() }
        guard let value = try values("+l STRENGTH").first.flatMap(Int.init) else { throw Failure.rejected }
        return value
    }

    // Sends one command and returns the values in its reply, in order:
    // "Frequency: 7025241" gives "7025241"; a bare "0.05" gives "0.05".
    // A reply of "RPRT" with an error number means the radio didn't do it.
    // rigctld closes a connection after some hamlib errors (an "RPRT 10"
    // from a value out of range, say) while carrying on itself, so if an
    // open connection turns out to be closed, it's opened again and the
    // command sent once more, rather than the radio seeming to vanish.
    private func values(_ command: String) throws -> [String] {
        let wasOpen = socket >= 0
        do {
            return try valuesOnce(command)
        } catch Failure.notRunning where wasOpen {
            disconnect()
            try connect()
            return try valuesOnce(command)
        }
    }

    private func valuesOnce(_ command: String) throws -> [String] {
        try send(command + "\n")
        var lines: [String] = []
        // A raw reply ("W") ends in a 0 byte, with RPRT straight after it
        // on the same line ("Reply: NR0;\0RPRT 0"), so 0 bytes split lines
        // too.
        var pending: [String] = []
        while true {
            if pending.isEmpty {
                pending = try readLine().split(separator: "\u{0}", omittingEmptySubsequences: false).map(String.init)
            }
            let line = pending.removeFirst()
            if line.hasPrefix("RPRT") {
                // hamlib's error numbers: -5 is a time-out and -6 an
                // input/output error (the radio didn't answer); anything
                // else means it answered "no".
                guard line == "RPRT 0" else {
                    throw ["RPRT -5", "RPRT -6"].contains(line) ? Failure.notAnswering : Failure.rejected
                }
                // The first line repeats the command ("get_freq:").
                return Array(lines.dropFirst())
            }
            lines.append(line.range(of: ": ").map { String(line[$0.upperBound...]) } ?? line)
            // A real reply is a few lines. Anything longer isn't rigctld.
            if lines.count > 20 { disconnect(); throw Failure.notAnswering }
        }
    }

    // MARK: - The connection

    private func connect() throws {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &list) == 0 else { throw Failure.notRunning }
        defer { freeaddrinfo(list) }
        var next = list
        while let address = next?.pointee {
            next = address.ai_next
            let candidate = Darwin.socket(address.ai_family, address.ai_socktype, address.ai_protocol)
            guard candidate >= 0 else { continue }
            if Self.connect(candidate, address) {
                socket = candidate
                return
            }
            Darwin.close(candidate)
        }
        throw Failure.notRunning
    }

    // Connects with a time limit. (A plain connect to a far-off address
    // that doesn't answer can wait over a minute.) Then sets the time
    // limits for sending and receiving.
    private static func connect(_ socket: Int32, _ address: addrinfo) -> Bool {
        let flags = fcntl(socket, F_GETFL)
        _ = fcntl(socket, F_SETFL, flags | O_NONBLOCK)
        if Darwin.connect(socket, address.ai_addr, address.ai_addrlen) != 0 {
            guard errno == EINPROGRESS else { return false }
            var waiting = pollfd(fd: socket, events: Int16(POLLOUT), revents: 0)
            var problem: Int32 = 0
            var size = socklen_t(MemoryLayout<Int32>.size)
            guard poll(&waiting, 1, connectMilliseconds) == 1,
                  getsockopt(socket, SOL_SOCKET, SO_ERROR, &problem, &size) == 0, problem == 0 else { return false }
        }
        _ = fcntl(socket, F_SETFL, flags)
        var limit = timeval(tv_sec: replySeconds, tv_usec: 0)
        let limitSize = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &limit, limitSize)
        setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, &limit, limitSize)
        // If rigctld goes away mid-send, report an error rather than
        // ending Solid Copy (which is what a "broken pipe" does by default).
        var on: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        return true
    }

    private func send(_ text: String) throws {
        let bytes = Array(text.utf8)
        var sent = 0
        while sent < bytes.count {
            let count = bytes[sent...].withUnsafeBytes { Darwin.send(socket, $0.baseAddress, $0.count, 0) }
            guard count > 0 else { disconnect(); throw Failure.notRunning }
            sent += count
        }
    }

    // One line of the reply, without its line ending. Running out of time
    // means the radio didn't answer; the connection closing means rigctld
    // stopped. Either way the connection is dropped, so a late reply
    // can't be mistaken for the answer to the next command.
    private func readLine() throws -> String {
        while true {
            if let end = buffer.firstIndex(of: 10) {
                let line = String(decoding: buffer[..<end], as: UTF8.self)
                buffer.removeSubrange(...end)
                return line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard buffer.count < 4_096 else { disconnect(); throw Failure.notAnswering }
            var chunk = [UInt8](repeating: 0, count: 1_024)
            let count = chunk.withUnsafeMutableBytes { recv(socket, $0.baseAddress, $0.count, 0) }
            if count > 0 {
                buffer += chunk[..<count]
            } else {
                let timedOut = count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)
                disconnect()
                throw timedOut ? Failure.notAnswering : Failure.notRunning
            }
        }
    }
}
