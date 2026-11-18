// LogImport.swift
//
// The one place that reads a log file from another program. It looks at
// the file to see what it is, and hands it to the right reader:
//   - an SQLite database (it starts with "SQLite format 3") is read as a
//     MacLoggerDX log (MacLoggerDXImport.swift);
//   - XML with an <ADX> element is read as ADX (ADXImport.swift). It's
//     checked before ADIF, since an ADX file can mention ADIF's tags;
//   - text with ADIF fields is read as ADIF (ADIFImport.swift).
// To support another format, add a reader and a check for it here.
//
// Looking at the contents, not just the name, means a file still imports
// correctly if its name ends in something unexpected (.txt, say).

import Foundation

enum LogImport {

    struct Result {
        // What kind of file it was, for the summary ("ADIF file").
        var format: String
        // The contacts read, oldest first.
        var contacts: [QSO]
        // Records that couldn't be read (no callsign, or no date and time).
        var unreadable: Int
        // Contacts that repeat another's call and time exactly, as "CALL on
        // date at time UTC". They're imported as they are.
        var repeated: [String]
        // Fields in the file that Solid Copy doesn't have yet, which
        // weren't imported (ADIF names, such as "MY_ANTENNA").
        var leftOut: [String]
    }

    static func read(from url: URL) throws -> Result {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)

        if data.starts(with: Array("SQLite format 3\u{0}".utf8)) {
            let log = try MacLoggerDXImport.read(from: url)
            return Result(format: "MacLoggerDX log", contacts: log.contacts, unreadable: log.unreadable,
                          repeated: repeats(in: log.contacts), leftOut: [])
        }
        if ADXImport.looksLikeADX(data) {
            let log = try ADXImport.read(data)
            let contacts = log.contacts.sorted { $0.timeOn < $1.timeOn }
            return Result(format: "ADX file", contacts: contacts, unreadable: log.unreadable,
                          repeated: repeats(in: contacts), leftOut: log.leftOut)
        }
        if ADIFImport.looksLikeADIF(data) {
            let log = ADIFImport.read(data)
            let contacts = log.contacts.sorted { $0.timeOn < $1.timeOn }
            return Result(format: "ADIF file", contacts: contacts, unreadable: log.unreadable,
                          repeated: repeats(in: contacts), leftOut: log.leftOut)
        }
        throw DatabaseError(message: "Solid Copy can import ADIF files (.adi or .adif), ADX files (.adx) and "
            + "MacLoggerDX logs (.sql). This file doesn't look like any of them.")
    }

    // Contacts with exactly the same call and time (to the second) as an
    // earlier one in the same file.
    static func repeats(in contacts: [QSO]) -> [String] {
        var seen: [String: Int] = [:]
        var repeated: [String] = []
        for qso in contacts {
            let key = "\(qso.call)|\(Int(qso.timeOn.timeIntervalSince1970))"
            seen[key, default: 0] += 1
            if seen[key] == 2 {
                repeated.append("\(qso.call) on \(qso.utcDateText) at \(qso.utcTimeText) UTC")
            }
        }
        return repeated
    }
}
