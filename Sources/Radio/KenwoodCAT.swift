// KenwoodCAT.swift
//
// The built-in driver's words for the radio: Kenwood's CAT command format,
// which Elecraft's radios and the TS-590 also speak. Pure text in and out
// (no serial port here), so tools/radio-check can test the encoding and
// the reading of replies against canned answers.
//
// The format: a command is two letters, its value, and a ";". A question is
// the two letters and ";", and the radio answers with the same two letters
// and the value, then ";" ("FA;" -> "FA00014060000;"). A setting gets no
// answer, so a "?;" means the radio didn't understand it. Solid Copy adds
// "ID;" after each change: the radio answers "ID" once it has taken the
// change, so Solid Copy knows the change arrived (the KX3 ignores a change
// that isn't followed by a question, found with Radio > Record Radio Log,
// 15 November 2026).
//
// Which command means what is written next to each one below. Commands
// marked "radio-tested" were watched on Scott's TS-590SG or KX3 through
// rigctld's raw "W" command (see RigctldClient, 15 November 2026). The rest
// are from Kenwood's and Elecraft's command references, or from memory of
// them, and are NOT yet checked on a radio: see docs/PLAN.md Phase 3.

import Foundation

// One of the radios the built-in driver speaks to, by hamlib's model
// number (see RadioModels).
struct KenwoodRadio: Equatable {
    // Elecraft (K3, KX3, KX2) or Kenwood (TS-590S, TS-590SG). The two use
    // different numbers for the same modes, and different preamp and
    // attenuator commands.
    let isElecraft: Bool
    // The most power on the radio's own scale, in watts. (The KX3's is
    // lower on some bands; the built-in driver uses the top figure.)
    let maxWatts: Double
    // A preamp or attenuator's level in dB when on. The Elecraft preamp is
    // only on or off, so it's 1 (hamlib's "on"; see RadioStatus.level).
    let preampDB: Int
    let attenuatorDB: Int
    // The largest number each level's command takes, for RF gain (RG),
    // audio volume (AG) and squelch (SQ). Each is sent as a fraction of
    // this.
    let rfGainMax: Int
    let audioMax: Int
    let squelchMax: Int

    // The radios, by hamlib's model number. Only these five are offered
    // for the built-in driver (Settings > Radio).
    static func forModel(_ model: Int) -> KenwoodRadio? { table[model] }

    private static let table: [Int: KenwoodRadio] = [
        2031: ts590, 2037: ts590,   // TS-590S, TS-590SG
        2029: k3,                   // Elecraft K3
        2044: kx2,                  // Elecraft KX2
        2045: kx3,                  // Elecraft KX3
    ]

    // The TS-590 levels: preamp 12 dB, attenuator 12 dB, 100 watts. Its
    // RF gain, volume and squelch run 0 to 255.
    private static let ts590 = KenwoodRadio(isElecraft: false, maxWatts: 100, preampDB: 12, attenuatorDB: 12,
                                            rfGainMax: 255, audioMax: 255, squelchMax: 255)
    private static let k3 = KenwoodRadio(isElecraft: true, maxWatts: 100, preampDB: 1, attenuatorDB: 10,
                                         rfGainMax: 100, audioMax: 60, squelchMax: 29)
    private static let kx2 = KenwoodRadio(isElecraft: true, maxWatts: 12, preampDB: 1, attenuatorDB: 10,
                                          rfGainMax: 100, audioMax: 60, squelchMax: 29)
    private static let kx3 = KenwoodRadio(isElecraft: true, maxWatts: 15, preampDB: 1, attenuatorDB: 10,
                                          rfGainMax: 100, audioMax: 60, squelchMax: 29)

    // The filter width command. "BW" on Elecraft, "FW" on the TS-590 (not
    // yet checked on a radio). Both are in tens of hertz: BW0050 is 500 Hz.
    var filterCode: String { isElecraft ? "BW" : "FW" }
    // The filter width's unit in hertz: the Elecraft counts tens of hertz
    // (BW0050 is 500 Hz), the TS-590 counts hertz (FW0050 is 50 Hz, as its
    // knob shows).
    var filterUnit: Int { isElecraft ? 10 : 1 }
}

