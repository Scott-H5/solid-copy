// MacLoggerDXImport.swift
//
// Reads a MacLoggerDX log and turns each row into a Solid Copy contact.
//
// MacLoggerDX keeps its log in an SQLite file (MacLoggerDX.sql, usually in
// ~/Documents/MLDX_Logs), with one table, "qso_table_v008" in the version
// this was written against. The file is opened strictly read-only (see
// Database.init(readOnlyURL:)), so the original is never changed.
//
// How MacLoggerDX stores things, and what each becomes (worked out from
// the author's own log, 2026-11-14):
//   - qso_start and qso_done are Unix time (seconds since 1 January 1970,
//     UTC). They become the contact's time, and End date and End time.
//     A few have fractions of a second; those are dropped.
//   - first_name and last_name become Name ("Hiram Percy").
//   - street, city, state, zip and postal_country become Address, one
//     part per line. city also becomes City (ADIF QTH).
//   - band_tx is like "20M"; ADIF writes bands in lower case ("20m").
//   - tx_frequency and rx_frequency are in MHz, as ADIF wants.
//   - mode "USB" or "LSB" becomes ADIF mode SSB with that submode. FT4
//     and JS8 become ADIF mode MFSK with that submode.
//   - Numbers stored as 0 (power, azimuth, serials, ...) mean "not set".
//   - qsl_sent and qsl_received are free text, such as
//     "20220423, LoTW:20220423, CardC:20251217" or
//     "Uploaded to QRZ Logbook 2025-12-16 16:38". Each part goes into its
//     ADIF field:
//       "LoTW:date" received     LoTW confirmed, and its date
//       "QRZLogbook:date"        QRZ Logbook confirmed, and its date
//       "CardC:date" received    a paper card received, and its date
//       "Uploaded to (or Updated in) QRZ Logbook date"  uploaded there
//     "CardC" is a card MacLoggerDX was told came in. In the author's log it's
//     the old paper cards he and his wife entered by hand on 17 December
//     2025 (an earlier reading took it for a bulk mark: it isn't, as the
//     contacts without cards from the same years show). MacLoggerDX puts
//     the same "CardC" in qsl_sent too, which says nothing about a card
//     going out, so it isn't taken as one. A bare date at the start of
//     qsl_received repeats the first confirmation's, so it's skipped.
//   - ext_val_1 and ext_val_2 hold your own county ("MD,COUNTY") and
//     state ("MD"). ext_val_3 repeated the other station's state and
//     ext_val_4 was empty, so neither is kept.
//
// LogImport.swift decides which reader a file needs. This file uses only
// Foundation (no windows), so it can be tested on its own: see
// tools/check-import-export.sh.

import Foundation

enum MacLoggerDXImport {

    struct Result {
        // The contacts read, oldest first.
        var contacts: [QSO]
        // Rows that couldn't be read (no callsign, or no start time).
        var unreadable: Int
    }

