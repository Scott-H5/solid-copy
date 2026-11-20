// RadioControl.swift
//
// Driving the radio from the keyboard: tuning, band, mode, filter width,
// keyer speed, preamp, attenuator, AGC, noise blanker and reduction,
// audio peak filter, dual watch, RIT and XIT and their offset, split and
// VFOs. (Power, RF gain, squelch and the S-meter are in RadioMonitor.)
// Each command changes the radio through its client (RadioLink), reads it back, and
// says what the radio actually did ("CW, 500 hertz"), since a radio may
// round a value or refuse it.
//
// Also: a frequency or mode typed in the Callsign field. A callsign always
// has both letters and a digit, so "14060", "7.0255" (numbers only) and
// "CW", "USB" (letters only) can't be callsigns, and Return tunes the
// radio or changes its mode instead of logging. (Contest loggers such as
// N1MM work the same way.)

import AppKit

// What was typed in the Callsign field, if it's a radio command.
enum RadioEntry: Equatable {
    case frequency(hertz: Int)
    case mode(String)

    // "14060" or "14060.5": kilohertz (1000 or more). "14.06", "7": megahertz.
    // "CW", "USB", "LSB", "AM", "FM", "RTTY", "DATA", and "SSB" (the usual
    // sideband for the band: lower below 10 MHz, upper above).
    static func parse(_ text: String, currentHertz: Int?) -> RadioEntry? {
        let text = text.trimmingCharacters(in: .whitespaces).uppercased()
        if let number = Double(text), number > 0, text.allSatisfy({ $0.isNumber || $0 == "." }) {
            let hertz = number >= 1_000 ? number * 1_000 : number * 1_000_000
            return .frequency(hertz: Int(hertz.rounded()))
        }
        switch text {
        case "CW", "CWR", "USB", "LSB", "AM", "FM", "RTTY", "RTTYR": return .mode(text)
        case "DATA", "DIGI", "PKT": return .mode("PKTUSB")
        case "SSB": return .mode((currentHertz ?? 14_000_000) < 10_000_000 ? "LSB" : "USB")
        default: return nil
        }
    }
}

extension RadioMonitor {

    // The tuning steps: Up and Down 100 hertz, with Shift 10, with Option
    // 1 kilohertz.
    static let tuningStep = 100
    static let fineTuningStep = 10
    static let coarseTuningStep = 1_000

    // Tunes up (positive) or down by this many hertz.
    func tune(by hertz: Int) {
        guard let reading else { return Speaker.announce(notConnectedText) }
        tune(toHertz: reading.hertz + hertz)
    }

    // Tunes and says the frequency (for a typed frequency; the tuning
    // control speaks for itself as it changes).
    func tuneAndSay(toHertz hertz: Int) {
        guard reading != nil else { return Speaker.announce(notConnectedText) }
        tune(toHertz: hertz)
        let megahertz = RadioReading.trimmedMegahertz(hertz)
        Speaker.say(.radio, full: "\(megahertz) megahertz.", cue: .radio)
    }

    // Changes the mode, keeping the radio's usual filter for it.
    func setMode(_ mode: String) {
        guard reading != nil else { return Speaker.announce(notConnectedText) }
        change("M \(mode) 0") { reading in
            guard let reading else { return Speaker.announce("The radio didn't take \(mode).") }
            Speaker.say(.radio, full: ([reading.spokenMode] + [reading.filterSpoken].compactMap { $0 })
                .joined(separator: ", ") + ".", cue: .radio)
        }
    }

    // Radio > Next Mode: CW, USB, LSB, data, AM, FM, RTTY, then CW again.
    func nextMode() {
        guard let reading else { return Speaker.announce(notConnectedText) }
        let order = ["CW", "USB", "LSB", "PKTUSB", "AM", "FM", "RTTY"]
        let index = order.firstIndex(of: reading.mode.uppercased()) ?? -1
        setMode(order[(index + 1) % order.count])
    }

