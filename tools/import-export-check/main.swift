// tools/import-export-check/main.swift
//
// Checks importing and exporting, using a real MacLoggerDX log:
//   1. imports it into a throwaway Solid Copy log (the original is only
//      read) and reports how many contacts have each field;
//   2. exports those contacts as ADIF, imports that ADIF into a second
//      throwaway log, and checks every contact comes back the same, field
//      for field;
//   3. does the same through ADX (ADIF as XML), notes and Solid Copy's
//      own APP fields included;
//   4. checks some awkward ADIF and ADX by hand: accents, no header, a
//      field Solid Copy doesn't have, hostile files, and the CSV
//      export's quoting.
//
// Run it with:  bash tools/check-import-export.sh [path to MacLoggerDX.sql]

import Foundation

MainActor.assumeIsolated {
    let source = URL(fileURLWithPath: CommandLine.arguments[1])
    let work = URL(fileURLWithPath: CommandLine.arguments[2])
    func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }
    @MainActor func freshLog(_ name: String) throws -> Logbook {
        try Logbook(database: LogDatabase(fileURL: work.appendingPathComponent(name)))
    }
    do {
        // 1. MacLoggerDX.
        let before = try FileManager.default.attributesOfItem(atPath: source.path)[.modificationDate] as? Date
        let result = try LogImport.read(from: source)
        check(result.format == "SQL log file", "recognised as an SQL log file")
        print("     \(result.contacts.count) contacts; \(result.unreadable) unreadable; repeated: \(result.repeated.joined(separator: "; "))")
        let logbook = try freshLog("FromMLDX.sqlite")
        let first = try logbook.importContacts(result.contacts)
        check(first.added.count == result.contacts.count, "imports all \(first.added.count)")
        check(try logbook.importContacts(result.contacts).added.isEmpty, "importing again adds nothing")
        let after = try FileManager.default.attributesOfItem(atPath: source.path)[.modificationDate] as? Date
        check(before == after, "the MacLoggerDX file wasn't changed")
        // QSLs: cards, LoTW and QRZ Logbook, from MacLoggerDX's QSL text.
        // (Counts are for the author's log; another log just reports them.)
        let imported = logbook.contacts
        func count(_ field: String) -> Int { imported.filter { $0[field] == "Y" }.count }
        let qsls = "cards \(count("qsl_rcvd")), LoTW \(count("lotw_qsl_rcvd")), QRZ confirmed "
            + "\(count("qrzcom_qso_download_status")), QRZ uploaded \(count("qrzcom_qso_upload_status"))"
        if source.path.hasSuffix("MLDX_Logs/MacLoggerDX.sql") {
            check(qsls == "cards 85, LoTW 11, QRZ confirmed 5, QRZ uploaded 71", "QSLs kept: \(qsls)")
            check(imported.allSatisfy { $0["qsl_rcvd"] != "Y" || $0["qslrdate"] == "20251217" }
                  && imported.allSatisfy { $0["qsl_sent"].isEmpty }, "cards dated when entered; none taken as sent")
        } else {
            print("     QSLs: " + qsls)
        }

        // 2 and 3. ADIF and ADX round trips, notes included: every field
        // of every contact must come back the same.
        @MainActor func roundTrip(_ format: ExportFormat, _ name: String) throws {
            let url = work.appendingPathComponent("export." + format.fileExtension)
            try format.data(for: logbook.contacts, includeNotes: true).write(to: url)
            let back = try LogImport.read(from: url)
            check(back.format == "\(name) file" && back.unreadable == 0 && back.leftOut.isEmpty,
                  "the exported \(name) reads back with nothing unreadable or left out")
            let second = try freshLog("From\(name).sqlite")
            _ = try second.importContacts(back.contacts)
            check(second.contacts.count == logbook.contacts.count, "same number of contacts after the \(name) round trip")
            var differences: [String] = []
            for (a, b) in zip(logbook.contacts, second.contacts) {
                if a.call != b.call || a.timeOn != b.timeOn { differences.append("\(a.call): call or time"); continue }
                for field in LogField.all where a[field.adif] != b[field.adif] {
                    // Latitude and longitude pass through ADIF's minutes form,
                    // so allow a tiny rounding difference (about 2 metres).
                    if ["lat", "lon"].contains(field.adif), let x = Double(a[field.adif]), let y = Double(b[field.adif]),
                       abs(x - y) < 0.0001 { continue }
                    differences.append("\(a.call) \(field.adif): '\(a[field.adif])' became '\(b[field.adif])'")
                }
            }
            differences.prefix(10).forEach { print("     " + $0) }
            check(differences.isEmpty, "every field of every contact survives MacLoggerDX → \(name) → Solid Copy")
        }
        try roundTrip(.adif, "ADIF")
        // the author's log has no Solid Copy APP fields or multi-line text worth
        // trusting to luck, so give the first contact some before ADX:
        // line breaks, XML's own characters, and an APP field.
        if var first = logbook.contacts.first {
            first["notes"] = "Line one & <two>\nLine \"three\""
            first["app_solidcopy_licw"] = "1234"
            first["app_solidcopy_card_text"] = "73, see you\non 40 m"
            _ = try logbook.update(first)
        }
        try roundTrip(.adx, "ADX")

        // Notes are left out unless asked for.
        var withNotes = QSO(call: "W1AW", timeOn: Date(timeIntervalSince1970: 1794666725), notes: "private")
        withNotes["comment"] = "public"
        let noNotes = String(decoding: ExportFormat.adif.data(for: [withNotes], includeNotes: false), as: UTF8.self)
        check(!noNotes.contains("private") && noNotes.contains("public"), "Notes are left out unless asked for")

        // 3. Awkward ADIF, written by hand.
        // No header, lower-case names, accents (lengths counted in UTF-8
        // bytes), and a field Solid Copy doesn't have.
        func field(_ name: String, _ value: String) -> String { "<\(name):\(value.utf8.count)>\(value)" }
        let handmade = field("call", "F5ÉÉ") + field("qso_date", "20261114") + field("time_on", "1432")
            + field("name", "Ségolène") + field("my_antenna", "dipole") + "<eor>"
        let parsed = ADIFImport.read(Data(handmade.utf8))
        check(parsed.contacts.first?.name == "Ségolène", "accented text reads correctly, with no header")
        check(parsed.leftOut == ["MY_ANTENNA"], "fields Solid Copy doesn't have are reported")
        check(ADIFLocation.decimal(fromADIF: ADIFLocation.adif(fromDecimal: "-116.375", isLatitude: false)) == "-116.375000"
              && ADIFLocation.adif(fromDecimal: "43.604166666", isLatitude: true) == "N043 36.250",
              "latitude and longitude convert both ways")
        // Damaged or hostile ADIF: none of these may crash or hang.
        let hostile: [Data] = [
            Data("<call:999999>W1AW<qso_date:8>20261114<time_on:4>1432<eor>".utf8),   // length past the end
            Data("<call:4>W1AW<qso_date:8>20261114<time_on:4>1432<eor><call:4".utf8), // tag never closed
            Data("<call:-5>W1AW<qso_date:8>20261114<time_on:4>1432<eor>".utf8),       // negative length
            Data((0..<200_000).map { _ in UInt8.random(in: 0...255) }),                 // random bytes
            Data("<eoh>".utf8 + Data(repeating: UInt8(ascii: "<"), count: 100_000)),     // a flood of "<"
        ]
        let started = Date()
        for data in hostile { _ = ADIFImport.read(data) }
        check(Date().timeIntervalSince(started) < 5, "damaged and hostile ADIF reads safely and quickly")

        // Awkward ADX, written by hand: lower-case names, an APP field,
        // a USERDEF field, entities, CDATA, a header that holds a CALL,
        // and line breaks as &#13; and LF.
        let adx = """
            <?xml version="1.0" encoding="UTF-8"?>
            <adx><header><call>NOTME</call><userdef fieldid="1" type="S">epc</userdef></header>
            <records><record>
              <call>F5ÉÉ</call><qso_date>20261114</qso_date><time_on>1432</time_on>
              <name>S&#233;gol&#232;ne &amp; co</name><comment><![CDATA[<cw> fb]]></comment>
              <APP PROGRAMID="SolidCopy" FIELDNAME="cwops" TYPE="S">999</APP>
              <USERDEF FIELDNAME="call">W9XYZ</USERDEF>
              <APP PROGRAMID="OtherLog" FIELDNAME="Mood" TYPE="S">happy</APP>
              <address>1 Main St&#13;
            Town</address>
            </record><record><call>NODATE</call></record></records></adx>
            """
        let fromADX = try ADXImport.read(Data(adx.utf8))
        let f5 = fromADX.contacts.first
        check(fromADX.contacts.count == 1 && fromADX.unreadable == 1 && f5?.call == "F5ÉÉ",
              "ADX: one contact read, one without a date counted unreadable, the header's CALL ignored")
        check(f5?.name == "Ségolène & co" && f5?["comment"] == "<cw> fb" && f5?["address"] == "1 Main St\nTown",
              "ADX: entities, CDATA and CR LF line breaks read correctly")
        check(f5?["app_solidcopy_cwops"] == "999", "ADX: Solid Copy's APP field read, in any case")
        check(fromADX.leftOut == ["APP_OTHERLOG_MOOD", "USERDEF_CALL"],
              "ADX: other programs' and USERDEF fields reported, a USERDEF never taken for CALL")
        check(ADXImport.looksLikeADX(Data(adx.utf8))
              && !ADIFImport.looksLikeADIF(Data("<?xml version=\"1.0\"?><adx></adx>".utf8)),
              "ADX is recognised as ADX")
        // Hostile and damaged ADX: refused, with nothing half imported.
        func refused(_ text: String) -> Bool { (try? ADXImport.read(Data(text.utf8))) == nil }
        let laughs = """
            <?xml version="1.0"?><!DOCTYPE adx [<!ENTITY a "aaaaaaaaaa"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">]>
            <adx><records><record><call>&b;</call></record></records></adx>
            """
        check(refused(laughs), "ADX: a DOCTYPE (entity bombs, outside files) is refused")
        check(refused("<adx><records><record><call>W1AW</call><qso_date>20261114"),
              "ADX: a file cut off partway is refused whole")
        let adxStarted = Date()
        _ = try? ADXImport.read(Data("<adx>".utf8) + Data((0..<200_000).map { _ in UInt8.random(in: 0...255) }))
        _ = try? ADXImport.read(Data(("<adx>" + String(repeating: "<a>", count: 50_000)).utf8))
        check(Date().timeIntervalSince(adxStarted) < 5, "ADX: random bytes and deep nesting read safely and quickly")
        // XML can't hold control characters; the export leaves them out
        // rather than write a file nothing can read.
        var control = QSO(call: "K1ABC", timeOn: Date(timeIntervalSince1970: 1794666725), comment: "bell\u{07}here")
        control["address"] = "a\nb"
        let controlBack = try ADXImport.read(ExportFormat.adx.data(for: [control], includeNotes: false))
        check(controlBack.contacts.first?.comment == "bellhere" && controlBack.contacts.first?["address"] == "a\nb",
              "ADX: control characters left out, line breaks kept")

        var tricky = QSO(call: "K1ABC", timeOn: Date(timeIntervalSince1970: 1794666725), comment: "hello, \"friend\"")
        tricky["address"] = "1 Main St\nTown"
        let csv = String(decoding: ExportFormat.csv.data(for: [tricky], includeNotes: false), as: UTF8.self)
        check(csv.contains("\"hello, \"\"friend\"\"\"") && csv.contains("\"1 Main St\nTown\""),
              "CSV quotes commas, quote marks and line breaks")
        // Cabrillo: the header, one QSO line per contact in time order, and
        // the exchange in the right places (serials first when the contest
        // has them).
        let contest = Contest(id: "ARRL-FIELD-DAY", name: "ARRL Field Day", exchange: ["srx_string"],
                              serial: true, dupes: .bandAndMode)
        var later = QSO(call: "K1ABC", timeOn: Date(timeIntervalSince1970: 1794666725))
        later["freq"] = "14.061"; later["mode"] = "SSB"
        later.rstSent = "59"; later.rstReceived = "59"
        later["stx"] = "1"; later["stx_string"] = "1D MDC"
        later["srx"] = "2"; later["srx_string"] = "3A NY"
        var earlier = QSO(call: "W1AW", timeOn: Date(timeIntervalSince1970: 1794666725 - 3600))
        earlier["freq"] = "7.030"; earlier["mode"] = "CW"
        earlier.rstSent = "599"; earlier.rstReceived = "599"
        earlier["stx"] = "7"; earlier["stx_string"] = "1D MDC"
        earlier["srx"] = "8"; earlier["srx_string"] = "2A CT"
        let cabrillo = Contest.cabrillo([later, earlier], contest: contest, myCall: "N0ME")
        let lines = cabrillo.split(separator: "\n").map(String.init)
        check(lines.first == "START-OF-LOG: 3.0" && lines.contains("CONTEST: ARRL-FIELD-DAY")
              && lines.contains("CALLSIGN: N0ME") && lines.last == "END-OF-LOG:",
              "Cabrillo: header and end line")
        let qsos = lines.filter { $0.hasPrefix("QSO: ") }
        check(qsos.count == 2, "Cabrillo: one QSO line per contact")
        check(qsos.first?.contains(" CW ") == true && qsos.first?.contains(" W1AW ") == true,
              "Cabrillo: earlier contact first, CW mode, call worked")
        check(qsos.first == "QSO: 7030 CW \(earlier.utcDateText) \(earlier.utcTimeText) N0ME 599 7 1D MDC W1AW 599 8 2A CT",
              "Cabrillo: CW line has frequency in kHz, sent serial and exchange, received serial and exchange")
        check(qsos.last == "QSO: 14061 PH \(later.utcDateText) \(later.utcTimeText) N0ME 59 1 1D MDC K1ABC 59 2 3A NY",
              "Cabrillo: phone line has frequency in kHz, mode PH, and the exchanges")
        let noSerial = Contest(id: "TEST", name: "Test", exchange: ["srx_string"], serial: false, dupes: .band)
        let plain = Contest.cabrillo([later], contest: noSerial, myCall: "N0ME")
        check(plain.contains("QSO: 14061 PH \(later.utcDateText) \(later.utcTimeText) N0ME 59 1D MDC K1ABC 59 3A NY\n"),
              "Cabrillo: no serials when the contest has none")
    } catch {
        print("FAIL error:", error)
        exit(1)
    }
}