    // Reads every contact in a MacLoggerDX log file.
    static func read(from url: URL) throws -> Result {
        let database = try Database(readOnlyURL: url)

        // Find the contacts table. The name ends in a version number, so
        // take the newest if there's more than one.
        let tables = try database.query(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'qso_table_v%' ORDER BY name DESC")
        guard let table = tables.first?["name"] else {
            throw DatabaseError(message: "This .sql file isn't a log Solid Copy can read: it has no contacts table.")
        }

        var contacts: [QSO] = []
        var unreadable = 0
        // The table's name comes from the file, so quote it safely: a name
        // containing a quote mark can't change the command.
        let quoted = "\"" + table.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        for row in try database.query("SELECT * FROM \(quoted) ORDER BY qso_start, pk") {
            if let qso = contact(from: row) {
                contacts.append(qso)
            } else {
                unreadable += 1
            }
        }
        return Result(contacts: contacts, unreadable: unreadable)
    }

    // Turns one MacLoggerDX row into a contact, or nil if it has no
    // callsign or start time.
    static func contact(from row: [String: String]) -> QSO? {
        func text(_ column: String) -> String {
            (row[column] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // A number column, with 0 meaning "not set", and "5.0" tidied to "5".
        func number(_ column: String) -> String {
            let value = text(column)
            guard let double = Double(value), double != 0 else { return "" }
            if double == double.rounded(), abs(double) < 1e15 { return String(Int(double)) }
            return value
        }

        let call = Callsign.normalized(text("call"))
        guard !call.isEmpty, let start = Double(text("qso_start")), start > 0 else { return nil }
        // Whole seconds only. A few MacLoggerDX times carry a fraction of a
        // second, which ADIF can't hold; dropping it means a contact's time
        // is the same however it arrives (directly, or through ADIF).
        var qso = QSO(call: call, timeOn: Date(timeIntervalSince1970: start.rounded(.down)))

        // When the contact ended.
        if let end = Double(text("qso_done")), end > 0 {
            let endTime = QSO(call: call, timeOn: Date(timeIntervalSince1970: end.rounded(.down)))
            qso["qso_date_off"] = endTime.adifDate
            qso["time_off"] = endTime.adifTime
        }

        // Contact.
        qso.name = [text("first_name"), text("last_name")].filter { !$0.isEmpty }.joined(separator: " ")
        qso.rstSent = text("rst_sent")
        qso.rstReceived = text("rst_received")
        qso.comment = text("comments")
        qso["email"] = text("email")
        qso["web"] = text("url")

        // Radio.
        qso["band"] = text("band_tx").lowercased()
        qso["band_rx"] = text("band_rx").lowercased()
        qso["freq"] = number("tx_frequency")
        qso["freq_rx"] = number("rx_frequency")
        qso["tx_pwr"] = number("power")
        qso["sat_name"] = text("satellite")
        let (mode, submode) = adifMode(text("mode"))
        qso["mode"] = mode
        qso["submode"] = submode

        // Location.
        qso["qth"] = text("city")
        qso["state"] = text("state")
        qso["cnty"] = text("county")
        qso["country"] = text("dxcc_country")
        qso["dxcc"] = number("dxcc_id")
        qso["gridsquare"] = text("grid")
        qso["cqz"] = text("cq_zone")
        qso["ituz"] = text("itu")
        qso["iota"] = text("iota")
        qso["lat"] = number("latitude")
        qso["lon"] = number("longitude")
        qso["distance"] = number("distance")
        qso["ant_az"] = number("azimuth")
        qso["ant_el"] = number("elevation")
        let cityLine = [[text("city"), text("state")].filter { !$0.isEmpty }.joined(separator: ", "), text("zip")]
            .filter { !$0.isEmpty }.joined(separator: " ")
        qso["address"] = [text("street"), cityLine, text("postal_country")]
            .filter { !$0.isEmpty }.joined(separator: "\n")

        // Awards and activities.
        qso["pota_ref"] = text("pota")
        qso["sota_ref"] = text("sota")
        qso["wwff_ref"] = text("wwff")
        qso["skcc"] = text("skcc")
        qso["ten_ten"] = text("ten_ten")
        qso["sig"] = text("sig")
        qso["sig_info"] = text("sig_info")

        // QSL.
        qso["qsl_via"] = text("qsl_via")
        let sent = text("qsl_sent")
        let received = text("qsl_received")
        if sent.localizedCaseInsensitiveContains("QRZ Logbook") {
            qso["qrzcom_qso_upload_status"] = "Y"
            qso["qrzcom_qso_upload_date"] = firstDate(in: sent)
        }
        // Confirmations: (service, status field, date field).
        for (service, status, date) in [("LoTW", "lotw_qsl_rcvd", "lotw_qslrdate"),
                                        ("QRZLogbook", "qrzcom_qso_download_status", "qrzcom_qso_download_date"),
                                        ("CardC", "qsl_rcvd", "qslrdate")] {
            guard let when = servicePart(service, in: received) else { continue }
            qso[status] = "Y"
            qso[date] = when
        }

        // Contest.
        qso["contest_id"] = text("contest_id")
        qso["stx"] = number("stx_numeric")
        qso["srx"] = number("srx_numeric")
        qso["stx_string"] = text("stx")
        qso["srx_string"] = text("srx")

        // My station.
        qso["station_callsign"] = Callsign.normalized(text("my_call"))
        qso["my_gridsquare"] = text("my_grid")
        qso["my_rig"] = text("my_rig")
        qso["my_pota_ref"] = text("my_pota")
        qso["my_sota_ref"] = text("my_sota")
        qso["my_wwff_ref"] = text("my_wwff")
        qso["my_sig"] = text("my_sig")
        qso["my_sig_info"] = text("my_sig_info")
        qso["my_cnty"] = text("ext_val_1")
        qso["my_state"] = text("ext_val_2")

        return qso
    }

    // ADIF names some modes differently from what radios show: USB and LSB
    // are SSB with a submode, and FT4 and JS8 are MFSK with a submode.
    static func adifMode(_ mode: String) -> (mode: String, submode: String) {
        let upper = mode.uppercased()
        switch upper {
        case "USB", "LSB": return ("SSB", upper)
        case "FT4", "JS8": return ("MFSK", upper)
        default: return (upper, "")
        }
    }

    // The first date in text, as ADIF's YYYYMMDD. Accepts "2025-12-16" or
    // "20251216".
    static func firstDate(in text: String) -> String {
        guard let match = text.range(of: #"\d{4}-?\d{2}-?\d{2}"#, options: .regularExpression) else { return "" }
        return text[match].filter(\.isNumber)
    }

    // The date after "Service:" in MacLoggerDX's QSL text, such as
    // "LoTW:20220423", or nil if that service isn't mentioned.
    static func servicePart(_ service: String, in text: String) -> String? {
        for part in text.components(separatedBy: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix(service.lowercased() + ":") {
                return firstDate(in: trimmed)
            }
        }
        return nil
    }
}
