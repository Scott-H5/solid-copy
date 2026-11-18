// Upload.swift
//
// The online logbooks Solid Copy uploads to, and when it does so by itself
// (Settings > Uploads). The uploading is in Sources/Uploads and
// Sources/LoTW; this is just the names and choices, which Settings and the
// menus share.

import Foundation

enum UploadService: String, CaseIterable {
    case lotw, qrzLogbook, clubLog, eqsl

    var name: String {
        switch self {
        case .lotw: "LoTW"
        case .qrzLogbook: "QRZ Logbook"
        case .clubLog: "Club Log"
        case .eqsl: "eQSL"
        }
    }

    // The site itself, for "QRZ couldn't be reached".
    var shortName: String { self == .qrzLogbook ? "QRZ" : name }

    // ADIF's fields saying a contact is uploaded here, and when.
    var sentField: String {
        switch self {
        case .lotw: "lotw_qsl_sent"
        case .qrzLogbook: "qrzcom_qso_upload_status"
        case .clubLog: "clublog_qso_upload_status"
        case .eqsl: "eqsl_qsl_sent"
        }
    }
    var sentDateField: String {
        switch self {
        case .lotw: "lotw_qslsdate"
        case .qrzLogbook: "qrzcom_qso_upload_date"
        case .clubLog: "clublog_qso_upload_date"
        case .eqsl: "eqsl_qslsdate"
        }
    }

    // The contact is marked as uploaded here, or (LoTW, eQSL) already
    // confirmed by it, which means it has it.
    func isUploaded(_ qso: QSO) -> Bool {
        if qso[sentField].uppercased() == "Y" { return true }
        switch self {
        case .lotw: return qso["lotw_qsl_rcvd"].uppercased() == "Y"
        case .eqsl: return qso["eqsl_qsl_rcvd"].uppercased() == "Y"
        case .qrzLogbook, .clubLog: return false
        }
    }

    // Marks a contact uploaded today; a date already there is kept.
    func mark(_ qso: inout QSO, today: String) {
        qso[sentField] = "Y"
        if qso[sentDateField].isEmpty { qso[sentDateField] = today }
    }

    // The contacts to send: not yet uploaded here, on or after `day`
    // ("2020-01-01"; empty for all).
    func toUpload(_ contacts: [QSO], from day: String) -> [QSO] {
        let start = day.isEmpty ? nil : QSO.date(adifDate: day.filter(\.isNumber), adifTime: "000000")
        return contacts.filter { qso in !isUploaded(qso) && start.map { qso.timeOn >= $0 } ?? true }
    }
}

// When new contacts go up by themselves.
enum AutoUpload: String, CaseIterable {
    // Only when you ask (the QSL menu, or the log's shortcut menu).
    case byHand
    // Half a minute after each contact: time for the lookup to fill in
    // its details, and for a quick correction.
    case soonAfterEach
    // Five minutes after the last contact: a run of contacts goes up
    // together, and any corrections made meanwhile go up with them (LoTW
    // can't change a contact once it has one).
    case afterAPause

    var title: String {
        switch self {
        case .byHand: "By hand"
        case .soonAfterEach: "Soon after each contact"
        case .afterAPause: "Five minutes after the last contact"
        }
    }

    // Seconds from the last contact logged to the upload.
    var delay: TimeInterval {
        switch self {
        case .byHand: 0
        case .soonAfterEach: 30
        case .afterAPause: 300
        }
    }
}

// How an upload went: words to say or show, and whether it all went.
struct UploadReport {
    // What every upload path says for a test log (LogList.swift), and
    // refuses with, before it touches the contacts or the network.
    static let testLogText = "This is a test log: nothing in it is ever uploaded."
    static let testLog = UploadReport(text: testLogText, ok: false)

    // The last upload or sync message said or shown, for QSL > Show Last
    // Upload Message: spoken ones (automatic uploads, the log's shortcut
    // menu) are gone once heard, and can't be read again or copied
    // otherwise.
    @MainActor static var last = ""

    var text: String
    // Every contact is in the online logbook now.
    var ok: Bool
    // Nothing could be sent (no internet, the service down): worth trying
    // again later.
    var tryAgain = false
}
