// WSJTXLogging.swift
//
// Contacts WSJT-X logs, into Solid Copy's log. When you log a contact in
// WSJT-X (its Log QSO window, or automatically if you've set that), it
// sends a Logged ADIF message: the contact as a small ADIF file. Solid
// Copy reads it with its own ADIF reader (ADIFImport.swift), so it
// arrives exactly as an imported contact would: call, grid, reports,
// band, frequency, mode (FT8, or MFSK with submode FT4), and times.
//
// WSJT-X also sends QSO Logged, the same contact field by field; only the
// ADIF one is used, so a contact is never added twice.
//
// What WSJT-X doesn't know comes from the profile in use, as for a
// contact logged on the form: your rig, county, park and so on. What
// WSJT-X did send is never replaced.
//
// The app adds them (AppDelegate.loggedFromWSJTX): skipping one already in
// the log, then the usual uploads and a spoken "Logged".

import Foundation

enum WSJTXLogging {
    // The contacts in one Logged ADIF message, with the profile's station
    // fields filling in what WSJT-X left empty. Empty if it holds none.
    static func contacts(from adif: String, station: [String: String]) -> [QSO] {
        ADIFImport.read(Data(adif.utf8)).contacts.map { qso in
            var qso = qso
            for (field, value) in station where qso[field].isEmpty && !value.isEmpty {
                qso[field] = value
            }
            return qso
        }
    }

    // "Logged KJ5IUY from WSJT-X." (several: "Logged 2 contacts from
    // WSJT-X."), and the ones already in the log.
    static func spoken(added: [QSO], skipped: Int) -> String {
        var parts: [String] = []
        if added.count == 1, let call = added.first?.call {
            parts.append("Logged \(call) from WSJT-X.")
        } else if added.count > 1 {
            parts.append("Logged \(added.count) contacts from WSJT-X.")
        }
        if skipped > 0 {
            parts.append(skipped == 1 ? "WSJT-X logged a contact that's already in the log, so it wasn't added again."
                                      : "\(skipped) contacts from WSJT-X were already in the log.")
        }
        return parts.joined(separator: " ")
    }
}