    // Radio > Wider Filter, Narrower Filter: the next common width up or
    // down for the mode. The radio picks its nearest, which is said.
    func changeFilter(wider: Bool) {
        guard let reading else { return Speaker.announce(notConnectedText) }
        let narrowModes = ["CW", "CWR", "RTTY", "RTTYR", "PKTUSB", "PKTLSB"]
        let voiceModes = ["USB", "LSB"]
        let widths: [Int]
        if narrowModes.contains(reading.mode.uppercased()) {
            // The TS-590's own steps, as its knob goes (the radio refuses any other).
            widths = [50, 80, 100, 150, 200, 250, 300, 400, 500, 600, 1_000, 1_500, 2_000, 2_500]
        } else if voiceModes.contains(reading.mode.uppercased()) {
            if !canSetSSBWidth { return Speaker.announce("\(radioName) sets its SSB width on the radio.") }
            widths = [1_800, 2_100, 2_400, 2_700, 3_000, 3_600]
        } else {
            return Speaker.announce("No filter choices for \(reading.spokenMode).")
        }
        let current = reading.passband ?? widths[widths.count / 2]
        guard let width = wider ? widths.first(where: { $0 > current }) : widths.last(where: { $0 < current }) else {
            return Speaker.announce("Filter \(reading.filterSpoken ?? ""), the \(wider ? "widest" : "narrowest").")
        }
        // Width only: "M" would also send the mode, and the TS-590 says the
        // mode aloud (with a morse C) on every change, even when it is the same.
        change("W \(width)") { newReading in
            guard let newReading else { return Speaker.announce("The radio didn't change the filter.") }
            Speaker.say(.radio, full: "Filter \(newReading.filterSpoken ?? "unknown").", cue: .radio)
        }
    }

    // Radio > Keyer Faster, Keyer Slower: one word per minute.
    func changeKeyerSpeed(by step: Int) {
        guard reading != nil else { return Speaker.announce(notConnectedText) }
        guard let wpm = status?.keyerWPM else { return Speaker.announce("The radio doesn't report keyer speed.") }
        let target = min(max(wpm + step, 5), 60)
        change("L KEYSPD \(target)") { reading in
            guard reading != nil, let now = RadioMonitor.shared.status?.keyerWPM else {
                return Speaker.announce("The radio didn't change keyer speed.")
            }
            Speaker.say(.radio, full: "Keyer \(now) words per minute.", cue: .radio)
        }
    }

    // MARK: - Bands
    //
    // Radio > Band Up, Band Down (Control-Command-Up and Down Arrow). The
    // radio's own band keys first (hamlib's BAND_UP and BAND_DOWN, which
    // keep the radio's band memory). A radio that can't (the KX3 through
    // hamlib, the dummy radio) is tuned by Solid Copy instead: back to
    // where you last were on that band this session, or else to a usual
    // spot for the mode (near the CW end, or in the phone part). 60 meters
    // is skipped (its channels are fixed), and 30 meters for phone (it has
    // none). Says "20 meters, 14.03 megahertz, CW".

    // The bands stepped through, with a usual CW and phone frequency in
    // kilohertz.
    private static let bandSteps: [(band: String, cw: Int, phone: Int)] = [
        ("160m", 1_810, 1_900), ("80m", 3_530, 3_850), ("40m", 7_030, 7_200), ("30m", 10_110, 0),
        ("20m", 14_030, 14_250), ("17m", 18_080, 18_130), ("15m", 21_030, 21_300),
        ("12m", 24_900, 24_950), ("10m", 28_030, 28_400), ("6m", 50_090, 50_150),
    ]

    func changeBand(up: Bool) {
        guard let reading else { return Speaker.announce(notConnectedText) }
        change(up ? "G BAND_UP" : "G BAND_DOWN") { newReading in
            let monitor = RadioMonitor.shared
            if let newReading, newReading.band != reading.band {
                return Speaker.say(.radio, full: Self.bandSpoken(newReading), cue: .radio)
            }
            monitor.stepBand(from: reading, up: up)
        }
    }

