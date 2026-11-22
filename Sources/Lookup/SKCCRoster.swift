// SKCCRoster.swift
//
// SKCC's member list: every Straight Key Century Club member's number and
// call, which SKCC publishes as one text file (about 2 MB, 31,000
// members). Solid Copy keeps a copy beside the log and fetches a fresh one
// when it's a week old, so looking a call up is instant and works without
// the internet. Nothing about you or your log is sent: it's a plain
// download of a public file.
//
// It's used two ways (ClubNumbers.swift, LogEntryViewController.swift):
//   - Fill in: leaving Callsign puts the member's number in SKCC number,
//     if it's empty, and says it with the lookup.
//   - Check: an SKCC number you type is checked against the call. A
//     number that belongs to someone else means one of the two was
//     miscopied, which a lookup can't catch (a miscopied call is often a
//     real call too).
//
// The file is pipe-separated, with a header line:
//   SKCCNR|CALL|NAME|QTH|SPC|OLDCALL|SKCC|DXCODE|JOINDATE|CENTDATE|TRIBDATE|TX8DATE|SENDATE|DXENTITY
//   3S|N6WK/SK|Gordon|Santa Ana|CA|N6WK|3|291|02 Jan 2006|19 Oct 2006|09 Sep 2007|14 Feb 2013|02 Nov 2013|USA
// The dates (when each member joined and made Centurion, Tribune,
// Tribune x8 and Senator) are kept for the SKCC awards (Awards.swift),
// which count a contact only if both stations had joined, or reached a
// level, by the day of the contact.
// SKCCNR is the number with the member's award letter, if any: C
// Centurion, T Tribune, S Senator. That's what goes in the log (ADIF's
// SKCC field holds it that way). Calls ending /SK (silent keys) and /EX
// (former members) are left out: those calls may since have gone to
// someone else; their dates are still kept, by number, since an old
// contact with them still counts for an award. The file repeats its header now and then in the middle;
// those lines are skipped.

import Foundation

// When an SKCC member joined and reached each level; nil if they haven't.
struct SKCCDates: Equatable {
    var joined: Date?
    var centurion: Date?
    var tribune: Date?
    var tribuneX8: Date?
    var senator: Date?
}

@MainActor
final class SKCCRoster {
    static let shared = SKCCRoster()

    static let url = URL(string: "https://www.skccgroup.com/membership_data/skccdata.txt")!
    // Fetched again when the copy is older than this. Members join daily,
    // but a week-old list knows nearly everyone you'll work.
    static let maximumAge: TimeInterval = 7 * 24 * 60 * 60
    // A real list is about 2 MB; anything much bigger is refused.
    static let maximumBytes = 20 * 1024 * 1024

    struct Members: Equatable {
        // "N6WK" -> "3S"
        var byCall: [String: String] = [:]
        // "3" -> "N6WK": the number without its award letter.
        var byNumber: [String: String] = [:]
        // "3" -> when member 3 joined and reached each level, silent keys
        // and former members too.
        var dates: [String: SKCCDates] = [:]
        var count: Int { byCall.count }
    }

    private(set) var members = Members()
    private(set) var downloading = false
    // When the copy on disk was fetched, or nil if there isn't one.
    private(set) var fetched: Date?
    // Called when a download finishes (Settings > Clubs shows it).
    var onChange: (() -> Void)?

    // MARK: Using it

    // The member's number with award letter ("12345T") for a call
    // (W1AW/P is looked up as W1AW), or nil if the call isn't a member
    // (or the list is off or not loaded).
    func number(for call: String) -> String? {
        guard Settings.skccLookup else { return nil }
        return members.byCall[CallsignLookup.lookupCall(for: Callsign.normalized(call))]
    }

    // Whose number this is ("12345" or "12345T"), or nil.
    func call(forNumber number: String) -> String? {
        guard Settings.skccLookup, let digits = Self.digits(number) else { return nil }
        return members.byNumber[digits]
    }

