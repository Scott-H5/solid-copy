// LogField.swift
//
// The list of every field a contact can have, besides the callsign and
// the date and time (which are special: see QSO.swift).
//
// This one list drives everything: the log file's columns, the details
// panel, the Edit Contact sheet, the log table's columns, and (soon) ADIF
// import and export and the SQL log import. To add a field, add it
// here, and add its column to the log file (a new entry in
// LogDatabase.migrations).
//
// Each field has:
//   - its ADIF name in lower case ("gridsquare"), which is also its
//     column name in the log file,
//   - the label people see and hear ("Grid square"),
//   - the group it's shown under in Edit Contact,
//   - whether it can hold more than one line (Notes, Address),
//   - whether Edit Contact shows it (not for fields Solid Copy keeps up
//     itself, such as a scanned card's file).
//
// The order here is the order fields appear in Edit Contact and the
// details panel.

import Foundation

struct LogField {
    enum Group: String, CaseIterable {
        case contact = "Contact"
        case radio = "Radio"
        case location = "Location"
        case awards = "Awards and activities"
        case qsl = "QSL"
        case contest = "Contest"
        case myStation = "My station"
    }

    let adif: String
    let group: Group
    var multiline = false
    var editable = true
    // For your own club fields (1 to clubSlots), which one: their label
    // is the name you gave it in Settings > Clubs. Nil for every other.
    var clubSlot: Int?
    private let fixedLabel: String

    init(adif: String, label: String, group: Group, multiline: Bool = false, editable: Bool = true,
         clubSlot: Int? = nil) {
        self.adif = adif
        fixedLabel = label
        self.group = group
        self.multiline = multiline
        self.editable = editable
        self.clubSlot = clubSlot
    }

    // What people see and hear. Your own club fields are called what you
    // named them ("NAQCC number"), or "Club field 2" until you do.
    var label: String {
        guard let clubSlot else { return fixedLabel }
        let name = ClubNames.name(clubSlot)
        return name.isEmpty ? "Club field \(clubSlot)" : name
    }

    // One of your club fields with no name: kept out of the form, the
    // column choices and Edit Contact until you name it. (Its values, if
    // any, stay in the log, the details panel and exports.)
    var isUnnamedClubField: Bool {
        clubSlot.map { ClubNames.name($0).isEmpty } ?? false
    }

    // How many club fields of your own there are. Five keeps Settings
    // short; the field list and the log file have room for exactly this
    // many (app_solidcopy_club1 ... club5; LogDatabase migration 8).
    static let clubSlots = 5

