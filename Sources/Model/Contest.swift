// Contest.swift
//
// Contests, defined in plain text files, so a rule
// change or a new contest needs no new version of Solid Copy: edit or add
// a file in the Contests folder (File > Show Contest Files). Solid Copy
// reads them each time it needs them. Field Day's file is written there
// the first time, as a working example; a README there explains the
// format. (the author, 17 November 2026.)
//
// A file, one setting per line, "#" starts a comment:
//   name: ARRL Field Day           required: what menus say
//   id: ARRL-FIELD-DAY             required: ADIF's CONTEST_ID, logged
//                                  with each contact (A-Z, 0-9, -)
//   exchange: exchange             what they send you: the form's fields,
//                                  in order (words below, or ADIF names)
//   serial: no                     yes adds Serial sent (counts itself)
//                                  and Serial received to the form
//   dupes: band and mode           once, band, or band and mode (modes
//                                  as contests group them: CW, phone,
//                                  digital)
//   messages: CQ FD {MYCALL} | ... CW messages F1, F2 ..., split by |
//   submit: dupe sheet             what File > Export… offers for it:
//                                  "dupe sheet" (calls by band and mode)
// Only name and id are needed; the rest has defaults (exchange: exchange,
// serial: no, dupes: band and mode, no messages, nothing to submit).
//
// A contest log (File > New Contest Log…) is a log made for one contest
// (LogInfo.contest): it comes with a profile built from the file (its
// form and messages; Settings.profile(for:)), dupes follow the file's
// rule, and Export offers what the file says to submit.
//
// Serial numbers aren't tied to a contest log: Serial sent counts itself
// in any log (nextSerial). Foundation only, so tools/check-cw.sh can check
// all of this.

import Foundation

struct Contest: Equatable {
    // How often a station may be worked.
    enum DupeRule: String, Equatable {
        case once            // once in the whole contest
        case band            // once per band
        case bandAndMode     // once per band and mode group

        var words: String {
            switch self {
            case .once: "once"
            case .band: "band"
            case .bandAndMode: "band and mode"
            }
        }
    }

    enum Submit: Equatable {
        case none
        case dupeSheet
    }

    // ADIF's CONTEST_ID, logged with each contact ("ARRL-FIELD-DAY").
    var id: String
    var name: String
    // Their exchange: the form's fields after Callsign, by ADIF name.
    var exchange: [String] = ["srx_string"]
    var serial = false
    var dupes: DupeRule = .bandAndMode
    var messages: [String] = []
    var submit: Submit = .none

    static func == (a: Contest, b: Contest) -> Bool {
        a.id == b.id && a.name == b.name && a.exchange == b.exchange && a.serial == b.serial
            && a.dupes == b.dupes && a.messages == b.messages && a.submit == b.submit
    }

    // MARK: Reading a file

    // Friendly words for the exchange, and the field each one is.
    // Any of the log's ADIF names (LogField.swift) works too.
    static let exchangeWords: [String: String] = [
        "exchange": "srx_string", "name": "name", "state": "state", "province": "state", "county": "cnty",
        "rst": "rst_rcvd", "report": "rst_rcvd", "zone": "cqz", "cq zone": "cqz",
        "itu zone": "ituz", "grid": "gridsquare", "park": "pota_ref", "summit": "sota_ref",
        "skcc": "skcc", "fists": "fists", "cwops": "app_solidcopy_cwops", "licw": "app_solidcopy_licw",
        "ten-ten": "ten_ten", "member": "srx_string", "number": "srx_string", "class and section": "srx_string",
    ]

