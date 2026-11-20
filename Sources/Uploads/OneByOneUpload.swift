// OneByOneUpload.swift
//
// The upload loop QRZ Logbook, Club Log and eQSL share: send contacts one
// at a time, read each answer, mark what the service has, and report in
// plain words. (LoTW is different: TQSL signs a whole file. See
// Sources/LoTW.)
//
// Why one at a time, for all three: each service's answer for a single
// contact says plainly what happened to it. A batch answer would have to
// be matched back to the contacts, and a wrong match would mark a contact
// uploaded when it isn't, or the other way round. Accuracy first; a
// whole log of a few hundred contacts still goes in minutes.
//
// Each service gives three things (QRZLogbookUpload.swift,
// ClubLogUpload.swift, EQSLUpload.swift):
//   - prepare: the request for one contact, or a reason not to send it
//     (say, no station callsign);
//   - read: what the service's answer means (ContactAnswer, below);
//   - pause: seconds between requests, to stay inside the service's
//     limits (Club Log allows 60 a minute).
//
// It stops at the first sign the rest would fail too: no internet, the
// service down, or the login refused. Sending the same failing login
// again and again can get your address blocked (Club Log says so), so a
// login problem stops at once and automatic uploads don't retry it.
// Contacts refused one by one are listed, grouped by reason, and left
// unmarked.

import Foundation

// What a service said about one contact.
enum ContactAnswer: Equatable {
    case added            // it's there now
    case alreadyThere     // a duplicate: it was already there
    case refused(String)  // this contact wasn't taken, and why (a phrase: "its date is ...")
    case stop(String, tryAgain: Bool)  // the rest would fail too: why, and whether later may work

    var inLogbook: Bool { self == .added || self == .alreadyThere }
}

// A contact that isn't sent at all, and why.
struct NotSent: Error { let reason: String }

@MainActor
enum OneByOneUpload {
    // The services uploading now, so a second upload to one waits.
    private(set) static var running: Set<UploadService> = []

    // How a request is sent; the checks swap in a pretend service.
    static var send: (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }

    // How long a long upload goes between "37 of 158" reports.
    static let progressEvery: TimeInterval = 30

    // Every app names itself to the services. Solid Copy sends
    // "SolidCopy/<version>", nothing about you.
    static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "SolidCopy/\(version)"
    }

    static func upload(_ contacts: [QSO], to service: UploadService, logbook: Logbook,
                       pause: TimeInterval,
                       prepare: (QSO) throws -> URLRequest,
                       read: (Data, HTTPURLResponse) -> ContactAnswer,
                       progress: (String) -> Void) async -> UploadReport {
        let name = service.name
        guard !logbook.isTest else { return .testLog }
        guard !running.contains(service) else { return UploadReport(text: "\(name): an upload is already running.", ok: false) }
        guard !contacts.isEmpty else { return UploadReport(text: "\(name): nothing new to send.", ok: true) }
        running.insert(service)
        defer { running.remove(service) }
        if contacts.count > 1 { progress("Uploading \(count(contacts.count)) to \(name).") }

        var inLogbook: Set<UUID> = []
        var already = 0
        var refused: [(call: String, why: String)] = []
        var stopped: String?
        var tryAgain = false
        var lastProgress = Date()
        for (number, qso) in contacts.enumerated() {
            if number > 0 {
                if pause > 0 { try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000)) }
                if Date().timeIntervalSince(lastProgress) >= progressEvery {
                    progress("\(name): \(number) of \(contacts.count).")
                    lastProgress = Date()
                }
            }
            var request: URLRequest
            do {
                request = try prepare(qso)
            } catch let notSent as NotSent {
                refused.append((qso.call, notSent.reason))
                continue
            } catch {
                refused.append((qso.call, error.localizedDescription))
                continue
            }
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let answer: ContactAnswer
            do {
                let (data, response) = try await send(request)
                guard let http = response as? HTTPURLResponse else {
                    stopped = "\(service.shortName)'s answer wasn't understood."
                    break
                }
                answer = read(data, http)
            } catch {
                stopped = "\(service.shortName) couldn't be reached. \(error.localizedDescription)"
                tryAgain = true
                break
            }
            switch answer {
            case .added: inLogbook.insert(qso.id)
            case .alreadyThere: inLogbook.insert(qso.id); already += 1
            case .refused(let why): refused.append((qso.call, why))
            case .stop(let why, let later): stopped = why; tryAgain = later
            }
            if stopped != nil { break }
        }

        // Marked on the latest copies, so an edit made meanwhile stays.
        let today = QSL.today()
        do {
            try logbook.change(inLogbook) { service.mark(&$0, today: today) }
        } catch {
            return UploadReport(text: "\(name) has them, but the log couldn't be marked: "
                                + error.localizedDescription, ok: false)
        }

        var text = "\(name): "
        let new = inLogbook.count - already
        text += new > 0 ? "added \(count(new))." : inLogbook.isEmpty ? "nothing added." : "nothing new added."
        if already > 0 { text += " \(already == 1 ? "1 was" : "\(already) were") already there; now marked." }
        text += refusals(refused)
        if let stopped {
            let left = contacts.count - inLogbook.count - refused.count
            text += " Stopped. \(stopped)" + (stopped.hasSuffix(".") ? "" : ".")
            if left > 0 { text += " \(count(left)) not sent yet." }
        }
        return UploadReport(text: text, ok: stopped == nil && refused.isEmpty, tryAgain: tryAgain)
    }

    // Refusals grouped by reason, so 24 contacts refused for one reason
    // are one sentence, not 24: " 24 weren't taken, because its date is
    // ...: KB3CFK, AF4CM, ... and 19 more." Reasons in the order first met.
    nonisolated static func refusals(_ refused: [(call: String, why: String)]) -> String {
        var reasons: [String] = []
        var calls: [String: [String]] = [:]
        for item in refused {
            if calls[item.why] == nil { reasons.append(item.why) }
            calls[item.why, default: []].append(item.call)
        }
        return reasons.map { why in
            let list = calls[why] ?? []
            let shown = list.prefix(5).joined(separator: ", ")
                + (list.count > 5 ? ", and \(list.count - 5) more" : "")
            let what = list.count == 1 ? "1 wasn't taken" : "\(list.count) weren't taken"
            // "because its date is ..." reads for one contact or many.
            return " \(what), because \(why): \(shown)."
        }.joined()
    }

    // Only letters, digits and - . _ ~ go as they are; everything else
    // (spaces, &, =, <, >, accented letters) as %XX, so nothing in a
    // contact can break a form.
    nonisolated static func formEncoded(_ text: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    private static func count(_ n: Int) -> String { n == 1 ? "1 contact" : "\(n) contacts" }
}