enum KenwoodCAT {

    // MARK: - Modes

    // The mode numbers. Kenwood's MD: 1 LSB, 2 USB, 3 CW, 4 FM, 5 AM, 6 FSK
    // (RTTY), 7 CW reverse, 9 FSK reverse. Elecraft's: 6 is DATA and 9 DATA
    // reverse, so data (PKTUSB) is 6 there. The TS-590 has no data mode
    // number: data is LSB, USB or FM with its DATA switch on (DA1; see
    // dataCommands and dataMode), so PKTUSB is MD2 there, with DA1.
    static func modeCode(_ mode: String, _ radio: KenwoodRadio) -> Int? {
        switch mode {
        case "LSB": 1
        case "USB": 2
        case "CW": 3
        case "FM": 4
        case "AM": 5
        case "RTTY": 6
        case "CWR": 7
        case "RTTYR": 9
        case "PKTUSB": radio.isElecraft ? 6 : 2
        case "PKTLSB": radio.isElecraft ? 9 : 1
        case "PKTFM" where !radio.isElecraft: 4
        default: nil
        }
    }

    // The TS-590's DATA switch for a mode: DA1 for the data modes, DA0 for
    // LSB, USB, FM and AM (so choosing USB really is voice), nothing for
    // CW and FSK, where DA is an error. Kenwood's PC command reference:
    // "DA Sets and reads the DATA mode", 0 off, 1 on, "in LSB, USB, FM,
    // and AM mode". Elecraft radios have their own DATA mode number.
    static func dataCommands(_ mode: String, _ radio: KenwoodRadio) -> [String] {
        guard !radio.isElecraft else { return [] }
        switch mode {
        case "PKTUSB", "PKTLSB", "PKTFM": return ["DA1"]
        case "LSB", "USB", "FM", "AM": return ["DA0"]
        default: return []
        }
    }

    // A TS-590 mode read with its DATA switch ("DA" answers "1" when on):
    // USB with DATA on is PKTUSB, and so on. AM with DATA stays AM (hamlib
    // has no name for it). Elecraft and every other mode: as read.
    static func dataMode(_ mode: String, dataBody: String?, _ radio: KenwoodRadio) -> String {
        guard !radio.isElecraft, dataBody == "1" else { return mode }
        switch mode {
        case "USB": return "PKTUSB"
        case "LSB": return "PKTLSB"
        case "FM": return "PKTFM"
        default: return mode
        }
    }

    // The reverse of modeCode, as hamlib names the mode.
    static func modeName(_ code: Int, _ radio: KenwoodRadio) -> String? {
        switch code {
        case 1: "LSB"
        case 2: "USB"
        case 3: "CW"
        case 4: "FM"
        case 5: "AM"
        case 6: radio.isElecraft ? "PKTUSB" : "RTTY"
        case 7: "CWR"
        case 9: radio.isElecraft ? "PKTLSB" : "RTTYR"
        default: nil
        }
    }

    // MARK: - Writing: hamlib's command strings, as Kenwood's

