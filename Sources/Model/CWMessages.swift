// CWMessages.swift
//
// The eight CW messages F1 to F8 send (through the WinKeyer), and the
// fill-ins they can use. Edited in Settings > CW. (Not for SKCC events:
// their rules require a mechanical key, so no keyer messages; the author, 17
// November 2026.)
//
// Fill-ins, in braces, any case:
//   {MYCALL}   your callsign, from the profile in use
//   {MYNAME}   your name, from Settings > CW
//   {MYSTATE}  your state, from the profile in use
//   {CALL}     the call in the form
//   {NAME}     their name, from the form or the lookup
//   {STATE}    their state, from the form or the lookup
//   {SKCC}     their SKCC number
//   {RST}      the report you're sending (RST sent), or 599 if it's empty
//   {SENT}     your exchange: the form's Exchange sent (STX_STRING), such
//              as Field Day's class and section, "1D MDC"
//   {NR}       your serial number for this contact: the form's Serial
//              sent, which counts itself (1, 2, 3 ... in this log for
//              this contest; LogEntryViewController.nextSerial)
// Each profile has its own messages (Settings.swift, Profile.cwMessages);
// a profile from the Field Day template starts with Field Day's.
// One with nothing to fill it is left out, so a message never sends
// "{NAME}" as letters. Foundation only, so tools/check-cw.sh can check it.

import Foundation

enum CWMessages {
    static let count = 8

    static let defaults = [
        "CQ CQ {MYCALL} {MYCALL} K",
        "{CALL} {RST} {MYNAME} {MYSTATE}",
        "TU {MYCALL}",
        "{MYCALL}",
        "{CALL}",
        "AGN?",
        "QRZ?",
        "73 {CALL} TU",
    ]

    // ARRL Field Day: CQ FD, the exchange (class and section, in Exchange
    // sent), and the usual short ones.
    static let fieldDay = [
        "CQ FD {MYCALL} {MYCALL} FD",
        "{CALL} {SENT}",
        "TU {MYCALL} FD",
        "{MYCALL}",
        "{CALL}",
        "AGN?",
        "QRZ?",
        "{SENT}",
    ]

    static let fillIns = ["MYCALL", "MYNAME", "MYSTATE", "CALL", "NAME", "STATE", "SKCC", "RST", "SENT", "NR"]

    // A message with its fill-ins filled from `values` (keyed by fill-in
    // name, upper case). Unknown or empty fill-ins are left out; spaces
    // are tidied after.
    static func expand(_ template: String, values: [String: String]) -> String {
        var out = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            out += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else {
                out += rest[open...]
                rest = ""
                break
            }
            let name = rest[rest.index(after: open)..<close].trimmingCharacters(in: .whitespaces).uppercased()
            out += values[name]?.trimmingCharacters(in: .whitespaces) ?? ""
            rest = rest[rest.index(after: close)...]
        }
        out += rest
        return out.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }
}
