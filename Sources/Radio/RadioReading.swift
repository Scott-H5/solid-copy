// RadioReading.swift
//
// What the radio says it's doing: frequency, mode and power. Turned into
// the log's own terms (ADIF frequency in megahertz, band, mode and
// submode, watts) and into words for VoiceOver.

import Foundation

struct RadioReading: Equatable {
    // The frequency in hertz: 7025241 is 7.025241 MHz.
    var hertz: Int
    // hamlib's name for the mode: "CW", "USB", "LSB", "PKTUSB", ...
    var mode: String
    // Output power, if the radio reports it.
    var watts: Double?
    // The receive filter's width in hertz (hamlib's "passband"), if known.
    var passband: Int?
    // The most power the radio has, if it reports power at all.
    var maxWatts: Double?

    // ADIF FREQ: megahertz, with at least three decimals ("14.060",
    // "7.025241").
    var megahertzText: String {
        var text = String(format: "%.6f", Double(hertz) / 1_000_000)
        while text.hasSuffix("0"), text.split(separator: ".").last.map({ $0.count > 3 }) == true {
            text.removeLast()
        }
        return text
    }

    // ADIF BAND, from the frequency ("40m"), or nil outside the ham bands.
    var band: String? { Bands.name(forHertz: hertz) }

    // ADIF MODE and SUBMODE. USB and LSB are both SSB to ADIF, with the
    // sideband as the submode. nil for modes Solid Copy can't name for
    // ADIF: the data modes (the radio says "PKTUSB", not whether it's
    // FT8 or PSK31), so the mode you typed is kept.
    var adifMode: (mode: String, submode: String)? {
        switch mode.uppercased() {
        case "CW", "CWR": return ("CW", "")
        case "USB": return ("SSB", "USB")
        case "LSB": return ("SSB", "LSB")
        case "AM", "AMS", "SAM", "AMN": return ("AM", "")
        case "FM", "FMN", "WFM": return ("FM", "")
        case "RTTY", "RTTYR": return ("RTTY", "")
        default: return nil
        }
    }

    // ADIF TX_PWR: "100", "5", "0.5".
    var wattsText: String? {
        guard let watts, watts > 0 else { return nil }
        return Self.wattsText(watts)
    }