    static let all: [LogField] = [
        // Contact
        LogField(adif: "name", label: "Name", group: .contact),
        LogField(adif: "rst_sent", label: "RST sent", group: .contact),
        LogField(adif: "rst_rcvd", label: "RST received", group: .contact),
        LogField(adif: "comment", label: "Comment", group: .contact),
        LogField(adif: "notes", label: "QSO notes", group: .contact, multiline: true),
        // When the contact ended, in ADIF form: YYYYMMDD and HHMMSS (UTC).
        LogField(adif: "qso_date_off", label: "End date (UTC)", group: .contact),
        LogField(adif: "time_off", label: "End time (UTC)", group: .contact),
        LogField(adif: "email", label: "Email", group: .contact),
        LogField(adif: "web", label: "Web page", group: .contact),

        // Radio
        LogField(adif: "band", label: "Band", group: .radio),
        LogField(adif: "mode", label: "Mode", group: .radio),
        LogField(adif: "submode", label: "Submode", group: .radio),
        LogField(adif: "freq", label: "Frequency (MHz)", group: .radio),
        LogField(adif: "band_rx", label: "Receive band", group: .radio),
        LogField(adif: "freq_rx", label: "Receive frequency (MHz)", group: .radio),
        LogField(adif: "tx_pwr", label: "Power (watts)", group: .radio),
        LogField(adif: "sat_name", label: "Satellite", group: .radio),

        // Location
        LogField(adif: "qth", label: "City", group: .location),
        LogField(adif: "state", label: "State or province", group: .location),
        LogField(adif: "cnty", label: "County", group: .location),
        LogField(adif: "country", label: "Country", group: .location),
        LogField(adif: "dxcc", label: "DXCC entity number", group: .location),
        LogField(adif: "gridsquare", label: "Grid square", group: .location),
        LogField(adif: "cqz", label: "CQ zone", group: .location),
        LogField(adif: "ituz", label: "ITU zone", group: .location),
        LogField(adif: "iota", label: "IOTA", group: .location),
        // The prefix that counts for CQ's WPX award, as LoTW gives it.
        LogField(adif: "pfx", label: "WPX prefix", group: .location),
        LogField(adif: "address", label: "Address", group: .location, multiline: true),
        LogField(adif: "lat", label: "Latitude", group: .location),
        LogField(adif: "lon", label: "Longitude", group: .location),
        LogField(adif: "distance", label: "Distance (km)", group: .location),
        LogField(adif: "ant_az", label: "Antenna azimuth", group: .location),
        LogField(adif: "ant_el", label: "Antenna elevation", group: .location),

        // Awards and activities
        LogField(adif: "pota_ref", label: "POTA park", group: .awards),
        LogField(adif: "sota_ref", label: "SOTA summit", group: .awards),
        LogField(adif: "wwff_ref", label: "WWFF reference", group: .awards),
        LogField(adif: "skcc", label: "SKCC number", group: .awards),
        LogField(adif: "fists", label: "FISTS number", group: .awards),
        LogField(adif: "fists_cc", label: "FISTS Century Certificate credits", group: .awards),
        // ADIF has no official fields for LICW or CWops, so these are Solid
        // Copy's own (APP_SOLIDCOPY_...), which ADIF allows. Other programs
        // keep or ignore them.
        LogField(adif: "app_solidcopy_licw", label: "LICW number", group: .awards),
        LogField(adif: "app_solidcopy_cwops", label: "CWops number", group: .awards),
    ] + (1...clubSlots).map {
        // Your own club fields (Settings > Clubs), named by you.
        LogField(adif: "app_solidcopy_club\($0)", label: "", group: .awards, clubSlot: $0)
    } + [
        LogField(adif: "ten_ten", label: "10-10 number", group: .awards),
        LogField(adif: "sig", label: "Special interest group", group: .awards),
        LogField(adif: "sig_info", label: "Special interest information", group: .awards),

        // QSL. ADIF's QSL_SENT and QSL_RCVD are paper cards, so they're
        // labelled "Card". Statuses are ADIF's letters: Y yes, N no,
        // R requested, Q queued, I ignore. Dates are YYYYMMDD. "Via" is how
        // it went: B bureau, D direct, E electronic, M manager.
        LogField(adif: "qsl_sent", label: "Card sent", group: .qsl),
        LogField(adif: "qslsdate", label: "Card sent date", group: .qsl),
        LogField(adif: "qsl_sent_via", label: "Card sent via", group: .qsl),
        LogField(adif: "qsl_rcvd", label: "Card received", group: .qsl),
        LogField(adif: "qslrdate", label: "Card received date", group: .qsl),
        LogField(adif: "qsl_rcvd_via", label: "Card received via", group: .qsl),
        LogField(adif: "qsl_via", label: "QSL via", group: .qsl),
        LogField(adif: "qslmsg", label: "QSL message", group: .qsl),
        // What their card said to you (comments written on it).
        LogField(adif: "qslmsg_rcvd", label: "Their card's message", group: .qsl, multiline: true),
        // A scanned card (QSLCards.swift): its file in the QSL Cards
        // folder beside the log, and the text the scan holds, so a search
        // finds it. Solid Copy's own fields (ADIF has none for these).
        LogField(adif: "app_solidcopy_qsl_card", label: "Scanned card", group: .qsl, editable: false),
        LogField(adif: "app_solidcopy_card_text", label: "Card text", group: .qsl, multiline: true, editable: false),
        LogField(adif: "lotw_qsl_sent", label: "Uploaded to LoTW", group: .qsl),
        LogField(adif: "lotw_qslsdate", label: "LoTW upload date", group: .qsl),
        LogField(adif: "lotw_qsl_rcvd", label: "LoTW confirmed", group: .qsl),
        LogField(adif: "lotw_qslrdate", label: "LoTW confirmed date", group: .qsl),
        LogField(adif: "eqsl_qsl_sent", label: "Uploaded to eQSL", group: .qsl),
        LogField(adif: "eqsl_qslsdate", label: "eQSL upload date", group: .qsl),
        LogField(adif: "eqsl_qsl_rcvd", label: "eQSL confirmed", group: .qsl),
        LogField(adif: "eqsl_qslrdate", label: "eQSL confirmed date", group: .qsl),
        LogField(adif: "qrzcom_qso_upload_status", label: "Uploaded to QRZ Logbook", group: .qsl),
        LogField(adif: "qrzcom_qso_upload_date", label: "QRZ Logbook upload date", group: .qsl),
        // ADIF's "downloaded from QRZ Logbook": what loggers use for a
        // contact QRZ Logbook confirms.
        LogField(adif: "qrzcom_qso_download_status", label: "QRZ Logbook confirmed", group: .qsl),
        LogField(adif: "qrzcom_qso_download_date", label: "QRZ Logbook confirmed date", group: .qsl),
        LogField(adif: "clublog_qso_upload_status", label: "Uploaded to Club Log", group: .qsl),
        LogField(adif: "clublog_qso_upload_date", label: "Club Log upload date", group: .qsl),

        // Contest
        LogField(adif: "contest_id", label: "Contest", group: .contest),
        LogField(adif: "stx", label: "Serial sent", group: .contest),
        LogField(adif: "srx", label: "Serial received", group: .contest),
        LogField(adif: "stx_string", label: "Exchange sent", group: .contest),
        LogField(adif: "srx_string", label: "Exchange received", group: .contest),

        // My station
        LogField(adif: "station_callsign", label: "My callsign", group: .myStation),
        LogField(adif: "my_gridsquare", label: "My grid square", group: .myStation),
        LogField(adif: "my_rig", label: "My radio", group: .myStation),
        LogField(adif: "my_state", label: "My state", group: .myStation),
        LogField(adif: "my_cnty", label: "My county", group: .myStation),
        LogField(adif: "my_pota_ref", label: "My POTA park", group: .myStation),
        LogField(adif: "my_sota_ref", label: "My SOTA summit", group: .myStation),
        LogField(adif: "my_wwff_ref", label: "My WWFF reference", group: .myStation),
        LogField(adif: "my_sig", label: "My special interest group", group: .myStation),
        LogField(adif: "my_sig_info", label: "My special interest information", group: .myStation),
    ]

