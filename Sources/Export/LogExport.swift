// LogExport.swift
//
// Writes the log in other programs' formats. Each format turns a list of
// contacts into the bytes of a file; the app's Export command (in
// ImportExport.swift) asks where to save it.
//
// Formats so far:
//   - ADIF (.adi): the standard exchange format. See ADIFImport.swift for
//     what it looks like.
//   - ADX (.adx): the same fields as ADIF, written as XML (ADIF's own
//     second form). Some programs and services take only one of the two.
//   - CSV (.csv): a spreadsheet, one row per contact, with ADIF field
//     names as the column headings.
//
// Notes (ADIF NOTES) are private, so they're left out unless you ask for
// them. Everything else is always included.

import Foundation

enum ExportFormat: CaseIterable {
    case adif
    case adx
    case csv
    // Calls worked by band and mode, what ARRL Field Day asks for
    // (Contest.dupeSheet). The Export command adds the contest's name.
    case dupeSheet
    // The contest's Cabrillo log (Contest.cabrillo). The Export command
    // writes it with the contest in use, so data(for:) has nothing here.
    case cabrillo

    // The name shown in the Export dialog's Format menu.
    var title: String {
        switch self {
        case .adif: return "ADIF (.adi)"
        case .adx: return "ADX, ADIF as XML (.adx)"
        case .csv: return "CSV spreadsheet (.csv)"
        case .dupeSheet: return "Dupe sheet, calls by band and mode (.txt)"
        case .cabrillo: return "Cabrillo, for a contest entry (.log)"
        }
    }

    var fileExtension: String {
        switch self {
        case .adif: return "adi"
        case .adx: return "adx"
        case .csv: return "csv"
        case .dupeSheet: return "txt"
        case .cabrillo: return "log"
        }
    }

    func data(for contacts: [QSO], includeNotes: Bool) -> Data {
        switch self {
        case .adif: return LogExport.adif(contacts, includeNotes: includeNotes)
        case .adx: return LogExport.adx(contacts, includeNotes: includeNotes)
        case .csv: return LogExport.csv(contacts, includeNotes: includeNotes)
        case .dupeSheet: return Data(Contest.dupeSheet(contacts, contestName: "Log", myCall: "").utf8)
        case .cabrillo: return Data()
        }
    }
}

enum LogExport {

    // The fields written, in order: every field in LogField.swift, less
    // Notes if they're not wanted.
    private static func fields(includeNotes: Bool) -> [LogField] {
        LogField.all.filter { includeNotes || $0.adif != "notes" }
    }

    // MARK: - ADIF

    static func adif(_ contacts: [QSO], includeNotes: Bool) -> Data {
        var text = "Exported from Solid Copy\n"
        text += header().map { tag($0.name, $0.value) }.joined() + "<EOH>\n\n"
        let fields = fields(includeNotes: includeNotes)
        for qso in contacts { text += record(qso, fields: fields) + "\n" }
        return Data(text.utf8)
    }

    // The header fields ADIF and ADX both start with.
    private static func header() -> [(name: String, value: String)] {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return [("ADIF_VER", "3.1.5"), ("PROGRAMID", "Solid Copy"), ("PROGRAMVERSION", version),
                ("CREATED_TIMESTAMP", QSO.adifTimestamp.string(from: Date()))]
    }

    // One contact as an ADIF record, ending <EOR>, with no header: what
    // QRZ Logbook takes (QRZLogbook.swift). Leaves out Notes and Solid
    // Copy's own fields (the card's file and its text), which are yours.
    static func adifRecord(_ qso: QSO) -> String {
        record(qso, fields: fields(includeNotes: false).filter { !$0.adif.hasPrefix("app_") })
    }

    private static func record(_ qso: QSO, fields: [LogField]) -> String {
        values(qso, fields: fields).map { tag($0.name, $0.value) }.joined() + "<EOR>"
    }

    // A contact's fields as ADIF writes them, upper-case names first:
    // CALL, QSO_DATE and TIME_ON, then every field that has a value.
    // Shared by ADIF and ADX, so the two always carry the same.
    private static func values(_ qso: QSO, fields: [LogField]) -> [(name: String, value: String, multiline: Bool)] {
        var out = [("CALL", qso.call, false), ("QSO_DATE", qso.adifDate, false), ("TIME_ON", qso.adifTime, false)]
        for field in fields {
            var value = qso[field.adif]
            guard !value.isEmpty else { continue }
            switch field.adif {
            case "lat": value = ADIFLocation.adif(fromDecimal: value, isLatitude: true)
            case "lon": value = ADIFLocation.adif(fromDecimal: value, isLatitude: false)
            default: break
            }
            // ADIF writes line breaks as CR LF.
            if field.multiline {
                value = value.replacingOccurrences(of: "\n", with: "\r\n")
            }
            out.append((field.adif.uppercased(), value, field.multiline))
        }
        return out
    }

