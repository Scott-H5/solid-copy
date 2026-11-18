// ADIFImport.swift
//
// Reads an ADIF file (.adi or .adif): the standard format for moving logs
// between ham radio programs.
//
// What an ADIF file looks like:
//
//   Some header text, which can say anything.
//   <ADIF_VER:5>3.1.5 <PROGRAMID:10>Solid Copy <EOH>
//   <CALL:4>W1AW <QSO_DATE:8>20261114 <TIME_ON:6>143205 <NAME:5>Hiram <EOR>
//   <CALL:5>K1ABC ... <EOR>
//
// Each field is <NAME:LENGTH>VALUE. The LENGTH says how many bytes of value
// follow, so a value can safely contain "<" or ">". <EOH> ends the header
// (a file that starts with "<" has no header) and <EOR> ends each contact.
// Field names can be in any case.
//
// Lengths are counted in bytes of UTF-8 text. ADIF's own rules say
// characters, and say plain ADI files are ASCII only, but most programs
// write UTF-8 and count bytes (WSJT-X, for example). For ordinary English
// letters the two are the same. Solid Copy writes and reads bytes, so its
// own files always round-trip, accents included.

import Foundation

enum ADIFImport {

    // Whether a file looks like ADIF: it mentions <EOH> or a CALL field.
    static func looksLikeADIF(_ data: Data) -> Bool {
        let start = String(decoding: data.prefix(64 * 1024), as: UTF8.self).lowercased()
        return start.contains("<eoh>") || start.contains("<call:")
    }

    // Reads every contact in an ADIF file. `leftOut` lists the names of
    // fields Solid Copy doesn't have yet, which weren't imported.
    static func read(_ data: Data) -> (contacts: [QSO], unreadable: Int, leftOut: [String]) {
        var contacts: [QSO] = []
        var unreadable = 0
        var leftOut = Set<String>()
        for record in records(in: data) {
            if let qso = contact(from: record, leftOut: &leftOut) {
                contacts.append(qso)
            } else {
                unreadable += 1
            }
        }
        return (contacts, unreadable, leftOut.sorted())
    }

    // Splits a file into contacts, each a dictionary of lower-case field
    // name to value.
    static func records(in data: Data) -> [[String: String]] {
        let bytes = [UInt8](data)
        let open = UInt8(ascii: "<"), close = UInt8(ascii: ">")
        // A file that doesn't start with "<" has a header to skip first.
        var inHeader = bytes.first(where: { $0 != 0x20 && $0 != 0x0A && $0 != 0x0D && $0 != 0xEF
            && $0 != 0xBB && $0 != 0xBF }) != open
        var records: [[String: String]] = []
        var record: [String: String] = [:]
        var index = 0

        while let tagStart = bytes[index...].firstIndex(of: open),
              let tagEnd = bytes[(tagStart + 1)...].firstIndex(of: close) {
            let tag = String(decoding: bytes[(tagStart + 1)..<tagEnd], as: UTF8.self)
            let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
            let name = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            index = tagEnd + 1

            switch name {
            case "eoh":
                inHeader = false
                record = [:]
            case "eor":
                if !inHeader, !record.isEmpty { records.append(record) }
                record = [:]
            default:
                // <NAME:LENGTH> or <NAME:LENGTH:TYPE>. Take exactly LENGTH
                // bytes after the tag.
                guard parts.count >= 2, let length = Int(parts[1].trimmingCharacters(in: .whitespaces)),
                      length >= 0 else { continue }
                let end = min(index + length, bytes.count)
                if !inHeader {
                    record[name] = String(decoding: bytes[index..<end], as: UTF8.self)
                }
                index = end
            }
        }
        return records
    }

    // Turns one ADIF record into a contact, or nil without a call, date
    // and time.
    static func contact(from record: [String: String], leftOut: inout Set<String>) -> QSO? {
        let call = Callsign.normalized(record["call"] ?? "")
        guard !call.isEmpty,
              let timeOn = QSO.date(adifDate: record["qso_date"] ?? "", adifTime: record["time_on"] ?? "")
        else { return nil }
        var qso = QSO(call: call, timeOn: timeOn)

        for (name, value) in record where !["call", "qso_date", "time_on"].contains(name) {
            guard let field = LogField.named(name) else {
                if !value.isEmpty { leftOut.insert(name.uppercased()) }
                continue
            }
            var value = value
            switch name {
            case "lat", "lon", "my_lat", "my_lon":
                value = ADIFLocation.decimal(fromADIF: value)
            case "band", "band_rx":
                value = value.lowercased()
            default:
                break
            }
            // ADIF writes line breaks as CR LF; Solid Copy keeps just LF.
            if field.multiline {
                value = value.replacingOccurrences(of: "\r\n", with: "\n")
            }
            qso[name] = value
        }
        return qso
    }
}
