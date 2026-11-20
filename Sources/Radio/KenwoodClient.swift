// KenwoodClient.swift
//
// The built-in driver: talks to a Kenwood or Elecraft radio over its own
// USB serial port, with the words KenwoodCAT.swift makes. It stands where
// RigctldClient stands (RadioLink), so the monitor and the controls don't
// know which one is in use.
//
// Like RigctldClient, every call waits for the radio, so RadioMonitor makes
// them on its background queue, one at a time, never on the main thread.
// Every wait has a time limit, so a silent radio can't hang anything.

import Foundation

// "@unchecked Sendable": only ever used from RadioMonitor's one background
// queue, one call at a time (as RigctldClient).
final class KenwoodClient: RadioLink, @unchecked Sendable {
    private let path: String
    private let baud: Int
    private let radio: KenwoodRadio
    // Opened on the first call, and closed when the port goes or Solid Copy
    // is told to disconnect (RadioMonitor does that when the port is gone).
    private var port: SerialPort?
    // Questions the radio has refused (say, the TS-590 has no RIT offset
    // question), so they're not asked again (as RigctldClient does).
    private var unsupported: Set<String> = []

    // How long one answer may take. A radio answers in a few milliseconds,
    // so a second is generous; a silent radio costs one second per question
    // and no more, since the first silence ends the call.
    private static let replySeconds: TimeInterval = 1

    init(path: String, baud: Int, radio: KenwoodRadio) {
        self.path = path
        self.baud = baud
        self.radio = radio
    }

    deinit { disconnect() }

    func disconnect() {
        port?.close()
        port = nil
    }

    // Frequency, mode, filter width and power. The frequency is of the VFO
    // that receives (FR says which), as the radio shows it.
    func reading() throws -> RadioReading {
        let vfoB = (try? ask("FR")) == "1"   // FR refused: the VFO A
        guard let hertz = KenwoodCAT.hertz(try ask(vfoB ? "FB" : "FA")) else { throw RadioFailure.notAnswering }
        let modeBody = try ask("MD")
        guard let mode = KenwoodCAT.mode(modeBody, radio) else { throw RadioFailure.notAnswering }
        // The filter width and power are optional: a radio that doesn't say
        // them is not a failure, so an error here is simply no answer.
        let passband = (try? ask(radio.filterCode)).flatMap(KenwoodCAT.passband)
        let watts = (try? ask("PC")).flatMap(KenwoodCAT.watts)
        return RadioReading(hertz: hertz, mode: mode, watts: watts, passband: passband,
                            maxWatts: watts == nil ? nil : radio.maxWatts)
    }

    // Tries each command in turn until the radio takes one (see RadioLink).
    // A command the radio hasn't got is rejected before it's sent, so the
    // next one is tried at once.
    func setFirst(of commands: [String]) throws -> String {
        for command in commands {
            do {
                // "F" tunes the VFO that receives, so ask which it is first.
                let vfoB = (try? ask("FR")) == "1"
                let bodies = try KenwoodCAT.commands(for: command, radio: radio, receiveVFOB: vfoB)
                try change(bodies)
                return command
            } catch RadioFailure.rejected {
                continue
            }
        }
        throw RadioFailure.rejected
    }

    // The S-meter is not built in yet: the Kenwood S-meter's scale isn't
    // checked against a radio, and a guessed one would show wrong signal
    // reports. Said as "doesn't report its signal strength" until it is.
    func strength() throws -> Int {
        throw RadioFailure.rejected
    }

    // The status line's settings. Each is asked for separately; one the
    // radio hasn't got is remembered and not asked for again. `mode` is the
    // radio's mode now: the audio peak filter is only asked about in CW, and
    // squelch only in FM, as RigctldClient does.
    func status(mode: String) throws -> RadioStatus {
        var status = RadioStatus()
        func value(_ code: String) throws -> String? {
            guard !unsupported.contains(code) else { return nil }
            do {
                return try ask(code)
            } catch RadioFailure.rejected {
                unsupported.insert(code)
                return nil
            }
        }
        let receive = try value("FR")
        status.vfo = receive.map { $0 == "1" ? "VFOB" : "VFOA" }
        status.keyerWPM = try value("KS").flatMap { Int($0) }
        status.ritOn = try value("RT").map(KenwoodCAT.isOn)
        status.xitOn = try value("XT").map(KenwoodCAT.isOn)
        // RIT and XIT share one offset on these radios (RO).
        let offset = try value("RO").flatMap(KenwoodCAT.offset)
        status.ritHertz = offset
        status.xitHertz = offset
        // Split: the transmit VFO (FT) isn't the receive VFO.
        if let transmit = try value("FT"), let receive { status.split = transmit != receive }
        status.attenuatorDB = try value("RA").map { KenwoodCAT.isOn($0) ? radio.attenuatorDB : 0 }
        status.preampDB = try value("PA").map { KenwoodCAT.isOn($0) ? radio.preampDB : 0 }
        // The AGC: the TS-590's GC (0 off, 1 slow, 2 fast), or the Elecraft's
        // GT, whose first three digits are the speed (2 fast, 4 slow).
        if radio.isElecraft {
            status.agc = try value("GT").flatMap { Int($0.prefix(3)) }.map { $0 == 2 ? 2 : 3 }
        } else {
            status.agc = try value("GC").flatMap { Int($0) }.flatMap { [0: 0, 1: 3, 2: 2][$0] }
        }
        status.noiseBlanker = try value("NB").map(KenwoodCAT.isOn)
        status.noiseReduction = try value("NR").map(KenwoodCAT.isOn)
        if mode.uppercased().hasPrefix("CW") && radio.isElecraft {
            status.peakFilter = try value("AP").map(KenwoodCAT.isOn)
        }
        if radio.isElecraft {
            status.dualWatch = try value("SB").map(KenwoodCAT.isOn)
        }
        // RF gain, volume and squelch: fractions from 0 to 1 of the radio's
        // largest number for each (see KenwoodRadio).
        status.rfGain = try value("RG").flatMap { Int($0) }.map { Double($0) / Double(radio.rfGainMax) }
        status.audioGain = try value("AG").flatMap { Int($0) }.map { Double($0) / Double(radio.audioMax) }
        if mode.uppercased().contains("FM") {
            status.squelch = try value("SQ").flatMap { Int($0) }.map { Double($0) / Double(radio.squelchMax) }
        }
        return status
    }