    // 100 -> "100", 5 -> "5", 2.5 -> "2.5": to the watt from 10 up,
    // otherwise to a tenth.
    static func wattsText(_ watts: Double) -> String {
        if watts >= 10 { return String(format: "%.0f", watts) }
        let text = String(format: "%.1f", watts)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    // The digital mode a program on this Mac says it's using (WSJT-X's
    // FT8, say), with when it said so, set by WSJTXListener. A data mode
    // on the radio can't name its digital mode, so this fills Mode then.
    // Only trusted for a minute: an old one may be a program since quit.
    nonisolated(unsafe) static var digitalMode: (mode: String, submode: String, said: Date)?

    // The fields this reading fills in, by ADIF name.
    var fields: [String: String] {
        var fields = ["freq": megahertzText]
        if let band { fields["band"] = band }
        if let adifMode {
            fields["mode"] = adifMode.mode
            fields["submode"] = adifMode.submode
        } else if mode.uppercased().hasPrefix("PKT"), let digital = Self.digitalMode,
                  Date().timeIntervalSince(digital.said) < 60 {
            fields["mode"] = digital.mode
            fields["submode"] = digital.submode
        }
        if let wattsText { fields["tx_pwr"] = wattsText }
        return fields
    }

    // The fields a radio can fill in. Typing in one of these on the form
    // keeps what you typed instead.
    static let fieldNames: Set<String> = ["freq", "band", "mode", "submode", "tx_pwr"]

    // For speech: "7.025 megahertz, CW". (To the kilohertz: more is noise
    // when heard.)
    var spoken: String {
        let frequency = String(format: "%.3f", Double(hertz) / 1_000_000)
        return "\(frequency) megahertz, \(spokenMode)"
    }

    // "CW", "USB", "data".
    var spokenMode: String {
        mode.uppercased().hasPrefix("PKT") ? "data" : (adifMode.map { $0.submode.isEmpty ? $0.mode : $0.submode } ?? mode)
    }

    // In kilohertz, to the 10 hertz, for tuning: "7025.30". (Tuning in 10
    // hertz steps, megahertz would need too many decimals to hear.)
    var kilohertzText: String { String(format: "%.2f", Double(hertz) / 1_000) }

    // "500 hertz", "2.4 kilohertz".
    var filterSpoken: String? {
        guard let passband else { return nil }
        return passband < 1_000 ? "\(passband) hertz" : Self.trimmed(Double(passband) / 1_000) + " kilohertz"
    }

    // "500 Hz", "2.4 kHz".
    var filterShown: String? {
        guard let passband else { return nil }
        return passband < 1_000 ? "\(passband) Hz" : Self.trimmed(Double(passband) / 1_000) + " kHz"
    }

    // 2.4 -> "2.4", 3.0 -> "3".
    static func trimmed(_ number: Double) -> String {
        let text = String(format: "%.1f", number)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    // For the screen: "7.025241 MHz, CW, 500 Hz, 40m, 5 W".
    var shown: String {
        [megahertzText + " MHz", spokenMode, filterShown, band, wattsText.map { $0 + " W" }]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

// The amateur bands, as ADIF names them, with their edges in hertz.
enum Bands {
    // "20m" -> "20 meters", "70cm" -> "70 centimeters", so it's spoken
    // properly. Anything else is left as it is.
    static func spoken(_ band: String) -> String {
        let lower = band.lowercased()
        if lower.hasSuffix("cm"), Double(lower.dropLast(2)) != nil { return "\(lower.dropLast(2)) centimeters" }
        if lower.hasSuffix("mm"), Double(lower.dropLast(2)) != nil { return "\(lower.dropLast(2)) millimeters" }
        if lower.hasSuffix("m"), Double(lower.dropLast()) != nil { return "\(lower.dropLast()) meters" }
        return band
    }

    // A band as typed, in ADIF's terms, or nil if it isn't one. LoTW and
    // awards only know ADIF's names ("20m"), so "20", "20 M", "20 meters"
    // and a frequency in megahertz ("14.058") all become "20m". Empty
    // stays empty. (Scott's VE6BBP, 16 November 2026: TQSL refused "20".)
    static func normalized(_ text: String) -> String? {
        var band = text.lowercased().filter { !$0.isWhitespace }
        guard !band.isEmpty else { return "" }
        for (word, unit) in [("millimeters", "mm"), ("centimeters", "cm"), ("meters", "m"), ("meter", "m")]
        where band.hasSuffix(word) {
            band = band.dropLast(word.count) + unit
            break
        }
        if names.contains(band) { return band }
        guard let number = Double(band), number > 0 else { return nil }
        // A bare number: meters if that's a band, otherwise megahertz.
        if names.contains(band + "m") { return band + "m" }
        return name(forHertz: Int((number * 1_000_000).rounded()))
    }

    private static let names = Set(edges.map(\.name))

    static func name(forHertz hertz: Int) -> String? {
        let kilohertz = Double(hertz) / 1_000
        return edges.first { kilohertz >= $0.low && kilohertz <= $0.high }?.name
    }

    // From the ADIF specification's Band enumeration, in kilohertz.
    private static let edges: [(name: String, low: Double, high: Double)] = [
        ("2190m", 135.7, 137.8), ("630m", 472, 479), ("560m", 501, 504),
        ("160m", 1_800, 2_000), ("80m", 3_500, 4_000), ("60m", 5_060, 5_450),
        ("40m", 7_000, 7_300), ("30m", 10_100, 10_150), ("20m", 14_000, 14_350),
        ("17m", 18_068, 18_168), ("15m", 21_000, 21_450), ("12m", 24_890, 24_990),
        ("10m", 28_000, 29_700), ("8m", 40_000, 45_000), ("6m", 50_000, 54_000),
        ("5m", 54_000.001, 69_900), ("4m", 70_000, 71_000), ("2m", 144_000, 148_000),
        ("1.25m", 222_000, 225_000), ("70cm", 420_000, 450_000), ("33cm", 902_000, 928_000),
        ("23cm", 1_240_000, 1_300_000), ("13cm", 2_300_000, 2_450_000), ("9cm", 3_300_000, 3_500_000),
        ("6cm", 5_650_000, 5_925_000), ("3cm", 10_000_000, 10_500_000), ("1.25cm", 24_000_000, 24_250_000),
        ("6mm", 47_000_000, 47_200_000), ("4mm", 75_500_000, 81_000_000), ("2.5mm", 119_980_000, 123_000_000),
        ("2mm", 134_000_000, 149_000_000), ("1mm", 241_000_000, 250_000_000),
    ]
}

// The radio's slower-changing settings, read every few seconds for the
// status line at the bottom of the window. Each is nil if the radio
// doesn't report it.
struct RadioStatus: Equatable {
    // "VFOA" or "VFOB" (or "MEM"): the VFO in use.
    var vfo: String?
    var keyerWPM: Int?
    // RIT and XIT switched on, and their offsets in hertz. (On the
    // TS-590SG and KX3, RIT and XIT share one offset.)
    var ritOn: Bool?
    var xitOn: Bool?
    var ritHertz: Int?
    var xitHertz: Int?
    var split: Bool?
    // hamlib's AGC number: 0 off, 1 super fast, 2 fast, 3 slow, 4 user,
    // 5 medium, 6 auto.
    var agc: Int?
    var preampDB: Int?
    var attenuatorDB: Int?
    var noiseBlanker: Bool?
    var noiseReduction: Bool?
    // The audio peak filter, for CW (the KX3's APF).
    var peakFilter: Bool?
    // RF gain, squelch and audio volume, from 0 to 1 (squelch read only in FM).
    var rfGain: Double?
    var squelch: Double?
    var audioGain: Double?
    // Dual watch: listening on both VFOs (the KX3's SUB).
    var dualWatch: Bool?

    // 0.8 -> "80%"; for speech "80 percent".
    static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }

    static let agcNames = ["off", "super fast", "fast", "slow", "user", "medium", "auto"]

    // A preamp or attenuator: "off", "12 dB", or "on" for one that's only
    // on or off (hamlib calls that 1 dB).
    static func level(_ decibels: Int) -> String {
        decibels == 0 ? "off" : decibels == 1 ? "on" : "\(decibels) dB"
    }

    // "AGC fast", "AGC 8".
    var agcText: String? {
        agc.map { Self.agcNames.indices.contains($0) ? Self.agcNames[$0] : "\($0)" }
    }

    // The offset the Offset control shows and changes: XIT's when only
    // XIT is on, otherwise RIT's.
    var offsetHertz: Int? { xitOn == true && ritOn != true ? xitHertz : ritHertz ?? xitHertz }
    var offsetCommand: String { xitOn == true && ritOn != true ? "Z" : "J" }

    // "VFO A, keyer 18 WPM, RIT on, XIT off, split off, AGC fast, preamp
    // off, attenuator 12 dB, NB off, NR on, APF off, dual watch off, RF
    // gain 100%". Only what the radio reports.
    var shown: String {
        func onOff(_ value: Bool?) -> String? { value.map { $0 ? "on" : "off" } }
        // A radio that can't say whether RIT is on: an offset means it is.
        func offset(_ hertz: Int?) -> String? {
            guard let hertz else { return nil }
            return hertz == 0 ? "off" : (hertz > 0 ? "+\(hertz) Hz" : "\(hertz) Hz")
        }
        let parts: [(String, String?)] = [
            ("VFO", vfo.flatMap { $0.hasPrefix("VFO") ? String($0.dropFirst(3)) : nil }),
            ("Keyer", keyerWPM.map { "\($0) WPM" }),
            ("RIT", onOff(ritOn) ?? offset(ritHertz)), ("XIT", onOff(xitOn) ?? offset(xitHertz)),
            ("split", onOff(split)), ("AGC", agcText),
            ("preamp", preampDB.map(Self.level)), ("attenuator", attenuatorDB.map(Self.level)),
            ("NB", onOff(noiseBlanker)), ("NR", onOff(noiseReduction)), ("APF", onOff(peakFilter)),
            ("dual watch", onOff(dualWatch)), ("RF gain", rfGain.map(Self.percent)),
            ("squelch", squelch.map(Self.percent)), ("volume", audioGain.map(Self.percent)),
        ]
        return parts.compactMap { name, value in value.map { "\(name) \($0)" } }.joined(separator: ", ")
    }
}
