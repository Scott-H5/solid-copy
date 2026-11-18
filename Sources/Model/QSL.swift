// QSL.swift
//
// QSL tracking: whether a contact is confirmed, and how, in words.
//
// A QSL is the other station's confirmation that the contact happened:
// a paper card in the post, or an electronic one through LoTW (the ARRL's
// Logbook of the World, the one awards accept), eQSL or QRZ Logbook. Each
// is kept in ADIF's own fields (see LogField.swift, QSL group), with ADIF's
// one-letter statuses:
//   Y yes, N no, R requested, Q queued, I ignore, V verified (counts as yes)
// and "via" letters: B bureau, D direct, E electronic, M manager.
//
// For paper cards, QSL_SENT "R" means the other station asked you for a
// card (you owe one); QSL_RCVD "R" means you asked them for theirs.
//
// This file turns all that into one line VoiceOver reads in one stop
// ("Confirmed: card 17 December 2025, LoTW 23 April 2022. Uploaded to
// QRZ Logbook."), the words for each field in the details panel, the log's
// QSL filters, and the card marks (Card Requested, Card Sent, Card
// Received) made from the log. Foundation only, so it can be checked on
// its own (tools/check-log-table.sh).

import Foundation

enum QSL {

    // The confirmations, in the order they're said: (name, status field,
    // date field).
    static let confirmations: [(name: String, status: String, date: String)] = [
        ("card", "qsl_rcvd", "qslrdate"),
        ("LoTW", "lotw_qsl_rcvd", "lotw_qslrdate"),
        ("eQSL", "eqsl_qsl_rcvd", "eqsl_qslrdate"),
        ("QRZ Logbook", "qrzcom_qso_download_status", "qrzcom_qso_download_date"),
    ]

    // Uploads, said after the confirmations: (name, status field).
    private static let uploads: [(name: String, status: String)] = [
        ("LoTW", "lotw_qsl_sent"), ("eQSL", "eqsl_qsl_sent"), ("QRZ Logbook", "qrzcom_qso_upload_status"),
        ("Club Log", "clublog_qso_upload_status"),
    ]

    private static func isYes(_ value: String) -> Bool { ["Y", "V"].contains(value.uppercased()) }

    // Confirmed by anything: a card, LoTW, eQSL or QRZ Logbook.
    static func isConfirmed(_ qso: QSO) -> Bool {
        confirmations.contains { isYes(qso[$0.status]) }
    }

    // The whole QSL story of a contact, in one line.
    static func summary(_ qso: QSO) -> String {
        var sentences: [String] = []
        let confirmed = confirmations.filter { isYes(qso[$0.status]) }.map { item in
            [item.name, spokenDate(qso[item.date])].filter { !$0.isEmpty }.joined(separator: " ")
        }
        sentences.append(confirmed.isEmpty ? "Not confirmed" : "Confirmed: " + confirmed.joined(separator: ", "))

        // Your card to them.
        let via = spokenVia(qso["qsl_sent_via"])
        switch qso["qsl_sent"].uppercased() {
        case "R": sentences.append("They asked for a card")
        case "Q": sentences.append("Card to send")
        case "Y":
            sentences.append(["Card sent", spokenDate(qso["qslsdate"]), via.isEmpty ? "" : "by " + via]
                .filter { !$0.isEmpty }.joined(separator: " "))
        default: break
        }
        // Theirs, asked for but not here yet.
        if qso["qsl_rcvd"].uppercased() == "R" { sentences.append("You asked for their card") }

        let uploaded = uploads.filter { isYes(qso[$0.status]) && !isYes(qso[confirmationField(for: $0.name)]) }
        if !uploaded.isEmpty { sentences.append("Uploaded to " + list(uploaded.map(\.name))) }
        if !qso["app_solidcopy_qsl_card"].isEmpty { sentences.append("Scanned card attached") }
        return sentences.joined(separator: ". ") + "."
    }

    // An upload that's also confirmed needn't be said twice.
    private static func confirmationField(for name: String) -> String {
        confirmations.first { $0.name == name }?.status ?? ""
    }

    // "LoTW", "LoTW and eQSL", "LoTW, eQSL and QRZ Logbook".
    private static func list(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names.last!
    }

    // MARK: - Words for the details panel

    private static let statusFields: Set<String> = [
        "qsl_sent", "qsl_rcvd", "lotw_qsl_sent", "lotw_qsl_rcvd", "eqsl_qsl_sent", "eqsl_qsl_rcvd",
        "qrzcom_qso_upload_status", "qrzcom_qso_download_status", "clublog_qso_upload_status",
    ]
    private static let dateFields: Set<String> = [
        "qslsdate", "qslrdate", "lotw_qslsdate", "lotw_qslrdate", "eqsl_qslsdate", "eqsl_qslrdate",
        "qrzcom_qso_upload_date", "qrzcom_qso_download_date", "clublog_qso_upload_date",
    ]

    // A QSL field's value in words ("Y" is "Yes", "20251217" is
    // "17 December 2025"); any other field's value as it is. Something
    // that isn't one of ADIF's letters or a date is shown as it is too.
    static func display(field: String, value: String) -> String {
        if statusFields.contains(field) {
            let words = ["Y": "Yes", "N": "No", "R": "Requested", "Q": "Queued", "I": "Ignore", "V": "Verified"]
            return words[value.uppercased()] ?? value
        }
        if field == "qsl_sent_via" || field == "qsl_rcvd_via" {
            let words = spokenVia(value)
            return words.isEmpty ? value : words.prefix(1).uppercased() + words.dropFirst()
        }
        if field == "app_solidcopy_qsl_card" { return "Attached (QSL > Open Card)" }
        if dateFields.contains(field) {
            let words = spokenDate(value)
            return words.isEmpty ? value : words
        }
        return value
    }

