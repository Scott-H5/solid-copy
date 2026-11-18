// EQSLUpload.swift
//
// Sends contacts to eQSL (eqsl.cc), one per request, through the shared
// loop (OneByOneUpload.swift).
//
// How eQSL's upload works (its ImportADIF.txt, revised 1 March 2026, and
// ADIFContentSpecs, read 17 November 2026):
//   - POST https://www.eqsl.cc/qslcard/ImportADIF.cfm as a file upload
//     ("multipart/form-data"): the fields EQSL_USER and EQSL_PSWD (your
//     eQSL login, sent plainly, which is why it must be https), and
//     Filename, an ADIF file. The file needs a name ending in .adi, and at
//     least one <EOR>.
//   - If you have more than one eQSL account for your callsign (a "QTH
//     Nickname" each), APP_EQSL_QTH_NICKNAME in the record says which.
//     Without it eQSL picks by the contact's date.
//   - The answer is a web page meant to be read by programs, one message
//     per line: "Result: 1 out of 1 records added", "Warning: Y=2025 M=12
//     D=17 Bad record: Duplicate", "Warning: ... Bad Mode: XYZ",
//     "Error: No match on eQSL_User/eQSL_Pswd" and so on. "Caution:" and
//     "Information:" lines don't matter for whether it was added.
//   - eQSL states no rate limit. Solid Copy waits a second between
//     contacts anyway, to be gentle with a free service.
// The card's message is QSLMSG; Notes and Comment never go (LogExport
// leaves Notes out, and eQSL keeps Comment private anyway).

import Foundation

@MainActor
enum EQSLUpload {
    static let endpoint = URL(string: "https://www.eqsl.cc/qslcard/ImportADIF.cfm")!
    static let pause: TimeInterval = 1

    static var running: Bool { OneByOneUpload.running.contains(.eqsl) }

    // The login and QTH Nickname (Settings > Uploads; the password from
    // the Keychain); the checks use pretend ones.
    static var login: () -> (user: String, password: String, nickname: String) = {
        (Settings.eqslUsername, Settings.eqslPassword, Settings.eqslQTHNickname)
    }
    static var pauseNow: TimeInterval = pause

    static func upload(_ contacts: [QSO], logbook: Logbook,
                       progress: (String) -> Void = { _ in }) async -> UploadReport {
        guard !logbook.isTest else { return .testLog }
        let login = login()
        guard !login.user.isEmpty, !login.password.isEmpty else {
            return UploadReport(text: "eQSL: add your eQSL username and password in Settings > Uploads.", ok: false)
        }
        return await OneByOneUpload.upload(contacts, to: .eqsl, logbook: logbook, pause: pauseNow, prepare: { qso in
            request(for: qso, user: login.user, password: login.password, nickname: login.nickname)
        }, read: { data, response in
            guard response.statusCode == 200 else {
                return .stop("eQSL answered with an error; try again later.", tryAgain: true)
            }
            return answer(String(decoding: data, as: UTF8.self))
        }, progress: progress)
    }

    // The ADIF file for one contact: a header naming Solid Copy, then the
    // record, with the QTH Nickname if you set one.
    static func file(for qso: QSO, nickname: String) -> String {
        var record = LogExport.adifRecord(qso)
        let nick = nickname.trimmingCharacters(in: .whitespaces)
        if !nick.isEmpty, record.hasSuffix("<EOR>") {
            record = String(record.dropLast(5)) + "<APP_EQSL_QTH_NICKNAME:\(nick.utf8.count)>\(nick) <EOR>"
        }
        return "Solid Copy upload\n<PROGRAMID:10>Solid Copy <EOH>\n\(record)\n"
    }

    static func request(for qso: QSO, user: String, password: String, nickname: String) -> URLRequest {
        let boundary = "SolidCopy-\(UUID().uuidString)"
        var body = ""
        for (name, value) in [("EQSL_USER", user), ("EQSL_PSWD", password)] {
            body += "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
        }
        body += "--\(boundary)\r\nContent-Disposition: form-data; name=\"Filename\"; filename=\"solidcopy.adi\"\r\n"
            + "Content-Type: text/plain; charset=utf-8\r\n\r\n\(file(for: qso, nickname: nickname))\r\n--\(boundary)--\r\n"
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        return request
    }