    // Turns one command from RadioControl ("F 7025300", "M CW 500") into
    // the Kenwood commands that do it, without their ";". Throws `rejected`
    // for a command the radio hasn't got, so setFirst tries the next one.
    // `receiveVFOB` says which VFO is receiving, so "F" tunes that one.
    static func commands(for command: String, radio: KenwoodRadio, receiveVFOB: Bool) throws -> [String] {
        let words = command.split(separator: " ").map(String.init)
        guard let verb = words.first else { throw RadioFailure.rejected }
        switch (verb, words.count) {
        case ("F", 2):
            // Eleven digits, with the leading zeros: 7025300 is 00007025300.
            guard let hertz = Int(words[1]), hertz > 0 else { throw RadioFailure.rejected }
            return [(receiveVFOB ? "FB" : "FA") + pad(hertz, 11)]
        case ("M", 3):
            guard let code = modeCode(words[1], radio), let width = Int(words[2]) else { throw RadioFailure.rejected }
            // The mode first, then (TS-590) its DATA switch: a filter width
            // is for the mode in use. Width 0 is the radio's usual one for
            // the mode, so it isn't sent.
            return ["MD\(code)"] + dataCommands(words[1], radio)
                + (width > 0 ? [radio.filterCode + pad(width / radio.filterUnit, 4)] : [])
        case ("SCAN", 2):
            // The radio's own band scan: 1 scans up, 0 stops (see RadioMonitor).
            guard words[1] == "1" || words[1] == "0" else { throw RadioFailure.rejected }
            return ["SC" + words[1]]
        case ("W", 2):
            // A filter width alone, for the mode in use (see RadioControl).
            guard let width = Int(words[1]), width > 0 else { throw RadioFailure.rejected }
            return [radio.filterCode + pad(width / radio.filterUnit, 4)]
        case ("L", 3):
            return try levels(words[1], words[2], radio)
        case ("U", 3):
            return try switches(words[1], words[2] == "1" ? "1" : "0", radio)
        case ("J", 2), ("Z", 2):
            // The RIT or XIT offset. Both share one offset on these radios
            // (RO), with a sign and four digits: RO+0100 is 100 hertz up.
            guard let hertz = Int(words[1]) else { throw RadioFailure.rejected }
            return ["RO" + (hertz < 0 ? "-" : "+") + pad(abs(hertz), 4)]
        case ("S", 3):
            // Split: transmit on VFO B (FT1) while receiving on A.
            return [words[1] == "1" ? "FT1" : "FT0"]
        case ("G", 2):
            switch words[1] {
            case "XCHG": return ["SV"]        // swap VFOs A and B (not yet checked)
            case "BAND_UP": return ["BU"]     // the radio's own band keys (not yet checked)
            case "BAND_DOWN": return ["BD"]
            default: throw RadioFailure.rejected
            }
        case ("V", 2):
            // Receive on a VFO: FR0 is A, FR1 is B (not yet checked).
            switch words[1] {
            case "VFOA": return ["FR0"]
            case "VFOB": return ["FR1"]
            default: throw RadioFailure.rejected
            }
        case ("T", 2):
            // Transmit, only for a program sharing the radio (RigctlServer),
            // never for Solid Copy's own keys. hamlib's values: 0 receive, 1
            // transmit, 2 from the microphone, 3 from the data input.
            // TS-590: TX0 sends the microphone, TX1 the data input (the USB
            // audio a digital-mode program plays), so 1 and 3 are TX1. The
            // KX3 and K3 have one TX. RX goes back to receive. (Not yet
            // checked on a radio: try it into a dummy load first.)
            switch words[1] {
            case "0": return ["RX"]
            case "1", "3": return [radio.isElecraft ? "TX" : "TX1"]
            case "2": return [radio.isElecraft ? "TX" : "TX0"]
            default: throw RadioFailure.rejected
            }
        case ("POWER", 2):
            // Watts, sent as three digits. Rounded to the whole watt, since
            // the command takes no tenths (not yet checked on the KX3, which
            // may take them). At least 1 watt, so the radio isn't set to
            // zero.
            guard let watts = Double(words[1]) else { throw RadioFailure.rejected }
            let whole = min(max(Int(watts.rounded()), 1), Int(radio.maxWatts))
            return ["PC" + pad(whole, 3)]
        default:
            throw RadioFailure.rejected
        }
    }

