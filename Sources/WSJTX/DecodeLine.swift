// DecodeLine.swift
//
// What the WSJT-X Decodes window says for each decode, and its status
// line (DecodesWindowController.swift). Kept apart from the window so
// tools/check-wsjtx.sh can test the wording.

import Foundation

// The words for one decode and for the status line. No windows here, so
// the check (tools/check-wsjtx.sh) can test them.
@MainActor
enum DecodeLine {
    static func isToMe(_ words: FT8Text, myCall: String) -> Bool {
        !myCall.isEmpty && Callsign.normalized(words.to.trimmingCharacters(in: CharacterSet(charactersIn: "<>")))
            == Callsign.normalized(myCall)
    }

    static func line(for decode: WSJTXDecode, words: FT8Text?, myCall: String, country: String? = nil,
                     needed: String? = nil, workedBefore: Bool = false) -> String {
        let signal = "\(decode.snr) dB, \(decode.timeText)"
        guard let words else { return "\(decode.text), \(signal)" }
        var parts: [String]
        if words.isCQ {
            parts = ["\(words.from) calling CQ" + (words.cqTo.isEmpty ? "" : " \(words.cqTo)")]
            if let country { parts.append(country) }
            if let grid = words.grid { parts.append("grid \(grid)") }
        } else if isToMe(words, myCall: myCall) {
            parts = ["To you, from \(words.from)" + (words.exchange.isEmpty ? "" : ": \(words.exchange)")]
            if let country { parts.append(country) }
        } else {
            parts = ["\(words.from) to \(words.to)" + (words.exchange.isEmpty ? "" : ": \(words.exchange)")]
            if let country { parts.append(country) }
        }
        parts.append(signal)
        if let needed { parts.append(needed) } else if workedBefore { parts.append("worked before") }
        if decode.lowConfidence { parts.append("low confidence") }
        return parts.joined(separator: ", ")
    }

    // "WSJT-X 3.0.1: 14.074 megahertz, FT8, transmitting. 18 of 40 decodes."
    static func status(listener: WSJTXListener, shown: Int, total: Int) -> String {
        if let problem = listener.problem { return problem }
        guard let heard = listener.lastHeard else {
            return "Waiting for WSJT-X. Start it, and in its Settings > Reporting, set UDP Server to 127.0.0.1 "
                + "and port 2237 (its usual settings)."
        }
        var text = "WSJT-X" + (listener.version.map { " \($0)" } ?? "")
        if let status = listener.status {
            text += ": " + RadioReading(hertz: Int(status.dialHertz), mode: status.mode).megahertzText + " megahertz, " + status.mode
            if status.transmitting { text += ", transmitting" }
        }
        text += ". " + (shown == total ? "\(total) decode\(total == 1 ? "" : "s")." : "\(shown) of \(total) decodes.")
        if Date().timeIntervalSince(heard) > 60 { text += " Nothing heard from WSJT-X for a minute: is it still running?" }
        return text
    }
}