    // MARK: - Choosing in Edit Contact

    // The choices for a status or "via" field, as menu items in words
    // (Edit Contact), with ADIF's letter each stands for. "Not set" is
    // empty. Nil for any other field. A value already in the log that
    // isn't one of these is added to the menu by Edit Contact, so it's
    // never lost by opening and saving.
    static func choices(for field: String) -> [(value: String, title: String)]? {
        if statusFields.contains(field) {
            return [("", "Not set"), ("Y", "Yes"), ("N", "No"), ("R", "Requested"), ("Q", "Queued"),
                    ("I", "Ignore"), ("V", "Verified")]
        }
        if field == "qsl_sent_via" || field == "qsl_rcvd_via" {
            return [("", "Not set"), ("B", "Bureau"), ("D", "Direct"), ("E", "Electronic"), ("M", "Manager")]
        }
        return nil
    }

    static func isDateField(_ field: String) -> Bool { dateFields.contains(field) }

    // ADIF's "20251217" as "2025-12-17", for typing over in Edit Contact
    // (VoiceOver reads it as a date). Anything else as it is.
    static func readableDate(_ adif: String) -> String {
        guard adif.count == 8, adif.allSatisfy(\.isNumber), adifDay.date(from: adif) != nil else { return adif }
        return "\(adif.prefix(4))-\(adif.dropFirst(4).prefix(2))-\(adif.suffix(2))"
    }

    // A typed date back to ADIF's form: "2025-12-17", "2025/12/17" or
    // "20251217" -> "20251217"; empty stays empty. Nil if it isn't a real
    // day (so Edit Contact can say so).
    static func adifDate(typed: String) -> String? {
        let text = typed.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return "" }
        let digits = text.filter(\.isNumber)
        guard digits.count == 8, text.allSatisfy({ $0.isNumber || "-/. ".contains($0) }),
              let date = adifDay.date(from: digits), adifDay.string(from: date) == digits else { return nil }
        return digits
    }

    private static func spokenVia(_ value: String) -> String {
        ["B": "bureau", "D": "direct", "E": "electronic", "M": "manager"][value.uppercased()] ?? ""
    }

    // ADIF's "20251217" as "17 December 2025"; anything else as "".
    static func spokenDate(_ adif: String) -> String {
        guard adif.count == 8, adif.allSatisfy(\.isNumber), let date = adifDay.date(from: adif) else { return "" }
        return spokenDay.string(from: date)
    }

    // Today (UTC) in ADIF's form, for the card marks.
    static func today(_ now: Date = Date()) -> String { adifDay.string(from: now) }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }
    private static let adifDay = formatter("yyyyMMdd")
    private static let spokenDay = formatter("d MMMM yyyy")

    // MARK: - The log's QSL filters

    enum Filter: CaseIterable {
        case confirmed, notConfirmed, cardRequested

        // For the log's heading: "12 contacts confirmed".
        var heading: String {
            switch self {
            case .confirmed: return "confirmed"
            case .notConfirmed: return "not confirmed"
            case .cardRequested: return "asking for a card"
            }
        }

        func matches(_ qso: QSO) -> Bool {
            switch self {
            case .confirmed: return QSL.isConfirmed(qso)
            case .notConfirmed: return !QSL.isConfirmed(qso)
            case .cardRequested: return qso["qsl_sent"].uppercased() == "R"
            }
        }
    }

    // MARK: - Card marks

    enum CardMark {
        case requested, sent, received

        // As said and in menus: "Card requested".
        var name: String {
            switch self {
            case .requested: return "Card requested"
            case .sent: return "Card sent"
            case .received: return "Card received"
            }
        }

        // The field it sets, the value, and the date field (if dated).
        var field: String { self == .received ? "qsl_rcvd" : "qsl_sent" }
        var value: String { self == .requested ? "R" : "Y" }
        var dateField: String? {
            switch self {
            case .requested: return nil
            case .sent: return "qslsdate"
            case .received: return "qslrdate"
            }
        }

        func isOn(_ qso: QSO) -> Bool { qso[field].uppercased() == value }
    }

    // Marks contacts, or, if every one already has the mark, takes it off
    // (so the same command undoes a slip, besides Command-Z). Marking
    // dates it today; taking it off clears the date. Returns the changed
    // contacts, and whether the mark went on.
    static func apply(_ mark: CardMark, to contacts: [QSO], today: String) -> (changed: [QSO], on: Bool) {
        let on = !contacts.allSatisfy(mark.isOn)
        let changed = contacts.map { qso -> QSO in
            var qso = qso
            if on {
                // Already marked keeps its date; the rest are dated today.
                if !mark.isOn(qso), let dateField = mark.dateField { qso[dateField] = today }
                qso[mark.field] = mark.value
            } else {
                qso[mark.field] = ""
                if let dateField = mark.dateField { qso[dateField] = "" }
            }
            return qso
        }
        return (changed, on)
    }
}