    // A contest from a file's text, or the problems that stop it being
    // one (said in Solid Copy, in words, with the line).
    static func parse(_ text: String, knownFields: Set<String>) -> Result<Contest, ContestFileError> {
        var values: [String: String] = [:]
        for (number, raw) in text.components(separatedBy: .newlines).enumerated() {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first
                .map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !line.isEmpty else { continue }
            guard let colon = line.firstIndex(of: ":") else {
                return .failure(.init("line \(number + 1) has no colon: \(line)"))
            }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            values[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard let name = values["name"], !name.isEmpty else { return .failure(.init("it needs a name: line")) }
        let id = (values["id"] ?? "").uppercased()
        guard !id.isEmpty, id.count <= 32, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        else { return .failure(.init("it needs an id: line, such as ARRL-FIELD-DAY (letters, figures, hyphens)")) }
        var contest = Contest(id: id, name: name)

        if let exchange = values["exchange"], !exchange.isEmpty {
            var fields: [String] = []
            for word in exchange.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() })
            where !word.isEmpty {
                guard let field = exchangeWords[word] ?? (knownFields.contains(word) ? word : nil) else {
                    return .failure(.init("exchange word \"\(word)\" isn't one Solid Copy knows"))
                }
                if !fields.contains(field) { fields.append(field) }
            }
            if !fields.isEmpty { contest.exchange = fields }
        }
        switch values["serial"]?.lowercased() {
        case nil, "", "no": break
        case "yes": contest.serial = true
        case let other?: return .failure(.init("serial is yes or no, not \(other)"))
        }
        switch values["dupes"]?.lowercased() {
        case nil, "", "band and mode", "band and mode group": break
        case "once": contest.dupes = .once
        case "band": contest.dupes = .band
        case let other?: return .failure(.init("dupes is once, band, or band and mode, not \(other)"))
        }
        if let messages = values["messages"], !messages.isEmpty {
            contest.messages = Array(messages.split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }.prefix(CWMessages.count))
        }
        switch values["submit"]?.lowercased() {
        case nil, "", "none": break
        case "dupe sheet": contest.submit = .dupeSheet
        case let other?: return .failure(.init("submit is dupe sheet or none, not \(other)"))
        }
        return .success(contest)
    }

    // The file Solid Copy would write for this contest (Save Profile as
    // Contest…), readable by parse.
    var fileText: String {
        var lines = ["name: \(name)", "id: \(id)", "exchange: \(exchange.joined(separator: ", "))",
                     "serial: \(serial ? "yes" : "no")", "dupes: \(dupes.words)"]
        if !messages.isEmpty { lines.append("messages: " + messages.joined(separator: " | ")) }
        if submit == .dupeSheet { lines.append("submit: dupe sheet") }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Dupes

    // Modes as contests count them: CW, phone (SSB, AM, FM ...), or
    // digital (everything else: FT8, RTTY, PSK ...). "" if unknown.
    static func modeGroup(_ mode: String) -> String {
        let mode = mode.trimmingCharacters(in: .whitespaces).uppercased()
        guard !mode.isEmpty else { return "" }
        if mode == "CW" { return "CW" }
        if ["SSB", "USB", "LSB", "AM", "FM", "PHONE", "PH", "DIGITALVOICE"].contains(mode) { return "Phone" }
        return "Digital"
    }

    // The contact in `contacts` (newest first) that makes `call` on this
    // band and mode a dupe under this contest's rule, if any.
    func dupe(of call: String, band: String, mode: String, in contacts: [QSO]) -> QSO? {
        let group = Self.modeGroup(mode)
        return contacts.last { qso in
            guard qso.call == call else { return false }
            switch dupes {
            case .once: return true
            case .band: return qso["band"].caseInsensitiveCompare(band) == .orderedSame
            case .bandAndMode:
                // An unknown mode is never a dupe: a wrong warning is worse
                // than none (the author's TS-590SG in a data mode, 17 November
                // 2026, warned of a CW contact).
                return !group.isEmpty && qso["band"].caseInsensitiveCompare(band) == .orderedSame
                    && Self.modeGroup(qso["mode"]) == group
            }
        }
    }

    // MARK: Serial numbers

    // The next serial number: 1 more than the highest Serial sent (STX)
    // already logged for this contest ("" for contacts with no contest).
    // Typed serials that aren't whole numbers are passed over.
    static func nextSerial(in contacts: [QSO], contest: String) -> Int {
        let wanted = contest.trimmingCharacters(in: .whitespaces).uppercased()
        let highest = contacts.lazy
            .filter { $0["contest_id"].trimmingCharacters(in: .whitespaces).uppercased() == wanted }
            .compactMap { Int($0["stx"].trimmingCharacters(in: .whitespaces)) }
            .max() ?? 0
        return highest + 1
    }

    // MARK: Dupe sheet

    // Calls worked, by band and mode group, for a contest that asks for a
    // dupe sheet (ARRL Field Day: "a dupe sheet or station list by band
    // and mode"). Plain text, one block per band and mode.
    static func dupeSheet(_ contacts: [QSO], contestName: String, myCall: String) -> String {
        var groups: [String: [String]] = [:]
        for qso in contacts {
            let key = "\(qso["band"].isEmpty ? "No band" : qso["band"]) \(modeGroup(qso["mode"]).isEmpty ? "No mode" : modeGroup(qso["mode"]))"
            if !(groups[key]?.contains(qso.call) ?? false) { groups[key, default: []].append(qso.call) }
        }
        // Bands longest first (160m, 80m ...), then CW, Phone, Digital.
        let bandOrder = ["2190m", "630m", "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m",
                         "6m", "4m", "2m", "1.25m", "70cm", "33cm", "23cm", "13cm"]
        let modeOrder = ["CW", "Phone", "Digital"]
        func order(_ key: String) -> (Int, Int, String) {
            let parts = key.split(separator: " ").map(String.init)
            let band = bandOrder.firstIndex { $0.caseInsensitiveCompare(parts.first ?? "") == .orderedSame } ?? 99
            return (band, modeOrder.firstIndex(of: parts.last ?? "") ?? 9, key)
        }
        var text = "\(contestName) dupe sheet, \(myCall.isEmpty ? "my station" : myCall)\n"
        text += "\(contacts.count) contacts\n"
        for key in groups.keys.sorted(by: { order($0) < order($1) }) {
            let calls = (groups[key] ?? []).sorted()
            text += "\n\(key) (\(calls.count))\n" + calls.joined(separator: " ") + "\n"
        }
        return text
    }

    // MARK: Cabrillo

    // A Cabrillo 3.0 log for a contest that wants one (File > Export…,
    // Cabrillo). Cabrillo is ARRL's and CQ's plain-text layout for contest
    // entries: a header, one QSO line per contact in time order, and an
    // end line. The header's CONTEST: and each QSO line's exchange fields
    // come from the contest file; check them against the contest's own
    // rules before you submit, since each contest words its layout a little
    // differently.
    static func cabrillo(_ contacts: [QSO], contest: Contest, myCall: String) -> String {
        func token(_ value: String) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "-" : trimmed
        }
        func mode(_ mode: String) -> String {
            switch modeGroup(mode) {
            case "CW": return "CW"
            case "Phone": return "PH"
            default: return "RY"
            }
        }
        var text = "START-OF-LOG: 3.0\nCREATED-BY: Solid Copy\nCONTEST: \(contest.id)\n"
        text += "CALLSIGN: \(token(myCall))\n"
        for qso in contacts.sorted(by: { $0.timeOn < $1.timeOn }) {
            // Sent: the serial (if the contest has one), then your exchange.
            let sent = (contest.serial ? [qso["stx"]] : []) + [qso["stx_string"]]
            // Received: their serial, then the exchange fields the contest asks for.
            let received = (contest.serial ? [qso["srx"]] : []) + contest.exchange.map { qso[$0] }
            let freq = Double(qso["freq"]).map { String(Int(($0 * 1000).rounded())) } ?? "-"
            text += ["QSO:", token(freq), mode(qso["mode"]), qso.utcDateText, qso.utcTimeText,
                     token(myCall), token(qso.rstSent), sent.map(token).joined(separator: " "),
                     token(qso.call), token(qso.rstReceived), received.map(token).joined(separator: " ")]
                .joined(separator: " ") + "\n"
        }
        return text + "END-OF-LOG:\n"
    }

    // MARK: The starting files

    // Written into the Contests folder the first time it's made.
    static let fieldDayFile = """
    # ARRL Field Day: the fourth full weekend in June, 1800 UTC Saturday
    # to 2059 UTC Sunday. Exchange: your class and ARRL/RAC section,
    # such as 1D MDC (put yours in Exchange sent on the profile). Each
    # station once per band per mode (CW, phone, digital). ARRL asks for
    # a dupe sheet: calls by band and mode (File > Export…, Dupe Sheet).
    # Rules: https://www.arrl.org/field-day-rules
    name: ARRL Field Day
    id: ARRL-FIELD-DAY
    exchange: class and section
    serial: no
    dupes: band and mode
    messages: CQ FD {MYCALL} {MYCALL} FD | {CALL} {SENT} | TU {MYCALL} FD | {MYCALL} | {CALL} | AGN? | QRZ? | {SENT}
    submit: dupe sheet

    """

    static let readme = """
    Contest files for Solid Copy

    Each .txt file here is one contest. Solid Copy reads them when you
    choose File > New Contest Log…, so a change takes effect at once. One
    setting per line; a # starts a comment.

    name: NAQP CW                 required, what menus say
    id: NAQP-CW                   required, the contest's ADIF CONTEST_ID
    exchange: name, state         what they send, in order
    serial: no                    yes adds Serial sent and received
    dupes: band and mode          once, band, or band and mode
    messages: CQ NA {MYCALL} | {CALL} {MYNAME} {MYSTATE} | TU {MYCALL}
    submit: none                  or: dupe sheet

    Exchange words: exchange, name, state, province, county, rst,
    zone, itu zone, grid, park, summit, skcc, fists, cwops, licw,
    ten-ten, member, number, class and section; or any field's ADIF name
    (srx_string, cnty, and so on).

    Message fill-ins: {MYCALL} {MYNAME} {MYSTATE} {SENT} {NR} {CALL}
    {NAME} {STATE} {SKCC} {RST}.

    File > Save Profile as Contest… writes a file like these from the
    profile in use.

    """
}

