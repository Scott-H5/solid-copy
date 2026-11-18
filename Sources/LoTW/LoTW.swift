// LoTW.swift
//
// Logbook of the World (LoTW), the ARRL's confirmation service: the rules,
// without any windows or network, so they can be checked on their own
// (tools/check-lotw.sh). LoTWSync.swift does the work.
//
// Uploading: contacts are signed with your callsign certificate by TQSL,
// the ARRL's own program, which then sends them. Solid Copy writes the
// contacts to an ADIF file and runs TQSL in batch mode (no window, unless
// TQSL needs to ask for a passphrase):
//   tqsl -x -d -u -a compliant -l "<station location>" -t <log> <file.adi>
//   -x batch, -d no date-range question, -u upload, -a compliant (sign the
//   contacts it can, skip any it can't), -l the station location, -t a
//   diagnostic log, whose last line is "Final Status: …".
// TQSL keeps its own record of what it has sent, so a contact already on
// LoTW is skipped, not sent twice. (Options and statuses from
// https://lotw.arrl.org/lotw-help/cmdline/, read 16 November 2026.)
//
// Downloading confirmations: LoTW's report service
//   https://lotw.arrl.org/lotwuser/lotwreport.adi?login=…&password=…
//     &qso_query=1&qso_qsl=yes&qso_qslsince=<date>
// answers with ADIF: a header with APP_LoTW_LASTQSL (send it back next
// time, so only newer confirmations come), and a record for each
// confirmation (CALL, BAND, MODE, QSO_DATE, TIME_ON, QSL_RCVD, QSLRDATE,
// APP_LoTW_MODEGROUP). If the login is wrong or anything fails, it sends a
// web page instead, with no <EOH>. ARRL documents only this form, with the
// login in the address; it travels encrypted (HTTPS). (From
// https://lotw.arrl.org/lotw-help/developer-query-qsos-qsls/, read
// 16 November 2026.)
//
// Matching a confirmation to a contact, as ARRL suggests: the same call
// and band, within 30 minutes; the mode only to choose between several.

import Foundation

enum LoTW {

    static let reportURL = URL(string: "https://lotw.arrl.org/lotwuser/lotwreport.adi")!
    // The first download asks for every confirmation since this day.
    static let beginning = "1900-01-01"
    // How far apart a contact and a confirmation may be in time.
    static let matchWindow: TimeInterval = 30 * 60

    // MARK: - Upload

    // The contacts to upload: not uploaded yet (or confirmed, which means
    // they were), from the chosen day on ("2020-01-01", or "" for all).
    static func toUpload(_ contacts: [QSO], from day: String) -> [QSO] {
        let start = day.isEmpty ? nil : QSO.date(adifDate: day.filter(\.isNumber), adifTime: "000000")
        return contacts.filter { qso in
            qso["lotw_qsl_sent"].uppercased() != "Y" && qso["lotw_qsl_rcvd"].uppercased() != "Y"
                && start.map { qso.timeOn >= $0 } ?? true
        }
    }

    // TQSL's command line for a file, a location and a log.
    static func tqslArguments(file: URL, location: String, log: URL) -> [String] {
        ["-x", "-d", "-u", "-a", "compliant", "-l", location, "-t", log.path, file.path]
    }

    // How a TQSL run went, from its diagnostic log.
    enum UploadResult: Equatable {
        case sent             // signed and uploaded
        case alreadySent      // nothing new: every contact was on LoTW already
        case someAlreadySent  // the new ones sent; the rest were already there
        case failed(String)   // why, in words

        // The contacts can be counted as uploaded.
        var uploaded: Bool { if case .failed = self { return false } else { return true } }
    }

    // The contacts TQSL skipped, from its output: for each one it prints
    // why ("The Station Location 'Gridsquare' has value 'EN82' while QSO
    // has 'EN83'"), then the contact, a field per line (CALL: KB3QQQ,
    // QSO_DATE: 19980322, TIME_ON: 202500, ...). Found on the author's first
    // real sync, 16 November 2026: a station location with its grid's
    // letters swapped skipped all 154 contacts.
    struct Skipped: Equatable {
        // "CALL QSO_DATE TIME_ON" of each (Skipped.key(for:) for a contact).
        var keys: Set<String> = []
        // The first reason given, in TQSL's words.
        var reason = ""
        // Each one as said: "VE6AAA on 13 December 2025", in TQSL's order.
        // TQSL's reason doesn't name the contact, so this is how you know
        // which to fix (the author, 16 November 2026).
        var named: [String] = []
        static func key(for qso: QSO) -> String { "\(Callsign.normalized(qso.call)) \(qso.adifDate) \(qso.adifTime)" }

        // "VE6AAA on 13 December 2025", or the first five and "and 3 more".
        var list: String {
            named.prefix(5).joined(separator: "; ") + (named.count > 5 ? "; and \(named.count - 5) more" : "")
        }

