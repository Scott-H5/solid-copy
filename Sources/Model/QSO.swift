// QSO.swift
//
// One logged contact ("QSO" is the ham abbreviation for a contact).
//
// Two things are special and kept as their own properties: the callsign
// (every contact must have one) and the date and time (kept as a moment
// in time, so it can be shown in UTC or local time).
//
// Every other field (name, band, grid square, SKCC number, notes, ...) is
// kept in `fields`, by its ADIF name in lower case. The full list of
// fields, with their labels, is in LogField.swift. ADIF (Amateur Data
// Interchange Format) is the standard file format for moving logs between
// programs, so using its names makes import and export simple and avoids
// losing data.

import Foundation

// Equatable lets the app tell whether an edit changed anything.
struct QSO: Equatable {
    // A unique identity for this contact, so it can be found again (for
    // example, to undo a delete) even if two contacts look the same.
    // Saved in the log, but not part of ADIF.
    var id = UUID()
    // ADIF: CALL
    var call: String
    // ADIF: QSO_DATE and TIME_ON. Always saved, shown and exported in
    // UTC, as ADIF requires.
    var timeOn: Date
    // All other fields, by lower-case ADIF name. Empty fields are left out.
    private(set) var fields: [String: String] = [:]

    init(id: UUID = UUID(), call: String, timeOn: Date,
         rstSent: String = "", rstReceived: String = "", comment: String = "",
         notes: String = "", fields: [String: String] = [:]) {
        self.id = id
        self.call = call
        self.timeOn = timeOn
        for (name, value) in fields { self[name] = value }
        self.rstSent = rstSent
        self.rstReceived = rstReceived
        self.comment = comment
        self.notes = notes
    }

    // A contact read back from the log file, whose fields were already
    // tidied when they were saved, so they're used as they are.
    init(id: UUID, call: String, timeOn: Date, storedFields: [String: String]) {
        self.id = id
        self.call = call
        self.timeOn = timeOn
        self.fields = storedFields
    }

    // Reads or changes a field by its ADIF name: qso["gridsquare"].
    // Reading a field that isn't set gives "". Setting "" removes it.
    subscript(field: String) -> String {
        get { fields[field] ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            fields[field] = trimmed.isEmpty ? nil : trimmed
        }
    }

    // Shortcuts for the fields the code uses most.
    // ADIF: NAME, the other operator's name.
    var name: String {
        get { self["name"] }
        set { self["name"] = newValue }
    }
    // ADIF: RST_SENT
    var rstSent: String {
        get { self["rst_sent"] }
        set { self["rst_sent"] = newValue }
    }
    // ADIF: RST_RCVD
    var rstReceived: String {
        get { self["rst_rcvd"] }
        set { self["rst_rcvd"] = newValue }
    }
    // ADIF: COMMENT. A short, one-line remark. Some services may show it
    // to others when the log is uploaded.
    var comment: String {
        get { self["comment"] }
        set { self["comment"] = newValue }
    }
    // ADIF: NOTES. Longer notes, for yourself. Always kept in the log and
    // its backups; left out of exports unless you ask for them.
    var notes: String {
        get { self["notes"] }
        set { self["notes"] = newValue }
    }

    // MARK: - Dates and times as text

    // For the screen: "2026-11-14", "1432" and "14:32:05".
    var utcDateText: String { Self.utcDate.string(from: timeOn) }
    var utcTimeText: String { Self.utcTime.string(from: timeOn) }
    var utcTimeWithSeconds: String { Self.utcTimeSeconds.string(from: timeOn) }

    // For the log file and ADIF: "20261114" and "143205".
    var adifDate: String { Self.adifDateFormat.string(from: timeOn) }
    var adifTime: String { Self.adifTimeFormat.string(from: timeOn) }

    // Turns ADIF's date and time back into a moment in time. ADIF allows
    // TIME_ON with or without seconds ("1432" or "143205"). Impossible
    // dates and times (30 February, 2561) give nil.
    //
    // Done with plain arithmetic rather than a date formatter: a log is
    // read with one of these per contact, and a formatter is many times
    // slower. (Days are counted with the well-known "days from civil"
    // method, which handles leap years.)
    static func date(adifDate: String, adifTime: String) -> Date? {
        let d = Array(adifDate.utf8), t = Array(adifTime.utf8)
        guard d.count == 8, t.count == 4 || t.count == 6,
              (d + t).allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        func number(_ digits: ArraySlice<UInt8>) -> Int { digits.reduce(0) { $0 * 10 + Int($1 - 48) } }
        let year = number(d[0..<4]), month = number(d[4..<6]), day = number(d[6..<8])
        let hour = number(t[0..<2]), minute = number(t[2..<4]), second = t.count == 6 ? number(t[4..<6]) : 0
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let monthDays = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard year >= 1900, (1...12).contains(month), day >= 1, day <= monthDays[month - 1],
              hour < 24, minute < 60, second < 60 else { return nil }
        let y = month <= 2 ? year - 1 : year
        let era = y / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let days = era * 146_097 + dayOfEra - 719_468
        return Date(timeIntervalSince1970: TimeInterval(days * 86_400 + hour * 3_600 + minute * 60 + second))
    }

    // Date formatters are slow to create, so these are made once and
    // shared. "en_US_POSIX" keeps the format fixed whatever your Mac's
    // language and region settings are.
    private static let utcDate = formatter("yyyy-MM-dd")
    private static let utcTime = formatter("HHmm")
    private static let utcTimeSeconds = formatter("HH:mm:ss")
    private static let adifDateFormat = formatter("yyyyMMdd")
    private static let adifTimeFormat = formatter("HHmmss")
    // ADIF's CREATED_TIMESTAMP form, "20261114 143205".
    static let adifTimestamp = formatter("yyyyMMdd HHmmss")
    // A plain UTC date for file names, "2026-11-14".
    static let fileDate = formatter("yyyy-MM-dd")

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }
}