    // When member "12345" (or "12345T") joined and reached each level.
    func dates(forNumber number: String) -> SKCCDates? {
        guard isReady, let digits = Self.digits(number) else { return nil }
        return members.dates[digits]
    }

    // Whether the list is on and loaded, so a check means something.
    var isReady: Bool { Settings.skccLookup && members.count > 0 }

    // What to say about an SKCC number typed for a call, or nil if it's
    // right (or can't be checked). The call is spelled out for speech
    // by the caller; this gives the words for the screen.
    // callText says a call: as it is for the screen, spelled out for
    // speech (Callsign.spoken).
    func problem(withNumber typed: String, for call: String,
                 callText: (String) -> String = { $0 }) -> String? {
        let typed = typed.trimmingCharacters(in: .whitespaces)
        guard isReady, !typed.isEmpty else { return nil }
        guard let digits = Self.digits(typed) else {
            return "SKCC number \(typed) isn't a number."
        }
        let theirs = number(for: call)
        if let theirs, Self.digits(theirs) == digits { return nil }
        let owner = members.byNumber[digits]
        let them = callText(call)
        switch (theirs, owner) {
        case (let theirs?, let owner?):
            return "SKCC \(digits) is \(callText(owner)). \(them) is SKCC \(theirs)."
        case (let theirs?, nil):
            return "No SKCC member has number \(digits). \(them) is SKCC \(theirs)."
        case (nil, let owner?):
            return "SKCC \(digits) is \(callText(owner)). \(them) isn't in SKCC's list."
        case (nil, nil):
            return "No SKCC member has number \(digits), and \(them) isn't in SKCC's list."
        }
    }

    // "12345T" -> "12345 Tribune", for speech.
    static func spoken(_ number: String) -> String {
        guard let digits = digits(number) else { return number }
        switch number.last?.uppercased() {
        case "C": return "\(digits) Centurion"
        case "T": return "\(digits) Tribune"
        case "S": return "\(digits) Senator"
        default: return digits
        }
    }

    // The number's digits, without an award letter: "12345T" -> "12345".
    // Nil for anything that isn't digits with at most a C, T or S after.
    nonisolated static func digits(_ number: String) -> String? {
        var text = number.trimmingCharacters(in: .whitespaces).uppercased()
        if let last = text.last, "CTS".contains(last) { text.removeLast() }
        guard !text.isEmpty, text.count <= 7, text.allSatisfy(\.isASCII), text.allSatisfy(\.isNumber) else {
            return nil
        }
        // "012" and "12" are the same member.
        return String(Int(text) ?? 0)
    }

    // MARK: Reading the file

