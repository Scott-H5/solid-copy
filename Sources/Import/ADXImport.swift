// ADXImport.swift
//
// Reads an ADX file: ADIF written as XML (ADIF specification, "ADX File
// Format"). What one looks like is in LogExport.swift, which writes them.
// In short: <ADX>, a <HEADER>, then <RECORDS> holding one <RECORD> per
// contact, each field an element named after its ADIF field:
//
//   <RECORD><CALL>W1AW</CALL><QSO_DATE>20261114</QSO_DATE>...</RECORD>
//
// Two kinds of field are elements with attributes instead:
//   - <APP PROGRAMID="SOLIDCOPY" FIELDNAME="LICW">: a program's own
//     field, read as ADIF's app_solidcopy_licw;
//   - <USERDEF FIELDNAME="EPC">: a field the log's owner made up. Solid
//     Copy has none of those, so they're reported as left out
//     ("USERDEF_EPC"), never mistaken for a field of the same name.
// Each record then goes through ADIFImport.contact, so ADX and ADIF are
// read by the very same rules (bands, latitude, line breaks, and so on).
//
// Safety: Apple's XMLParser reads the file, with no outside code. A file
// with a DOCTYPE is refused before parsing: ADX never needs one, and a
// DOCTYPE is how a hostile XML file declares entities that expand into
// gigabytes or point at other files. A file that isn't valid XML is
// refused whole, saying the line, rather than half imported.

import Foundation

enum ADXImport {

    // Whether a file looks like ADX: an <ADX> element near the start.
    static func looksLikeADX(_ data: Data) -> Bool {
        String(decoding: data.prefix(4096), as: UTF8.self).lowercased().contains("<adx")
    }

    // Reads every contact, as ADIFImport.read does.
    static func read(_ data: Data) throws -> (contacts: [QSO], unreadable: Int, leftOut: [String]) {
        var contacts: [QSO] = []
        var unreadable = 0
        var leftOut = Set<String>()
        for record in try records(in: data) {
            if let qso = ADIFImport.contact(from: record, leftOut: &leftOut) {
                contacts.append(qso)
            } else {
                unreadable += 1
            }
        }
        return (contacts, unreadable, leftOut.sorted())
    }

    // Each <RECORD> as a dictionary of lower-case ADIF name to value.
    static func records(in data: Data) throws -> [[String: String]] {
        for marker in ["<!DOCTYPE", "<!doctype", "<!ENTITY", "<!entity"] where data.range(of: Data(marker.utf8)) != nil {
            throw DatabaseError(message: "This ADX file declares a DOCTYPE, which ADX files never need, so "
                                + "Solid Copy won't read it.")
        }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        let reader = ADXReader()
        parser.delegate = reader
        guard parser.parse() else {
            throw DatabaseError(message: "This ADX file isn't valid XML (line \(parser.lineNumber)), so nothing "
                                + "was imported. The program that wrote it may have stopped partway.")
        }
        return reader.records
    }
}

// Walks the XML. Only elements exactly three deep in the right place,
// ADX > RECORDS > RECORD > field, are fields; anything else (the header,
// stray elements, whitespace between fields) is passed over. Element
// names are matched in any case, as ADIF's are.
private final class ADXReader: NSObject, XMLParserDelegate {
    var records: [[String: String]] = []
    private var path: [String] = []           // the open elements, upper-case
    private var record: [String: String]?     // the RECORD being read
    private var field: String?                // its field being read, ADIF name
    private var value = ""

    private var inRecord: Bool { path.count == 3 && path == ["ADX", "RECORDS", "RECORD"] }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        let wasInRecord = inRecord
        path.append(elementName.uppercased())
        if inRecord {
            record = [:]
        } else if wasInRecord {
            field = name(of: path[3], attributes: attributes)
            value = ""
        }
    }

    // A field's ADIF name, lower-case; nil for an APP or USERDEF missing
    // its names (skipped).
    private func name(of element: String, attributes: [String: String]) -> String? {
        var upper: [String: String] = [:]
        for (key, value) in attributes { upper[key.uppercased()] = value }
        switch element {
        case "APP":
            guard let program = upper["PROGRAMID"], let name = upper["FIELDNAME"],
                  !program.isEmpty, !name.isEmpty else { return nil }
            return "app_\(program)_\(name)".lowercased()
        case "USERDEF":
            guard let name = upper["FIELDNAME"], !name.isEmpty else { return nil }
            return "userdef_\(name)".lowercased()
        default:
            return element.lowercased()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if path.count == 4, field != nil { value += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if path.count == 4, field != nil { value += String(decoding: CDATABlock, as: UTF8.self) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName: String?) {
        if path.count == 4, let field {
            record?[field] = value
            self.field = nil
        } else if inRecord {
            if let record, !record.isEmpty { records.append(record) }
            record = nil
        }
        path.removeLast()
    }
}