    // Looks up a field by its ADIF name.
    // Whether it can go on the logging form: a field you'd type as you
    // log. Not the QSL statuses and dates, which nobody knows yet when
    // logging; syncing, the QSL menu and Edit Contact set them. Multi-line
    // fields are kept off the form, except QSO notes, which go on as one
    // line (Edit Contact has the full box for line breaks).
    var canGoOnForm: Bool {
        editable && (!multiline || Self.multilineOnForm.contains(adif))
            && !Self.setLater.contains(adif) && !isUnnamedClubField
    }
    private static let multilineOnForm: Set<String> = ["notes"]

    // The club membership numbers: SKCC, FISTS, LICW, CWops and your own
    // club fields. A member keeps their number, so Solid Copy fills these
    // in from the last contact with the same call (ClubNumbers.swift).
    static let clubNumberFields: [String] = ["skcc", "fists", "app_solidcopy_licw", "app_solidcopy_cwops"]
        + (1...clubSlots).map { "app_solidcopy_club\($0)" }
    private static let setLater: Set<String> = [
        "qsl_sent", "qslsdate", "qsl_sent_via", "qsl_rcvd", "qslrdate", "qsl_rcvd_via",
        "lotw_qsl_sent", "lotw_qslsdate", "lotw_qsl_rcvd", "lotw_qslrdate",
        "eqsl_qsl_sent", "eqsl_qslsdate", "eqsl_qsl_rcvd", "eqsl_qslrdate",
        "qrzcom_qso_upload_status", "qrzcom_qso_upload_date", "qrzcom_qso_download_status", "qrzcom_qso_download_date",
        "clublog_qso_upload_status", "clublog_qso_upload_date",
    ]

    static func named(_ adif: String) -> LogField? {
        all.first { $0.adif == adif }
    }
}

// The names you gave your own club fields (Settings > Clubs), kept with
// the other settings. Here rather than in Settings.swift because the
// field list needs them, and the check tools build the field list
// without the Settings code.
enum ClubNames {
    private static let key = "clubNames"

    // Slot 1 to LogField.clubSlots; "" for one not named.
    static func name(_ slot: Int) -> String {
        let names = UserDefaults.standard.stringArray(forKey: key) ?? []
        return names.indices.contains(slot - 1) ? names[slot - 1] : ""
    }

    static func setName(_ name: String, for slot: Int) {
        guard (1...LogField.clubSlots).contains(slot) else { return }
        var names = UserDefaults.standard.stringArray(forKey: key) ?? []
        while names.count < LogField.clubSlots { names.append("") }
        names[slot - 1] = String(name.trimmingCharacters(in: .whitespaces).prefix(40))
        UserDefaults.standard.set(names, forKey: key)
    }
}
