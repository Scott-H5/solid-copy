// QRZLogbookSync.swift
//
// Gets confirmations from QRZ Logbook and marks them in the log (CLAUDE.md
// v1 item 4), as LoTW's Sync does. QSL > Sync with QRZ Logbook uploads
// new contacts first (QRZLogbookUpload.swift), then comes here.
//
// How QRZ's FETCH works (its Logbook API Developer Guide, last updated 7
// March 2025, read 17 November 2026):
//   - The same address and form as uploading: KEY, ACTION=FETCH, and
//     OPTION, a comma-separated list. Solid Copy sends
//     STATUS:CONFIRMED,MAX:250,AFTERLOGID:<n>: only confirmed contacts,
//     250 at a time, from log ID n on.
//   - The answer: RESULT=OK&COUNT=...&LOGIDS=...&ADIF=<the records>. With
//     250 records there may be more: ask again from the highest
//     APP_QRZLOG_LOGID plus one, until fewer come (QRZ's own advice).
//   - It needs a QRZ subscription, like uploading.
// The guide doesn't name the field that says a record is confirmed. As
// Solid Copy asks for confirmed records only, every record that comes is
// taken as confirmed, unless it carries APP_QRZLOG_STATUS with something
// other than C (what other loggers read). The date is APP_QRZLOG_QSLDATE
// if QRZ sends one; with none, a date already in the log is kept.
// Each confirmation is matched to a contact as LoTW's are (LoTW.apply):
// the same call and band within 30 minutes, the mode to choose between
// several. Everything QRZ has is fetched each time (a few requests for a
// log of thousands): a confirmation can arrive for an old contact, so
// asking only for newer log IDs would miss it.

import Foundation

enum QRZLogbookFetch {
    static let pageSize = 250

    static func fetchBody(key: String, afterLogID: Int) -> Data {
        let option = "STATUS:CONFIRMED,MAX:\(pageSize),AFTERLOGID:\(afterLogID)"
        let pairs = [("KEY", key), ("ACTION", "FETCH"), ("OPTION", option)]
        return Data(pairs.map { "\($0)=\(OneByOneUpload.formEncoded($1))" }.joined(separator: "&").utf8)
    }

    // One page of QRZ's answer.
    struct Page: Equatable {
        var confirmations: [LoTW.Confirmation]
        var records: Int        // how many came, to know if there's more
        var highestLogID: Int   // for the next page
    }

    enum Answer: Equatable {
        case page(Page)
        case problem(String)    // stop: what's wrong, in plain words
    }

    static func answer(from data: Data) -> Answer {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // The ADIF holds < > and maybe & of its own, so it's taken whole,
        // from ADIF= to its last <eor>, before the rest is read as pairs.
        var adif = ""
        var head = text
        if let start = text.range(of: "ADIF=", options: .caseInsensitive) {
            let rest = text[start.upperBound...]
            let end = rest.range(of: "<eor>", options: [.caseInsensitive, .backwards])?.upperBound ?? rest.endIndex
            adif = String(rest[..<end])
            head = String(text[..<start.lowerBound]) + String(rest[end...])
        }
        // QRZ may send the ADIF percent-encoded or as web text (&lt;).
        if adif.contains("%3C") || adif.contains("%3c") { adif = adif.removingPercentEncoding ?? adif }
        if adif.contains("&lt;") {
            adif = adif.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
        }
        var fields: [String: String] = [:]
        if let range = head.range(of: "REASON=") {
            fields["REASON"] = String(head[range.upperBound...]).removingPercentEncoding ?? ""
            head = String(head[..<range.lowerBound])
        }
        for pair in head.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { fields[parts[0].uppercased()] = parts[1].removingPercentEncoding ?? parts[1] }
        }
        let reason = QRZLogbook.plainReason(fields["REASON"] ?? "")
        switch (fields["RESULT"] ?? "").uppercased() {
        case "OK": break
        case "AUTH":
            return .problem("QRZ didn't allow it: getting confirmations needs a QRZ subscription, and the API key "
                            + "of your logbook.")
        case "FAIL":
            // Nothing confirmed (yet) is an empty page, not a problem.
            let lower = reason.lowercased()
            if fields["COUNT"] == "0" || lower.contains("no log entries") || lower.contains("not found")
                || lower.contains("no qso") || lower.contains("no records") {
                return .page(Page(confirmations: [], records: 0, highestLogID: 0))
            }
            return .problem("QRZ said: \(reason.isEmpty ? "it couldn't fetch the confirmations" : reason).")
        default:
            return .problem(text.isEmpty ? "QRZ sent an empty answer." : "QRZ's answer wasn't understood.")
        }

        let records = ADIFImport.records(in: Data(adif.utf8))
        var highest = 0
        let confirmations = records.compactMap { record -> LoTW.Confirmation? in
            highest = max(highest, Int(record["app_qrzlog_logid"] ?? "") ?? 0)
            if let status = record["app_qrzlog_status"], !status.isEmpty, status.uppercased() != "C" { return nil }
            guard let call = record["call"], !call.isEmpty,
                  let time = QSO.date(adifDate: record["qso_date"] ?? "", adifTime: record["time_on"] ?? "")
            else { return nil }
            let date = (record["app_qrzlog_qsldate"] ?? record["qrzcom_qso_download_date"] ?? "").filter(\.isNumber)
            return LoTW.Confirmation(call: Callsign.normalized(call), band: (record["band"] ?? "").lowercased(),
                                     mode: record["mode"] ?? "", time: time,
                                     confirmedOn: date.count == 8 ? date : "")
        }
        return .page(Page(confirmations: confirmations, records: records.count, highestLogID: highest))
    }
}