        // "20251213" -> "13 December 2025" (as said elsewhere in Solid Copy).
        static func spokenDate(_ adif: String) -> String {
            guard let date = QSO.date(adifDate: adif, adifTime: "000000") else { return adif }
            return dateWords.string(from: date)
        }
        private static let dateWords: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_GB")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "d MMMM yyyy"
            return formatter
        }()
    }

    // Each problem TQSL reports is a line ending "on line N" ("Invalid
    // contact - QSO does not specify a band or frequency on line 2081"),
    // then the contact. "Previously Signed QSO detected" isn't a problem:
    // that contact is on LoTW already (signed before, or a repeat of one
    // earlier in the same file, as with the author's VE3XYZ entered three
    // times), so it isn't counted as skipped.
    static func skipped(in output: String) -> Skipped {
        var result = Skipped()
        var counting = false
        var call = "", date = ""
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.range(of: #" on line \d+$"#, options: .regularExpression) != nil {
                counting = !line.lowercased().hasPrefix("previously signed")
                let reason = line.replacingOccurrences(of: #" on line \d+$"#, with: "", options: .regularExpression)
                if counting, result.reason.isEmpty { result.reason = reason }
                call = ""
                date = ""
                continue
            }
            guard counting else { continue }
            if line.hasPrefix("CALL:") { call = Callsign.normalized(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
            if line.hasPrefix("QSO_DATE:") { date = line.dropFirst(9).trimmingCharacters(in: .whitespaces) }
            if line.hasPrefix("TIME_ON:"), !call.isEmpty, !date.isEmpty {
                var time = line.dropFirst(8).trimmingCharacters(in: .whitespaces)
                if time.count == 4 { time += "00" }
                if result.keys.insert("\(call) \(date) \(time)").inserted {
                    result.named.append("\(call) on \(Skipped.spokenDate(date))")
                }
                counting = false
            }
        }
        return result
    }

    // Reads TQSL's log: its "Final Status" line, and the passphrase problem
    // (TQSL can't unlock the certificate), which needs saying plainly.
    static func uploadResult(fromLog log: String) -> UploadResult {
        let lower = log.lowercased()
        if lower.contains("bad decrypt") || lower.contains("operator aborted") {
            return .failed("TQSL couldn't unlock your callsign certificate: its passphrase wasn't given. "
                + "Nothing was uploaded.")
        }
        // No certificate for the call (none yet, or expired): TQSL signs
        // nothing, and says code 8, the same as "all already on LoTW".
        // Found 16 November 2026, while the author's new certificate was on its
        // way: Solid Copy took it for "already uploaded" and marked 156.
        if lower.contains("no valid callsign certificate") || lower.contains("signing aborted") {
            return .failed("TQSL has no usable callsign certificate for this call, so it signed nothing. "
                + "Load your certificate in TQSL, then sync again.")
        }
        guard let line = log.split(whereSeparator: \.isNewline).last(where: { $0.contains("Final Status:") }) else {
            return .failed("TQSL stopped without saying how it went. Nothing was counted as uploaded.")
        }
        let status = line.components(separatedBy: "Final Status:").last?
            .trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        // Codes 0, 8 and 9 (ARRL's list), by their words or their number.
        func says(_ words: [String], _ code: Int) -> Bool {
            words.contains { status.contains($0) } || status.hasSuffix("(\(code))")
        }
        if says(["success"], 0) { return .sent }
        // Code 8 counts as "already on LoTW" only when TQSL says the
        // contacts were duplicates; otherwise nothing was sent.
        if says(["no qsos"], 8) {
            // Repeats are on LoTW already; any real skips among them stay
            // unmarked (LoTWSync leaves them out) and are said.
            if lower.contains("duplicate") || lower.contains("already uploaded") || lower.contains("previously signed") {
                return .alreadySent
            }
            let skipped = skipped(in: log)
            if !skipped.keys.isEmpty {
                // TQSL's reason first: it says whether the contact or the
                // station location is wrong.
                return .failed("TQSL signed nothing. \(skipped.keys.count == 1 ? "1 contact couldn't" : "\(skipped.keys.count) contacts couldn't") "
                    + "be signed: \(skipped.list). TQSL said: \(skipped.reason). Fix it in Edit Contact "
                    + "(or, if TQSL names your station, the station location in TQSL), then sync again.")
            }
            let words = line.components(separatedBy: "Final Status:").last?.trimmingCharacters(in: .whitespaces) ?? ""
            return .failed("TQSL uploaded nothing. It said: \(words).")
        }
        if says(["some qsos", "duplicate"], 9) { return .someAlreadySent }
        if says(["connection"], 11) { return .failed("TQSL couldn't reach LoTW. Check the internet, and try again.") }
        if says(["rejected"], 2) { return .failed("LoTW rejected the upload.") }
        if says(["cancel"], 1) { return .failed("The upload was cancelled in TQSL.") }
        if says(["input file"], 6) { return .failed("TQSL couldn't open the contacts file.") }
        let shown = line.components(separatedBy: "Final Status:").last?.trimmingCharacters(in: .whitespaces) ?? ""
        return .failed("TQSL said: \(shown). Nothing was counted as uploaded.")
    }

    // MARK: - Download

    struct Confirmation: Equatable {
        var call: String
        var band: String
        var mode: String
        var time: Date
        var confirmedOn: String   // QSLRDATE, YYYYMMDD
    }

    struct Report {
        var confirmations: [Confirmation]
        // APP_LoTW_LASTQSL, to send back next time, or "" if none.
        var lastQSL: String
    }

    // The address to ask for confirmations since a time (LoTW's own
    // lastQSL, or the beginning).
    static func reportRequest(username: String, password: String, since: String) -> URL? {
        var parts = URLComponents(url: reportURL, resolvingAgainstBaseURL: false)
        parts?.queryItems = [
            URLQueryItem(name: "login", value: username), URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "qso_query", value: "1"), URLQueryItem(name: "qso_qsl", value: "yes"),
            URLQueryItem(name: "qso_qslsince", value: since.isEmpty ? beginning : since),
        ]
        // "+" would be read as a space: spell it out, in a password too.
        let query = parts?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        parts?.percentEncodedQuery = query
        return parts?.url
    }

    // Reads LoTW's answer, or throws with what LoTW said (its page's text)
    // if it isn't a report.
    static func report(from data: Data) throws -> Report {
        let text = String(decoding: data, as: UTF8.self)
        guard text.range(of: "<eoh>", options: .caseInsensitive) != nil else {
            let page = text.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            throw DatabaseError(message: "LoTW didn't send confirmations"
                + (page.isEmpty ? "." : ". It said: " + String(page.prefix(200))))
        }
        var lastQSL = ""
        if let tag = text.range(of: #"<APP_LoTW_LASTQSL:(\d+)>"#, options: [.regularExpression, .caseInsensitive]) {
            let length = Int(text[tag].filter(\.isNumber)) ?? 0
            lastQSL = String(text[tag.upperBound...].prefix(length))
        }
        let confirmations = ADIFImport.records(in: data).compactMap { record -> Confirmation? in
            guard (record["qsl_rcvd"] ?? "").uppercased() == "Y", let call = record["call"], !call.isEmpty,
                  let time = QSO.date(adifDate: record["qso_date"] ?? "", adifTime: record["time_on"] ?? "")
            else { return nil }
            return Confirmation(call: Callsign.normalized(call), band: (record["band"] ?? "").lowercased(),
                                mode: record["app_lotw_modegroup"] ?? record["mode"] ?? "", time: time,
                                confirmedOn: record["qslrdate"] ?? "")
        }
        return Report(confirmations: confirmations, lastQSL: lastQSL)
    }

    // The fields a confirmation sets: confirmed, its date, and uploaded
    // (a service that confirms a contact has it). LoTW's, or QRZ
    // Logbook's (QRZLogbookSync.swift), which matches the same way.
    struct Marks {
        var status: String, date: String, sent: String
        static let lotw = Marks(status: "lotw_qsl_rcvd", date: "lotw_qslrdate", sent: "lotw_qsl_sent")
        static let qrzLogbook = Marks(status: "qrzcom_qso_download_status", date: "qrzcom_qso_download_date",
                                      sent: "qrzcom_qso_upload_status")
    }

    // Each confirmation's contact: the same call and band within 30
    // minutes; among several, the same kind of mode, then the nearest in
    // time. Returns the contacts changed (confirmed, and counted as
    // uploaded) and the confirmations that matched nothing in the log.
    static func apply(_ confirmations: [Confirmation], to contacts: [QSO],
                      marks: Marks = .lotw) -> (changed: [QSO], unmatched: [Confirmation]) {
        var byCall: [String: [Int]] = [:]
        for (index, qso) in contacts.enumerated() { byCall[Callsign.normalized(qso.call), default: []].append(index) }
        var changed: [Int: QSO] = [:]
        var unmatched: [Confirmation] = []
        for confirmation in confirmations {
            let near = (byCall[confirmation.call] ?? []).filter { index in
                let qso = contacts[index]
                return qso["band"].lowercased() == confirmation.band
                    && abs(qso.timeOn.timeIntervalSince(confirmation.time)) <= matchWindow
            }
            let sameMode = near.filter { Spot.group(of: contacts[$0]["mode"]) == Spot.group(of: confirmation.mode) }
            let pool = sameMode.isEmpty ? near : sameMode
            guard let index = pool.min(by: {
                abs(contacts[$0].timeOn.timeIntervalSince(confirmation.time))
                    < abs(contacts[$1].timeOn.timeIntervalSince(confirmation.time))
            }) else {
                unmatched.append(confirmation)
                continue
            }
            var qso = changed[index] ?? contacts[index]
            // No date from the service: a date already there is kept.
            let date = confirmation.confirmedOn.isEmpty ? qso[marks.date] : confirmation.confirmedOn
            let wasConfirmed = qso[marks.status].uppercased() == "Y" && qso[marks.date] == date
            guard !wasConfirmed else { continue }
            qso[marks.status] = "Y"
            qso[marks.date] = date
            if qso[marks.sent].uppercased() != "Y" { qso[marks.sent] = "Y" }
            changed[index] = qso
        }
        return (changed.keys.sorted().map { changed[$0]! }, unmatched)
    }
}