    // MARK: - Sending and waiting

    // Asks a question and returns the answer's value: "FA;" gets
    // "FA00014060000;", which gives "00014060000".
    private func ask(_ code: String) throws -> String {
        let port = try open()
        // Anything still arriving from an earlier question would be taken as
        // this answer, so it's thrown away first.
        port.discardInput()
        port.write(Array((code + ";").utf8))
        return try reply(to: code)
    }

    // Makes changes. Each command ends in ";", and "ID;" comes last: the
    // radio answers "ID" once it has taken them all, so the wait for that
    // answer is the wait for the changes. A "?" in between means one was
    // refused (see reply(to:)).
    private func change(_ commands: [String]) throws {
        let port = try open()
        port.discardInput()
        port.write(Array((commands.map { $0 + ";" } + ["ID;"]).joined().utf8))
        _ = try reply(to: "ID")
    }

    // The value of the next answer to `code`. Answers to other questions (a
    // late one, say) are skipped. "?" (not understood) or "E" (a
    // communication error) means the radio refused what was sent.
    private func reply(to code: String) throws -> String {
        for _ in 0..<8 {
            let token = try nextToken()
            if token.hasPrefix(code) { return String(token.dropFirst(code.count)) }
            if token == "?" || token == "E" { throw RadioFailure.rejected }
        }
        throw RadioFailure.notAnswering
    }

    // The next answer from the radio, without its ";". Times out after
    // replySeconds. Nothing arriving is "not answering" if the port is still
    // there, and "gone" if it isn't: the radio is off or unplugged, which
    // RadioMonitor says differently.
    private func nextToken() throws -> String {
        guard let port else { throw RadioFailure.portGone }
        var bytes: [UInt8] = []
        let deadline = Date().addingTimeInterval(Self.replySeconds)
        while true {
            let wait = deadline.timeIntervalSinceNow
            guard wait > 0 else { throw RadioFailure.notAnswering }
            guard let byte = port.read(1, timeout: wait).first else {
                throw FileManager.default.fileExists(atPath: path) ? RadioFailure.notAnswering : RadioFailure.portGone
            }
            if let token = KenwoodCAT.addByte(byte, to: &bytes) { return token }
            // A real answer is a few characters. Anything longer isn't this radio.
            guard bytes.count < 64 else { throw RadioFailure.notAnswering }
        }
    }

    // Opens the port on first use, with 8 data bits, no parity, one stop
    // bit and hardware handshake (Kenwood's format; the WinKeyer's two stop
    // bits are its own). The handshake is what the radio needs over USB:
    // without it the TS-590SG stays silent. Another app holding the port is
    // "busy", and a port that isn't there is "gone".
    private func open() throws -> SerialPort {
        if let port { return port }
        guard FileManager.default.fileExists(atPath: path) else { throw RadioFailure.portGone }
        do {
            let opened = try SerialPort(path, baud: Self.speed(baud), twoStopBits: false, hardwareHandshake: true)
            port = opened
            return opened
        } catch SerialPortError.inUse {
            throw RadioFailure.portBusy
        } catch {
            throw RadioFailure.portGone
        }
    }

    // The speeds Settings offers, as the port's constants. Anything else is
    // 38400, the usual Kenwood speed.
    private static func speed(_ baud: Int) -> speed_t {
        switch baud {
        case 4_800: speed_t(B4800)
        case 9_600: speed_t(B9600)
        case 19_200: speed_t(B19200)
        case 57_600: speed_t(B57600)
        case 115_200: speed_t(B115200)
        default: speed_t(B38400)
        }
    }
}
