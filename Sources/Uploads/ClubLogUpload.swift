// ClubLogUpload.swift
//
// Sends contacts to Club Log (clublog.org), one per request, through the
// shared loop (OneByOneUpload.swift).
//
// How Club Log's REST API works (its knowledge base, "REST API", read 17
// November 2026; it replaced the old realtime.php, which is closed to new
// programs):
//   - You make a token on clublog.org: Settings, the API tab, a label,
//     Create token. It's shown once, so copy it then. Solid Copy keeps it
//     in the Keychain ("Solid Copy: Club Log"). No developer key is needed.
//   - Each request carries "Authorization: Bearer <token>".
//   - One contact: POST https://clublog.org/api/v1/qso, JSON
//     {"call": your callsign, "adif": one ADIF record}. Your callsign must
//     belong to the token's account.
//   - Answers: 201 created (with a qsoid), 200 with status "duplicate" or
//     "updated", 422 refused (the reason in "message"), 401 token not
//     accepted, 403 callsign not on the account, 429 too many requests.
//   - Limits: 60 requests a minute, 10,000 contacts a day, per account.
//     Solid Copy waits 1.1 seconds between contacts, so it can't go over.
//   - A program that keeps sending a failing request can have your
//     internet address blocked for a while. So 401, 403 and 429 stop the
//     upload, and only 429 and Club Log's own errors are tried again
//     later.
//   - A token made with "Test mode" ticked checks contacts without keeping
//     them, and answers with no qsoid. Solid Copy stops then, marks
//     nothing, and says so, rather than marking contacts Club Log doesn't
//     have.
// The callsign sent is the contact's own station callsign ("My callsign"),
// or the current profile's if the contact has none.

import Foundation

@MainActor
enum ClubLogUpload {
    static let endpoint = URL(string: "https://clublog.org/api/v1/qso")!
    static let pause: TimeInterval = 1.1

    static var running: Bool { OneByOneUpload.running.contains(.clubLog) }

    // The token (from the Keychain), and your callsign when a contact has
    // none; the checks use pretend ones.
    static var token: () -> String = { Settings.clubLogToken }
    static var myCall: () -> String = { Settings.currentProfile.station["station_callsign"] ?? "" }
    // The checks don't wait between contacts.
    static var pauseNow: TimeInterval = pause

    static func upload(_ contacts: [QSO], logbook: Logbook,
                       progress: (String) -> Void = { _ in }) async -> UploadReport {
        guard !logbook.isTest else { return .testLog }
        let token = token()
        guard !token.isEmpty else {
            return UploadReport(text: "Club Log: add your Club Log token in Settings > Uploads.", ok: false)
        }
        let fallback = myCall()
        // The callsign in the request now, so a refusal can name it: "the
        // callsign isn't on your account" is only useful if you know
        // which callsign was sent.
        var sent = ""
        return await OneByOneUpload.upload(contacts, to: .clubLog, logbook: logbook, pause: pauseNow, prepare: { qso in
            sent = callsign(for: qso, myCall: fallback)
            return try request(for: qso, token: token, myCall: fallback)
        }, read: { data, response in
            answer(status: response.statusCode, data: data, call: sent)
        }, progress: progress)
    }

    // The contact's own station callsign, or yours if it has none.
    static func callsign(for qso: QSO, myCall: String) -> String {
        (qso["station_callsign"].isEmpty ? myCall : qso["station_callsign"])
            .trimmingCharacters(in: .whitespaces).uppercased()
    }

    static func request(for qso: QSO, token: String, myCall: String) throws -> URLRequest {
        let call = callsign(for: qso, myCall: myCall)
        guard !call.isEmpty else {
            throw NotSent(reason: "it has no station callsign (add My callsign in Edit Contact, or in your profile)")
        }
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["call": call, "adif": LogExport.adifRecord(qso)])
        return request
    }

    // What Club Log's answer means. The HTTP status says most of it; the
    // JSON's "status" tells a duplicate from an update, and "message" is
    // Club Log's reason in its own words.
    // call is the callsign that was sent, named in a 403.
    static func answer(status: Int, data: Data, call: String = "") -> ContactAnswer {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        // "message" is what the knowledge base shows; "error" is read too,
        // in case an answer uses that instead, so Club Log's own words are
        // never lost.
        let message = ((json?["message"] as? String) ?? (json?["error"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let state = ((json?["status"] as? String) ?? "").lowercased()
        let said = message.isEmpty ? "" : " Club Log said: \(message)" + (message.hasSuffix(".") ? "" : ".")
        switch status {
        case 200, 201:
            if state == "duplicate" { return .alreadyThere }
            // A test-mode token: checked, not kept (qsoid is null).
            if json?["qsoid"] is NSNull {
                return .stop("Your Club Log token is a test-mode token, so Club Log checked the contacts "
                             + "but didn't keep them. Make a token without Test mode ticked.", tryAgain: false)
            }
            if status == 201 || state == "updated" || state == "created" { return .added }
            return .stop("Club Log's answer wasn't understood, so nothing more was sent.", tryAgain: false)
        case 422:
            return .refused(message.isEmpty ? "Club Log gave no reason" : "Club Log said: \(message)")
        case 401:
            return .stop("Club Log didn't accept your token. On clublog.org, open Settings, then API, make a new "
                         + "token, and paste it in Settings > Uploads.\(said)", tryAgain: false)
        case 403:
            let which = call.isEmpty ? "the callsign" : call
            return .stop("Club Log said \(which) isn't on the account your token belongs to. On clublog.org, "
                         + "check that \(which) is one of your account's callsigns, or make the token on the "
                         + "account that has it. If \(which) is wrong, fix My callsign in your profile or the "
                         + "contact.\(said)", tryAgain: false)
        case 429:
            return .stop("Club Log asked for a pause; the rest can go later.", tryAgain: true)
        case 500...599:
            return .stop("Club Log had a problem; try again later.", tryAgain: true)
        default:
            return .stop("Club Log answered with error \(status).\(said)", tryAgain: false)
        }
    }
}