    // Reads SKCC's file. Lines that don't fit are skipped, so a damaged or
    // odd file gives fewer members, never wrong ones or a crash.
    nonisolated static func parse(_ text: String) -> Members {
        var members = Members()
        var highest: [String: Int] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let columns = line.split(separator: "|", omittingEmptySubsequences: false)
            guard columns.count >= 2 else { continue }
            let number = columns[0].trimmingCharacters(in: .whitespaces).uppercased()
            guard let digits = digits(number), let value = Int(digits) else { continue }
            // JOINDATE to SENDATE are columns 9 to 13.
            if columns.count >= 13 {
                let day = { (index: Int) in Self.date(String(columns[index])) }
                members.dates[digits] = SKCCDates(joined: day(8), centurion: day(9), tribune: day(10),
                                                  tribuneX8: day(11), senator: day(12))
            }
            let raw = columns[1].trimmingCharacters(in: .whitespaces).uppercased()
            // "N6WK/SK" and "K1ABC/EX" are left out; any other "/" part
            // is dropped ("K1ABC/W1XYZ" is K1ABC).
            let parts = raw.split(separator: "/").map(String.init)
            guard let call = parts.first, Callsign.looksValid(call),
                  !parts.dropFirst().contains(where: { $0 == "SK" || $0 == "EX" }) else { continue }
            members.byNumber[digits] = call
            // A call listed twice (rejoined, or a reissued call): the
            // newest number wins.
            if let previous = highest[call], previous > value { continue }
            highest[call] = value
            members.byCall[call] = number
        }
        return members
    }

    // "02 Jan 2006" as a date (the start of that day, UTC), or nil.
    nonisolated static func date(_ text: String) -> Date? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= 12 else { return nil }
        return dayFormat.date(from: text)
    }
    nonisolated(unsafe) private static let dayFormat: DateFormatter = {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "dd MMM yyyy"
        return format
    }()

    // MARK: The copy on disk

    private var fileURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Solid Copy", isDirectory: true)
            .appendingPathComponent("SKCC members.txt")
    }

    // At launch, when the list is turned on, and on each call (Solid
    // Copy may stay open for days): read the copy on disk, then fetch a
    // new one if it's old or missing. A failed fetch (no internet) isn't
    // tried again for an hour.
    func start() {
        guard Settings.skccLookup else { return }
        if members.count == 0, !triedDisk {
            triedDisk = true
            loadFromDisk()
        }
        let old = fetched.map { Date().timeIntervalSince($0) > Self.maximumAge } ?? true
        let recentlyTried = lastTry.map { Date().timeIntervalSince($0) < 60 * 60 } ?? false
        guard old, !recentlyTried, !downloading else { return }
        lastTry = Date()
        Task { await update() }
    }
    private var triedDisk = false
    private var lastTry: Date?

    private func loadFromDisk() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return }
        fetched = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let parsed = Self.parse(text)
        if parsed.count > 0 { members = parsed }
    }

    // Uses a list given as text (tools/check-clubs.sh).
    func use(_ text: String) {
        members = Self.parse(text)
    }

    // Fetches the list now. Returns words for Settings to show and say.
    // Window > Activity lists the fetch too (fetch() does the work).
    @discardableResult
    func update() async -> String {
        guard !downloading else { return "SKCC's list is already being fetched." }
        downloading = true
        defer {
            downloading = false
            onChange?()
        }
        let outcome = await Activity.shared.track("SKCC", "Member list", { _ in await self.fetch() },
                                                  finish: { ($0.ok, $0.text) })
        return outcome.text
    }

    // The fetch itself: whether the list was kept or replaced, and the words to show.
    private func fetch() async -> (ok: Bool, text: String) {
        do {
            var request = URLRequest(url: Self.url, timeoutInterval: 60)
            request.setValue("Solid Copy (Mac ham logger)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return (false, "SKCC's list couldn't be fetched: the site answered with an error. The old copy is kept.")
            }
            guard data.count <= Self.maximumBytes, let text = String(data: data, encoding: .utf8),
                  text.hasPrefix("SKCCNR|CALL|") else {
                return (false, "SKCC's list didn't look right, so the old copy is kept.")
            }
            // Parsing 31,000 lines takes a moment: off the main thread.
            let parsed = await Task.detached { Self.parse(text) }.value
            // Fewer than a thousand members is a broken file, not SKCC.
            guard parsed.count > 1_000 else { return (false, "SKCC's list was nearly empty, so the old copy is kept.") }
            if let fileURL { try data.write(to: fileURL, options: .atomic) }
            members = parsed
            fetched = Date()
            return (true, "SKCC's list fetched: \(parsed.count.formatted()) members.")
        } catch {
            return (false, "SKCC's list couldn't be fetched. \(error.localizedDescription) The old copy is kept.")
        }
    }

    // "31,601 members, fetched 16 November 2026", for Settings.
    var status: String {
        if downloading { return "Fetching SKCC's list…" }
        guard members.count > 0 else { return "SKCC's list hasn't been fetched yet." }
        let when = fetched.map { " Fetched \($0.formatted(date: .long, time: .omitted))." } ?? ""
        return "\(members.count.formatted()) SKCC members.\(when)"
    }
}
