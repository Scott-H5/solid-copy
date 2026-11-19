// ADIFLocation.swift
//
// Converts latitude and longitude between the two ways they're written.
//
// Solid Copy keeps them as decimal degrees ("43.604166", "-116.375"), which
// is what SQL log files store and what maps and distance sums use. ADIF
// writes them as a hemisphere letter, three-digit degrees and minutes:
// "N043 36.250" and "W116 22.500".

import Foundation

enum ADIFLocation {
    // Decimal degrees to ADIF: 43.604166 -> "N043 36.250".
    static func adif(fromDecimal text: String, isLatitude: Bool) -> String {
        guard let value = Double(text) else { return text }
        let hemisphere = isLatitude ? (value < 0 ? "S" : "N") : (value < 0 ? "W" : "E")
        var degrees = Int(abs(value))
        // Minutes to three decimal places (about 2 metres).
        var minutes = ((abs(value) - Double(degrees)) * 60 * 1000).rounded() / 1000
        if minutes >= 60 {
            degrees += 1
            minutes -= 60
        }
        return String(format: "%@%03d %06.3f", hemisphere, degrees, minutes)
    }

    // ADIF to decimal degrees: "N043 36.250" -> "43.604167". Text that
    // isn't in ADIF form (already decimal, say) is returned unchanged.
    static func decimal(fromADIF text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let letter = trimmed.first, "NSEWnsew".contains(letter) else { return trimmed }
        let parts = trimmed.dropFirst().split(separator: " ")
        guard parts.count == 2, let degrees = Double(parts[0]), let minutes = Double(parts[1]) else {
            return trimmed
        }
        var value = degrees + minutes / 60
        if "SWsw".contains(letter) { value = -value }
        return String(format: "%.6f", value)
    }
}