    private func stepBand(from reading: RadioReading, up: Bool) {
        let phone = ["USB", "LSB", "AM", "FM"].contains(reading.mode.uppercased())
        let steps = Self.bandSteps.filter { !phone || $0.phone > 0 }
        // The next band in the list, from the band you're on (or, outside
        // the ham bands, from the frequency).
        let kilohertz = reading.hertz / 1_000
        let next = up ? steps.first { $0.cw > kilohertz + 100 && $0.band != reading.band }
                      : steps.last { $0.cw < kilohertz - 100 && $0.band != reading.band }
        guard let next else {
            NSSound.beep()
            return Speaker.announce(up ? "No band above." : "No band below.")
        }
        let remembered = lastOnBand[next.band]
        let hertz = remembered?.hertz ?? (phone ? next.phone : next.cw) * 1_000
        // The sideband that goes with the band, for SSB: lower below 10 MHz.
        var mode = remembered?.mode ?? reading.mode
        if ["USB", "LSB"].contains(mode.uppercased()) { mode = hertz < 10_000_000 ? "LSB" : "USB" }
        change("F \(hertz)") { tuned in
            guard tuned != nil else { return Speaker.announce("The radio didn't take \(next.band).") }
            let monitor = RadioMonitor.shared
            guard mode.uppercased() != monitor.reading?.mode.uppercased() else {
                return Speaker.say(.radio, full: Self.bandSpoken(monitor.reading), cue: .radio)
            }
            monitor.change("M \(mode) 0") { moded in
                Speaker.say(.radio, full: Self.bandSpoken(moded ?? RadioMonitor.shared.reading), cue: .radio)
            }
        }
    }

    // "20 meters, 14.03 megahertz, CW."
    private static func bandSpoken(_ reading: RadioReading?) -> String {
        guard let reading else { return "Band changed." }
        let band = reading.band.map { Bands.spoken($0) + ", " } ?? ""
        return band + "\(RadioReading.trimmedMegahertz(reading.hertz)) megahertz, \(reading.spokenMode)."
    }

    // MARK: - Receive and transmit settings
    //
    // Each press changes the radio, reads it back and says what it's now
    // set to ("Preamp 12 dB", "Noise blanker off"). Radio > Preamp and the
    // rest; see AppDelegate.fillRadioMenu for their keys.

    // Radio > Preamp: off, or on at the radio's own preamp (12 dB on the
    // TS-590SG). hamlib only takes a value the radio has, so the usual
    // ones are tried from the lowest; radios with two preamps (10 and 20
    // dB) get the first.
    func togglePreamp() {
        let on = (status?.preampDB).map { $0 > 0 }
        changeSetting("preamp", known: on != nil,
                      commands: on == true ? ["L PREAMP 0"] : [1, 6, 10, 12, 14, 18, 20].map { "L PREAMP \($0)" }) {
            $0.preampDB.map { "Preamp " + RadioStatus.level($0) }
        }
    }

    // Radio > Attenuator: off, or on at the radio's own attenuator (12 dB
    // on the TS-590SG, 10 on the KX3).
    func toggleAttenuator() {
        let on = (status?.attenuatorDB).map { $0 > 0 }
        changeSetting("attenuator", known: on != nil,
                      commands: on == true ? ["L ATT 0"] : [3, 6, 10, 12, 18, 20].map { "L ATT \($0)" }) {
            $0.attenuatorDB.map { "Attenuator " + RadioStatus.level($0) }
        }
    }

    // Radio > AGC: slow, medium, fast, off, then slow again, skipping any
    // the radio hasn't got (the TS-590SG and KX3 have no medium).
    func nextAGC() {
        let order = [3, 5, 2, 0]   // hamlib: slow, medium, fast, off
        let next = (order.firstIndex(of: status?.agc ?? -1) ?? -1) + 1
        let tries = (0..<order.count).map { order[(next + $0) % order.count] }
        changeSetting("AGC", known: status?.agc != nil, commands: tries.map { "L AGC \($0)" }) {
            $0.agcText.map { "AGC \($0)" }
        }
    }