@MainActor
enum QRZLogbookSync {
    private(set) static var running = false
    // Enough pages for 25,000 confirmations: a stop, should paging ever
    // go wrong, so it can't ask QRZ forever.
    static let mostPages = 100

    // Uploads, then gets confirmations. Returns the summary, a sentence
    // or two per step.
    static func sync(_ logbook: Logbook, progress: @escaping (String) -> Void) async -> String {
        guard !logbook.isTest else { return UploadReport.testLogText }
        let toSend = UploadService.qrzLogbook.toUpload(logbook.contacts, from: Settings.qrzUploadFrom)
        let upload = await QRZLogbookUpload.upload(toSend, logbook: logbook, progress: progress)
        return upload.text + "\n\n" + (await download(logbook, progress: progress))
    }

    static func download(_ logbook: Logbook, progress: (String) -> Void) async -> String {
        guard !logbook.isTest else { return UploadReport.testLogText }
        guard !running else { return "Confirmations: already being fetched." }
        let key = QRZLogbookUpload.key()
        guard !key.isEmpty else { return "Confirmations: add your logbook's API key in Settings > Uploads." }
        running = true
        defer { running = false }
        progress("Getting confirmations from QRZ Logbook.")

        var confirmations: [LoTW.Confirmation] = []
        var after = 0
        for _ in 0..<mostPages {
            var request = URLRequest(url: QRZLogbook.endpoint, timeoutInterval: 60)
            request.httpMethod = "POST"
            request.setValue(OneByOneUpload.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = QRZLogbookFetch.fetchBody(key: key, afterLogID: after)
            let answer: QRZLogbookFetch.Answer
            do {
                let (data, response) = try await OneByOneUpload.send(request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    return "Confirmations: QRZ answered with an error. Try again later."
                }
                answer = QRZLogbookFetch.answer(from: data)
            } catch {
                return "Confirmations: QRZ couldn't be reached. \(error.localizedDescription)"
            }
            switch answer {
            case .problem(let why): return "Confirmations: " + why
            case .page(let page):
                confirmations += page.confirmations
                // A full page means there may be more, from past the last.
                // (No log IDs to go on: stop, rather than fetch the same page again.)
                guard page.records >= QRZLogbookFetch.pageSize, page.highestLogID > 0, page.highestLogID >= after
                else { break }
                after = page.highestLogID + 1
                continue
            }
            break
        }

        let (changed, unmatched) = LoTW.apply(confirmations, to: logbook.contacts, marks: .qrzLogbook)
        do { try logbook.updateAll(changed) } catch {
            return "Confirmations came, but the log couldn't be changed: \(error.localizedDescription)"
        }
        var text = changed.isEmpty ? "Confirmations: none new."
            : "Confirmations: \(changed.count == 1 ? "1 contact" : "\(changed.count) contacts") newly confirmed by QRZ Logbook."
        if !unmatched.isEmpty {
            let some = unmatched.prefix(10).map { "\($0.call) \($0.band) \(QSO(call: $0.call, timeOn: $0.time).utcDateText)" }
            text += " \(unmatched.count) matched nothing in this log (logged elsewhere?): "
                + some.joined(separator: ", ") + (unmatched.count > 10 ? ", and more." : ".")
        }
        return text
    }
}