    // One field: <NAME:LENGTH>VALUE, then a space. LENGTH is in bytes of
    // UTF-8 (see ADIFImport.swift for why).
    private static func tag(_ name: String, _ value: String) -> String {
        "<\(name):\(value.utf8.count)>\(value) "
    }

    // MARK: - ADX

    // ADX is ADIF as XML (ADIF specification, "ADX File Format"):
    //
    //   <?xml version="1.0" encoding="UTF-8"?>
    //   <ADX>
    //     <HEADER> <ADIF_VER>3.1.5</ADIF_VER> ... </HEADER>
    //     <RECORDS>
    //       <RECORD>
    //         <CALL>W1AW</CALL> <QSO_DATE>20261114</QSO_DATE> ...
    //         <APP PROGRAMID="SOLIDCOPY" FIELDNAME="LICW" TYPE="S">1234</APP>
    //       </RECORD>
    //     </RECORDS>
    //   </ADX>
    //
    // Each field is an element named after it, with the same value ADIF
    // would hold. A program's own field (ADIF's APP_SOLIDCOPY_LICW) is an
    // APP element naming the program and the field. Reading it back is
    // ADXImport.swift.
    static func adx(_ contacts: [QSO], includeNotes: Bool) -> Data {
        var text = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ADX>\n  <HEADER>\n"
        for item in header() { text += "    " + element(item.name, item.value, multiline: false) + "\n" }
        text += "  </HEADER>\n  <RECORDS>\n"
        let fields = fields(includeNotes: includeNotes)
        for qso in contacts {
            text += "    <RECORD>\n"
            for item in values(qso, fields: fields) {
                text += "      " + element(item.name, item.value, multiline: item.multiline) + "\n"
            }
            text += "    </RECORD>\n"
        }
        return Data((text + "  </RECORDS>\n</ADX>\n").utf8)
    }

    // <NAME>value</NAME>, or for APP_PROGRAM_FIELD an APP element. A
    // program ID can't hold "_" (ADIF's rule), so the first "_" after
    // APP_ ends it: APP_SOLIDCOPY_CARD_TEXT is SOLIDCOPY's CARD_TEXT.
    private static func element(_ name: String, _ value: String, multiline: Bool) -> String {
        let value = xmlEscaped(value)
        if name.hasPrefix("APP_") {
            let rest = name.dropFirst(4)
            if let cut = rest.firstIndex(of: "_") {
                let program = rest[..<cut], field = rest[rest.index(after: cut)...]
                return "<APP PROGRAMID=\"\(xmlEscaped(String(program)))\" FIELDNAME=\"\(xmlEscaped(String(field)))\" "
                    + "TYPE=\"\(multiline ? "M" : "S")\">\(value)</APP>"
            }
        }
        return "<\(name)>\(value)</\(name)>"
    }

    // Text made safe for XML. & < > and " become entities. A CR becomes
    // &#13;, because an XML reader would otherwise turn CR LF into LF and
    // ADIF's line breaks are CR LF. Other control characters are left
    // out: XML 1.0 can't hold them at all, not even as &#NN;.
    static func xmlEscaped(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "\r": out += "&#13;"
            case "\t", "\n": out.unicodeScalars.append(scalar)
            default:
                if scalar.value < 0x20 || scalar.value == 0xFFFE || scalar.value == 0xFFFF { continue }
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    // MARK: - CSV

    static func csv(_ contacts: [QSO], includeNotes: Bool) -> Data {
        let fields = fields(includeNotes: includeNotes)
        var rows = [(["CALL", "QSO_DATE", "TIME_ON"] + fields.map { $0.adif.uppercased() })]
        for qso in contacts {
            rows.append([qso.call, qso.adifDate, qso.adifTime] + fields.map { qso[$0.adif] })
        }
        let text = rows.map { $0.map(csvCell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
        return Data(text.utf8)
    }

    // Quotes a cell if it contains a comma, quote mark or line break, as
    // spreadsheets expect, doubling any quote marks inside.
    private static func csvCell(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
