// QRZLogbookUpload.swift
//
// Sends contacts to QRZ Logbook, one per request (QRZ takes one at a
// time), through the loop all three online logbooks share
// (OneByOneUpload.swift). QRZ's rules are in QRZLogbook.swift. Used by
// QSL > Upload to QRZ Logbook (every contact not yet sent), the log's
// shortcut menu (the selected ones) and automatic uploads
// (AutoUploader.swift). Only your API key and the contacts are sent, and
// only to QRZ.

import Foundation

@MainActor
enum QRZLogbookUpload {
    static var running: Bool { OneByOneUpload.running.contains(.qrzLogbook) }

    // The API key (from the Keychain); the checks use a pretend one.
    static var key: () -> String = { Settings.qrzLogbookKey }

    static func upload(_ contacts: [QSO], logbook: Logbook,
                       progress: (String) -> Void = { _ in }) async -> UploadReport {
        // A test log never uploads (LogList.swift): checked first.
        guard !logbook.isTest else { return .testLog }
        let key = key()
        guard !key.isEmpty else {
            return UploadReport(text: "QRZ Logbook: add your logbook's API key in Settings > Uploads.", ok: false)
        }
        return await OneByOneUpload.upload(contacts, to: .qrzLogbook, logbook: logbook, pause: 0, prepare: { qso in
            var request = URLRequest(url: QRZLogbook.endpoint, timeoutInterval: 30)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = QRZLogbook.insertBody(key: key, qso: qso)
            return request
        }, read: { data, response in
            guard response.statusCode == 200 else {
                return .stop("QRZ answered with an error; try again later.", tryAgain: true)
            }
            return QRZLogbook.answer(from: data)
        }, progress: progress)
    }
}
