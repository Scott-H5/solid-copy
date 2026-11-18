// QRZLogbook.swift
//
// The rules for uploading to QRZ Logbook (logbook.qrz.com), kept apart from
// the network so the checks can test them (tools/check-uploads.sh). The
// uploading itself is in QRZLogbookUpload.swift.
//
// How QRZ's Logbook API works (its Developer Guide, read 16 November 2026):
//   - One web address, https://logbook.qrz.com/api, sent a form (POST) of
//     name=value pairs: KEY (your logbook's API key, from the logbook's
//     Settings on qrz.com), ACTION=INSERT, and ADIF (one contact).
//   - It answers the same way: RESULT=OK&LOGID=130877825&COUNT=1, or
//     RESULT=FAIL&REASON=..., or RESULT=AUTH when the key isn't allowed
//     (uploading needs a QRZ subscription).
//   - One contact per INSERT. A contact already in the logbook fails with
//     a reason that says "duplicate".
//   - Every app must name itself in its User-Agent (OneByOneUpload
//     sends "SolidCopy/<version>", nothing about you).
// A logbook is for one callsign, so the contact's station callsign must be
// that logbook's (QRZ refuses it otherwise, and says so).

import Foundation

enum QRZLogbook {
    static let endpoint = URL(string: "https://logbook.qrz.com/api")!

    // The form sent for one contact, ready to post.
    static func insertBody(key: String, qso: QSO) -> Data {
        let pairs = [("KEY", key), ("ACTION", "INSERT"), ("ADIF", LogExport.adifRecord(qso))]
        return Data(pairs.map { "\($0)=\(OneByOneUpload.formEncoded($1))" }.joined(separator: "&").utf8)
    }

    static func answer(from data: Data) -> ContactAnswer {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        var fields: [String: String] = [:]
        // REASON can hold an & of its own, so it runs to the end of the
        // answer when it's last (as QRZ sends it).
        if let range = text.range(of: "REASON=") {
            fields["REASON"] = String(text[range.upperBound...]).removingPercentEncoding ?? ""
        }
        let head = text.range(of: "REASON=").map { String(text[..<$0.lowerBound]) } ?? text
        for pair in head.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { fields[parts[0].uppercased()] = parts[1].removingPercentEncoding ?? parts[1] }
        }
        let reason = plainReason(fields["REASON"] ?? "")
        switch (fields["RESULT"] ?? "").uppercased() {
        case "OK", "REPLACE": return .added
        case "AUTH":
            return .stop("QRZ didn't allow it: uploading needs a QRZ subscription, and the API key "
                         + "of your logbook. \(reason)".trimmingCharacters(in: .whitespaces), tryAgain: false)
        case "FAIL":
            let lower = reason.lowercased()
            if lower.contains("duplicate") { return .alreadyThere }
            if lower.contains("key") || lower.contains("auth") || lower.contains("subscri") {
                return .stop("QRZ said: \(reason).", tryAgain: false)
            }
            return .refused(reason.isEmpty ? "QRZ gave no reason" : reason)
        default:
            return .refused(text.isEmpty ? "QRZ sent an empty answer" : "QRZ's answer wasn't understood")
        }
    }

    // QRZ's reason in plain words. QRZ sends things like
    //   "QRZ Internal Error: Unable to add QSO to database.&EXTENDED=add_qso: outside date range,"
    // (16 November 2026, for contacts older than the logbook's start).
    // The EXTENDED part is the real reason; the rest is QRZ's wrapping.
    // Reasons Solid Copy knows are said in its own words, saying what to
    // do; others are passed on, tidied.
    static func plainReason(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let extended = text.range(of: "&EXTENDED=", options: .caseInsensitive) {
            let detail = String(text[extended.upperBound...])
            // The detail if there is one, otherwise what came before it.
            text = detail.trimmingCharacters(in: .whitespaces).isEmpty ? String(text[..<extended.lowerBound]) : detail
        }
        for prefix in ["QRZ Internal Error:", "add_qso:"] {
            if text.lowercased().hasPrefix(prefix.lowercased()) { text = String(text.dropFirst(prefix.count)) }
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,;&.\n\t"))
        let lower = text.lowercased()
        if lower.contains("outside date range") {
            return "its date is outside your QRZ logbook's date range (change the range in the logbook's "
                + "settings on qrz.com, then upload again)"
        }
        // "freq_to_band: cannot determine band from , ... qso_hash:
        // required field missing band1, ..." (VE6AAA, 16 November 2026).
        if lower.contains("cannot determine band") || lower.contains("missing band") {
            return "it has no band or frequency (add one in Edit Contact, then upload again)"
        }
        // Anything else: QRZ repeats itself ("a, b, a, b,"), so each part
        // once, without QRZ's own labels ("freq_to_band:").
        var parts: [String] = []
        for part in text.split(separator: ",") {
            var piece = part.trimmingCharacters(in: .whitespaces)
            if let colon = piece.firstIndex(of: ":"), !piece[..<colon].contains(" ") {
                piece = piece[piece.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            if !piece.isEmpty, !parts.contains(piece) { parts.append(piece) }
        }
        return parts.isEmpty ? text : parts.joined(separator: "; ")
    }
}