    // Radio > Noise Blanker, Noise Reduction, Audio Peak Filter, RIT, XIT,
    // Split: on and off.
    func toggleNoiseBlanker() { toggle("noise blanker", \.noiseBlanker) { ["U NB \($0)"] } }
    // Noise reduction: the switch, or (on radios where hamlib only has
    // its level, such as the KX3) the level, halfway for on.
    func toggleNoiseReduction() {
        toggle("noise reduction", \.noiseReduction) { ["U NR \($0)", "L NR \($0 == 1 ? "0.5" : "0")"] }
    }
    // The TS-590 has no audio peak filter (the Elecraft radios do).
    func togglePeakFilter() {
        if !hasPeakFilter { return Speaker.announce("\(radioName) has no audio peak filter.") }
        toggle("audio peak filter", \.peakFilter) { ["U APF \($0)"] }
    }
    // Dual watch: both VFOs heard at once (the KX3's SUB).
    func toggleDualWatch() { toggle("dual watch", \.dualWatch) { ["U DUAL_WATCH \($0)"] } }
    func toggleRIT() { toggle("RIT", \.ritOn) { ["U RIT \($0)"] } }
    func toggleXIT() { toggle("XIT", \.xitOn) { ["U XIT \($0)"] } }
    // Split: receive on VFO A, transmit on B.
    func toggleSplit() { toggle("split", \.split) { $0 == 1 ? ["S 1 VFOB"] : ["S 0 VFOA"] } }

    // Radio > Swap VFOs: A and B change places, or (on radios that can't
    // swap, such as the TS-590SG and KX3 through hamlib) the other VFO is
    // used. Says the VFO and its frequency: "VFO B, 14.060 megahertz, CW".
    func swapVFOs() {
        guard reading != nil else { return Speaker.announce(notConnectedText) }
        let other = status?.vfo == "VFOB" ? "VFOA" : "VFOB"
        change(["G XCHG", "G TOGGLE", "V \(other)"]) { reading, _ in
            guard let reading else { return Speaker.announce("\(RadioMonitor.shared.radioName) didn't change VFOs.") }
            let vfo = RadioMonitor.shared.status?.vfo.flatMap { $0.hasPrefix("VFO") ? "VFO \($0.dropFirst(3)), " : nil }
            Speaker.say(.radio, full: (vfo ?? "") + reading.spoken + ".", cue: .radio)
        }
    }

    // Offset control: Up and Down, Delete to clear.
    // (Power, RF gain and squelch: changeLevel, in RadioMonitor.)
    func changeOffset(by hertz: Int) {
        guard let offset = offsetHertz else { return Speaker.announce(noOffsetText) }
        setOffset(toHertz: min(max(offset + hertz, -9_990), 9_990))
    }
    func clearOffset() {
        guard offsetHertz != nil else { return Speaker.announce(noOffsetText) }
        setOffset(toHertz: 0)
    }
    private var noOffsetText: String {
        reading == nil ? notConnectedText : "\(radioName) doesn't report a RIT offset."
    }

    // On and off, for the settings that are just that: "1" turns on.
    private func toggle(_ name: String, _ setting: KeyPath<RadioStatus, Bool?>, commands: (Int) -> [String]) {
        let on = status?[keyPath: setting]
        changeSetting(name, known: on != nil, commands: commands(on == true ? 0 : 1)) {
            $0[keyPath: setting].map { "\(name.prefix(1).uppercased() + name.dropFirst()) \($0 ? "on" : "off")" }
        }
    }

    // Sends the first of `commands` the radio takes, then says the
    // setting as the radio reports it.
    private func changeSetting(_ name: String, known: Bool, commands: [String],
                               said: @escaping @MainActor (RadioStatus) -> String?) {
        guard reading != nil else { return Speaker.announce(notConnectedText) }
        guard known else { return Speaker.announce("\(radioName) doesn't report its \(name).") }
        let before = status.flatMap(said)
        change(commands) { reading, _ in
            let monitor = RadioMonitor.shared
            // Reported the same as before: the radio took the command but
            // didn't act on it (the KX3's noise reduction does this).
            guard reading != nil, let text = monitor.status.flatMap(said), text != before else {
                return Speaker.announce("\(monitor.radioName) didn't change its \(name).")
            }
            Speaker.say(.radio, full: text + ".", cue: .radio)
        }
    }

    var notConnectedText: String {
        state == .none ? "No radio in use." : "\(radioName) isn't connected."
    }
}

extension RadioReading {
    // 14060000 -> "14.06", 7025300 -> "7.0253": megahertz without trailing
    // zeros, for speech.
    static func trimmedMegahertz(_ hertz: Int) -> String {
        var text = String(format: "%.6f", Double(hertz) / 1_000_000)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
