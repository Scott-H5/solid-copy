// Callsign.swift
//
// Small helpers for amateur radio callsigns.

import Foundation

enum Callsign {
    // Tidies what was typed: removes spaces and makes it upper case.
    static func normalized(_ text: String) -> String {
        text.filter { !$0.isWhitespace }.uppercased()
    }

    // A loose check that the text could be a callsign: at least three
    // characters, only letters, digits and "/" (as in W1AW/P or VE3/W1AW),
    // with at least one letter and one digit. Deliberately loose, so
    // unusual calls aren't rejected; the online lookup is the real check.
    static func looksValid(_ call: String) -> Bool {
        guard call.count >= 3 else { return false }
        let allowed = call.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "/" }
        return allowed && call.contains(where: \.isLetter) && call.contains(where: \.isNumber)
    }

    // How a callsign should be spoken: letter by letter, "W 1 A W".
    // VoiceOver otherwise tries to read calls as words (contract, rule 10).
    // "/" is spoken as "stroke", as hams say it on the air.
    static func spoken(_ call: String) -> String {
        call.map { $0 == "/" ? "stroke" : String($0) }.joined(separator: " ")
    }
}