    // "L" settings: keyer speed, preamp, attenuator, AGC, RF gain, volume and
    // squelch. hamlib's numbers for AGC: 2 fast, 3 slow.
    private static func levels(_ name: String, _ value: String, _ radio: KenwoodRadio) throws -> [String] {
        let number = Int(value)
        switch name {
        case "KEYSPD":
            guard let speed = number else { throw RadioFailure.rejected }
            return ["KS" + pad(speed, 3)]
        case "PREAMP":
            // Off, or the radio's own preamp. The Elecraft has one level, so
            // any value on is taken; the TS-590 takes only its 12 dB.
            guard let db = number else { throw RadioFailure.rejected }
            if db == 0 { return ["PA0"] }
            guard db == radio.preampDB || radio.isElecraft else { throw RadioFailure.rejected }
            return ["PA1"]
        case "ATT":
            guard let db = number else { throw RadioFailure.rejected }
            if db == 0 { return ["RA00"] }
            guard db == radio.attenuatorDB else { throw RadioFailure.rejected }
            return ["RA01"]
        case "AGC":
            // The TS-590 has no "off" from a speed: GC3 (on again, at the
            // last speed) comes first, or the radio refuses the speed
            // (found 15 November 2026). Radio-tested on the TS-590SG.
            guard let speed = number else { throw RadioFailure.rejected }
            switch (radio.isElecraft, speed) {
            case (false, 0): return ["GC0"]
            case (false, 2): return ["GC3", "GC2"]
            case (false, 3): return ["GC3", "GC1"]
            case (true, 2): return ["GT002"]    // radio-tested on the KX3
            case (true, 3): return ["GT004"]
            default: throw RadioFailure.rejected
            }
        case "RF", "AF", "SQL":
            // A fraction from 0 to 1, sent as a whole number up to the
            // radio's largest (see KenwoodRadio).
            guard let fraction = Double(value) else { throw RadioFailure.rejected }
            let top = name == "RF" ? radio.rfGainMax : name == "AF" ? radio.audioMax : radio.squelchMax
            let level = pad(min(max(Int((fraction * Double(top)).rounded()), 0), top), 3)
            switch name {
            case "RF": return ["RG" + level]
            case "AF": return ["AG0" + level]
            default: return [radio.isElecraft ? "SQ" + level : "SQ0" + level]
            }
        default:
            throw RadioFailure.rejected   // "L NR" isn't one of these (use "U NR")
        }
    }

    // "U" switches: 1 on, 0 off. The noise reduction, noise blanker, RIT and
    // XIT are on both families; the peak filter and dual watch only on the
    // Elecraft radios.
    private static func switches(_ name: String, _ on: String, _ radio: KenwoodRadio) throws -> [String] {
        switch name {
        case "NB": return ["NB" + on]
        case "NR": return ["NR" + on]    // TS-590: NR1 is on (not yet checked)
        case "RIT": return ["RT" + on]
        case "XIT": return ["XT" + on]
        case "APF" where radio.isElecraft: return ["AP" + on]     // not yet checked
        case "DUAL_WATCH" where radio.isElecraft: return ["SB" + on]   // radio-tested on the KX3
        default: throw RadioFailure.rejected
        }
    }

    // MARK: - Reading the radio's answers

    // The frequency in hertz from "00014060000" (the body of "FA").
    static func hertz(_ body: String) -> Int? { Int(body).flatMap { $0 > 0 ? $0 : nil } }

    // The mode from its number ("3" is CW).
    static func mode(_ body: String, _ radio: KenwoodRadio) -> String? {
        Int(body).flatMap { modeName($0, radio) }
    }

    // The filter width in hertz from "0050" (the body of "BW" or "FW"),
    // multiplied by the radio's unit (see filterUnit). nil if zero.
    static func passband(_ body: String, unit: Int) -> Int? {
        Int(body).flatMap { $0 > 0 ? $0 * unit : nil }
    }

    // Watts from "100" (the body of "PC"), or nil if zero.
    static func watts(_ body: String) -> Double? {
        Int(body).flatMap { $0 > 0 ? Double($0) : nil }
    }

    // A signed offset from "+0100" or "-0050" (the body of "RO").
    static func offset(_ body: String) -> Int? { Int(body) }

    // A switch's answer: on unless its first digit is 0 ("NB00" is off, as
    // is "NR0"; "NB10" is on).
    static func isOn(_ body: String) -> Bool { body.first.map { $0 != "0" } ?? false }

    // Adds one byte from the radio to the answer being read. Returns the
    // answer, without its ";", when that byte is the ";" (and empties the
    // buffer for the next one); nil while the answer is still coming. Line
    // ends and spaces aren't part of an answer.
    static func addByte(_ byte: UInt8, to bytes: inout [UInt8]) -> String? {
        if byte == UInt8(ascii: ";") {
            defer { bytes.removeAll() }
            return String(decoding: bytes, as: UTF8.self)
        }
        if byte > 0x20 { bytes.append(byte) }
        return nil
    }

    // A number, zero-padded to `digits`: pad(7, 3) is "007".
    static func pad(_ value: Int, _ digits: Int) -> String {
        String(format: "%0\(digits)d", value)
    }
}