    // eQSL's page as plain lines: <BR> ends a line, other tags go.
    static func lines(of page: String) -> [String] {
        page.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func answer(_ page: String) -> ContactAnswer {
        let lines = lines(of: page)
        func first(_ prefix: String) -> String? {
            lines.first { $0.lowercased().hasPrefix(prefix.lowercased()) }
                .map { String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) }
        }
        if let error = first("Error:") {
            let lower = error.lowercased()
            if lower.contains("no match on eqsl_user/eqsl_pswd for date") {
                return .refused("your eQSL account doesn't cover its date (check your callsign's dates in your "
                                + "eQSL profile, or the QTH Nickname in Settings > Uploads)")
            }
            if lower.contains("multiple accounts match") {
                return .stop("You have more than one eQSL account for this callsign. Put the one to use in "
                             + "QTH Nickname, in Settings > Uploads.", tryAgain: false)
            }
            // The QTH Nickname isn't one of this account's QTH profiles. eQSL
            // names the one it was given, so say which, and how to fix it.
            if lower.contains("no match on app_eqsl_qth_nickname") {
                let name = error.range(of: "APP_EQSL_QTH_NICKNAME:", options: .caseInsensitive)
                    .map { String(error[$0.upperBound...]).trimmingCharacters(in: .whitespaces) } ?? ""
                return .stop("eQSL has no QTH profile named \"\(name)\". Check the name in your eQSL profile, "
                             + "or clear QTH Nickname in Settings > Uploads so eQSL picks by date.", tryAgain: false)
            }
            if lower.contains("no match on eqsl_user") || lower.contains("missing eqsl_") {
                return .stop("eQSL didn't accept your username and password. Check them in Settings > Uploads.",
                             tryAgain: false)
            }
            if lower.contains("down") {
                return .stop("eQSL is down for now; the rest can go later.", tryAgain: true)
            }
            return .stop("eQSL said: \(error)", tryAgain: false)
        }
        if lines.contains(where: { $0.range(of: "Bad record: Duplicate", options: .caseInsensitive) != nil }) {
            return .alreadyThere
        }
        let result = first("Result:")
        if let result, let added = Int(result.prefix(while: \.isNumber)), added > 0 { return .added }
        if let warning = first("Warning:") { return .refused(plainWarning(warning)) }
        if result != nil { return .refused("eQSL didn't add it, and gave no reason") }
        return .stop("eQSL's answer wasn't understood, so nothing more was sent.", tryAgain: false)
    }

    // "Y=2025 M=12 D=17 Bad Mode: XYZ" in plain words, saying what to do.
    static func plainWarning(_ raw: String) -> String {
        let text = raw.replacingOccurrences(of: "^Y=\\S+\\s+M=\\S+\\s+D=\\S+\\s*", with: "", options: .regularExpression)
        func value(after label: String) -> String {
            guard let range = text.range(of: label, options: .caseInsensitive) else { return "" }
            return text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        }
        let lower = text.lowercased()
        if lower.contains("bad callsign") { return "eQSL says its callsign, \(value(after: "Bad Callsign:")), isn't valid" }
        if lower.contains("bad mode") {
            return "eQSL doesn't take its mode, \(value(after: "Bad Mode:")) (change it in Edit Contact, then upload again)"
        }
        if lower.contains("bad band") {
            return "it has no band or frequency eQSL knows (add one in Edit Contact, then upload again)"
        }
        if lower.contains("future") { return "its date and time are in the future" }
        if lower.contains("bad qso date") { return "its date isn't one eQSL accepts" }
        if lower.contains("bad sat_mode") { return "eQSL doesn't know its satellite mode" }
        return "eQSL said: \(text)"
    }
}
