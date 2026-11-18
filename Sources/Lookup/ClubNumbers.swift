// ClubNumbers.swift
//
// Club membership numbers for a call, to fill in on the form: SKCC,
// FISTS, LICW, CWops and your own club fields (LogField.clubNumberFields).
// A member keeps their number, so:
//   1. SKCC comes from SKCC's own member list (SKCCRoster.swift) when it
//      knows the call: it's the authority, and it has the newest award
//      letter (12345C becomes 12345T).
//   2. Your own club fields can have a member list from a file
//      (ClubLists.swift); its number wins, as SKCC's does.
//   3. Everything else comes from your log: the newest contact with the
//      same call that has the number. FISTS and LICW publish no lists,
//      so this is how they get filled; work a regular once, and their
//      number is there next time.
// Calls match by their main part (W1AW/P is W1AW). It's all local, so it's
// instant, and it works with lookups off.

import Foundation

@MainActor
enum ClubNumbers {
    static func numbers(for call: String, in contacts: [QSO]) -> [String: String] {
        let key = CallsignLookup.lookupCall(for: Callsign.normalized(call))
        guard !key.isEmpty else { return [:] }
        var found: [String: String] = [:]
        var missing = Set(LogField.clubNumberFields)
        // Newest first; stop once every field has a value.
        for qso in contacts.reversed() where !missing.isEmpty {
            guard CallsignLookup.lookupCall(for: qso.call) == key else { continue }
            for field in missing where !qso[field].trimmingCharacters(in: .whitespaces).isEmpty {
                found[field] = qso[field].trimmingCharacters(in: .whitespaces)
                missing.remove(field)
            }
        }
        if let skcc = SKCCRoster.shared.number(for: key) { found["skcc"] = skcc }
        // A member list from a file, for a named club field of your own, wins
        // too: it's the club's own list (ClubLists.swift).
        for slot in 1...LogField.clubSlots where !ClubNames.name(slot).isEmpty {
            if let number = ClubLists.number(slot: slot, for: key) { found["app_solidcopy_club\(slot)"] = number }
        }
        return found
    }

    // "SKCC 12345T, FISTS 9876", for the lookup line, in the field list's
    // order. Empty if there are none.
    static func shown(_ numbers: [String: String]) -> String {
        LogField.clubNumberFields.compactMap { field in
            numbers[field].map { "\(shortName(field)) \($0)" }
        }.joined(separator: ", ")
    }

    // The same, for speech: "SKCC 12345 Tribune, FISTS 9876".
    static func spoken(_ numbers: [String: String]) -> String {
        LogField.clubNumberFields.compactMap { field in
            numbers[field].map { "\(shortName(field)) \(field == "skcc" ? SKCCRoster.spoken($0) : $0)" }
        }.joined(separator: ", ")
    }

    // "SKCC", "FISTS", ... or your club field's name without a trailing
    // "number" ("NAQCC number" -> "NAQCC").
    static func shortName(_ field: String) -> String {
        let label = LogField.named(field)?.label ?? field
        for ending in [" number", " Number", " #"] where label.hasSuffix(ending) && label.count > ending.count {
            return String(label.dropLast(ending.count))
        }
        return label
    }
}