struct ContestFileError: Error, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
}

// The contests in the Contests folder (Application Support/Solid Copy/
// Contests), read fresh each time: Field Day's file and a README are
// written there the first time. A file that can't be read is listed in
// `problems`, with why, and left out.
enum ContestList {
    struct Loaded {
        var contests: [Contest]
        var problems: [String]
    }

    static func folder(in base: URL) -> URL { base.appendingPathComponent("Contests", isDirectory: true) }

    static func load(from folder: URL) -> Loaded {
        let files = FileManager.default
        if !files.fileExists(atPath: folder.path) {
            try? files.createDirectory(at: folder, withIntermediateDirectories: true)
            try? Data(Contest.fieldDayFile.utf8).write(to: folder.appendingPathComponent("ARRL Field Day.txt"))
            try? Data(Contest.readme.utf8).write(to: folder.appendingPathComponent("README.txt"))
        }
        let known = Set(LogField.all.map(\.adif))
        var loaded = Loaded(contests: [], problems: [])
        let names = ((try? files.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.lowercased().hasSuffix(".txt") && $0 != "README.txt" }.sorted()
        for name in names {
            // A contest file is small; anything big isn't one.
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)), data.count < 64_000,
                  let text = String(data: data, encoding: .utf8) else {
                loaded.problems.append("\(name): couldn't be read as text.")
                continue
            }
            switch Contest.parse(text, knownFields: known) {
            case .success(let contest):
                if loaded.contests.contains(where: { $0.id == contest.id }) {
                    loaded.problems.append("\(name): another file already has id \(contest.id).")
                } else {
                    loaded.contests.append(contest)
                }
            case .failure(let error):
                loaded.problems.append("\(name): \(error.message).")
            }
        }
        return loaded
    }

    // The contests in Solid Copy's own folder.
    static func load() -> Loaded {
        guard let base = try? LogList.baseFolder() else { return Loaded(contests: [], problems: []) }
        return load(from: folder(in: base))
    }

    static func named(_ id: String?) -> Contest? {
        guard let id, !id.isEmpty else { return nil }
        return load().contests.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
    }
}
