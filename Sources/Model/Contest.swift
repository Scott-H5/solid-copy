// Contest.swift
//
// Contests, defined in plain text files (CLAUDE.md, item 7), so a rule
// change or a new contest needs no new version of Solid Copy: edit or add
// a file in the Contests folder (File > Show Contest Files). Solid Copy
// reads them each time it needs them. Field Day's file is written there
// the first time, as a working example; a README there explains the
// format. (Scott, 17 November 2026.)
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
// Scoring (v1.6 item 2, for SKCC's events, whose web forms ask for your
// totals rather than a log). All optional; Speech > Say Contest Score
// and File > Contests > Contest Score… add them up (Contest.score):
//   points: 1                      each contact that isn't a dupe
//   multipliers: state             a field (exchange words work) whose
//                                  different values multiply the points,
//                                  once each in the contest
//   skcc bonus: C 5, T 10, S 15    once per station, from the letter on
//                                  their SKCC number
//   bonus station: KS1KCC 25 per band   a station worth points, per band
//                                  or once; several split by commas
//   grid bonus: 5                  each different 4-character grid
//   name bonus: /BD 30             each station whose name ends so, once
// Score: points times multipliers (or just points, with no multipliers
// line), plus the bonuses.
// Only name and id are needed; the rest has defaults (exchange: exchange,
// serial: no, dupes: band and mode, no messages, nothing to submit, 1
// point a contact, no multipliers or bonuses).
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
    // Scoring (see the top of this file).
    var points = 1
    var multipliers: [String] = []
    var skccBonus: [Character: Int] = [:]
    var bonusStations: [BonusStation] = []
    var gridBonus = 0
    var nameBonus: (ending: String, points: Int)?

    struct BonusStation: Equatable {
        var call: String
        var points: Int
        var perBand: Bool
    }

    // Whether the file says anything about scoring, so Say Contest Score
    // can say a score is just a count of contacts.
    var hasScoring: Bool {
        !multipliers.isEmpty || !skccBonus.isEmpty || !bonusStations.isEmpty || gridBonus > 0 || nameBonus != nil
    }

    static func == (a: Contest, b: Contest) -> Bool {
        a.id == b.id && a.name == b.name && a.exchange == b.exchange && a.serial == b.serial
            && a.dupes == b.dupes && a.messages == b.messages && a.submit == b.submit
            && a.points == b.points && a.multipliers == b.multipliers && a.skccBonus == b.skccBonus
            && a.bonusStations == b.bonusStations && a.gridBonus == b.gridBonus
            && a.nameBonus?.ending == b.nameBonus?.ending && a.nameBonus?.points == b.nameBonus?.points
    }

    // MARK: Reading a file

    // Friendly words for the exchange, and the field each one is.
    // Any of the log's ADIF names (LogField.swift) works too.
    static let exchangeWords: [String: String] = [
        "exchange": "srx_string", "name": "name", "state": "state", "province": "state", "county": "cnty",
        "rst": "rst_rcvd", "report": "rst_rcvd", "rst sent": "rst_sent", "spc": "state", "zone": "cqz", "cq zone": "cqz",
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

        // A list of fields, in exchange words or ADIF names.
        func fields(_ key: String) -> Result<[String], ContestFileError> {
            var fields: [String] = []
            for word in (values[key] ?? "").split(separator: ",")
                .map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) where !word.isEmpty {
                guard let field = exchangeWords[word] ?? (knownFields.contains(word) ? word : nil) else {
                    return .failure(.init("\(key) word \"\(word)\" isn't one Solid Copy knows"))
                }
                if !fields.contains(field) { fields.append(field) }
            }
            return .success(fields)
        }
        switch fields("exchange") {
        case .success(let list): if !list.isEmpty { contest.exchange = list }
        case .failure(let error): return .failure(error)
        }
        switch fields("multipliers") {
        case .success(let list): contest.multipliers = list
        case .failure(let error): return .failure(error)
        }
        // A whole number of points, 0 to 10,000 (no file needs more).
        func number(_ text: String, _ what: String) -> Result<Int, ContestFileError> {
            guard let value = Int(text.trimmingCharacters(in: .whitespaces)), (0...10_000).contains(value) else {
                return .failure(.init("\(what) needs a whole number of points, not \(text)"))
            }
            return .success(value)
        }
        if let text = values["points"], !text.isEmpty {
            switch number(text, "points") {
            case .success(let value): contest.points = value
            case .failure(let error): return .failure(error)
            }
        }
        if let text = values["grid bonus"], !text.isEmpty {
            switch number(text, "grid bonus") {
            case .success(let value): contest.gridBonus = value
            case .failure(let error): return .failure(error)
            }
        }
        // "C 5, T 10, S 15"
        for part in (values["skcc bonus"] ?? "").split(separator: ",") {
            let words = part.split(separator: " ").map(String.init)
            guard words.count == 2, let letter = words[0].uppercased().first, words[0].count == 1,
                  "CTS".contains(letter), let value = Int(words[1]), (0...10_000).contains(value) else {
                return .failure(.init("skcc bonus is a letter and points, like C 5, T 10, S 15, not \(part)"))
            }
            contest.skccBonus[letter] = value
        }
        // "KS1KCC 25 per band, K9SKC 10 once"
        for part in (values["bonus station"] ?? "").split(separator: ",") {
            let words = part.split(separator: " ").map { $0.lowercased() }
            let perBand = words.suffix(2) == ["per", "band"]
            let once = words.last == "once"
            guard words.count == (perBand ? 4 : once ? 3 : 2), let value = Int(words[1]),
                  (0...10_000).contains(value) else {
                return .failure(.init("bonus station is a call and points, then per band or once, like KS1KCC 25 per band, not \(part)"))
            }
            contest.bonusStations.append(BonusStation(call: words[0].uppercased(), points: value, perBand: perBand))
        }
        // "/BD 30"
        if let text = values["name bonus"], !text.isEmpty {
            let words = text.split(separator: " ").map(String.init)
            guard words.count == 2, let value = Int(words[1]), (0...10_000).contains(value) else {
                return .failure(.init("name bonus is an ending and points, like /BD 30, not \(text)"))
            }
            contest.nameBonus = (words[0].uppercased(), value)
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
        if points != 1 { lines.append("points: \(points)") }
        if !multipliers.isEmpty { lines.append("multipliers: " + multipliers.joined(separator: ", ")) }
        if !skccBonus.isEmpty {
            lines.append("skcc bonus: " + "CTS".compactMap { letter in skccBonus[letter].map { "\(letter) \($0)" } }
                .joined(separator: ", "))
        }
        if !bonusStations.isEmpty {
            lines.append("bonus station: " + bonusStations
                .map { "\($0.call) \($0.points) \($0.perBand ? "per band" : "once")" }.joined(separator: ", "))
        }
        if gridBonus > 0 { lines.append("grid bonus: \(gridBonus)") }
        if let nameBonus { lines.append("name bonus: \(nameBonus.ending) \(nameBonus.points)") }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Score

    // What a contest log adds up to, by the file's scoring lines: the
    // numbers SKCC's score forms ask for, and the total.
    struct Score: Equatable {
        var contacts = 0              // counted: dupes left out
        var dupes = 0
        var points = 0
        var multipliers = 0
        var members: [Character: Int] = [:]   // C, T and S stations, once each
        var memberPoints = 0
        var bonusStations: [String: Int] = [:]   // call: bands (or 1)
        var bonusStationPoints = 0
        var grids = 0
        var gridPoints = 0
        var named = 0
        var namedPoints = 0
        var total = 0
    }

    func score(_ contacts: [QSO]) -> Score {
        var score = Score()
        var counted: [QSO] = []
        // In time order, so the first contact counts and later ones are
        // the dupes.
        for qso in contacts.sorted(by: { $0.timeOn < $1.timeOn }) {
            if dupe(of: qso.call, band: qso["band"], mode: qso["mode"], in: counted) != nil {
                score.dupes += 1
            } else {
                counted.append(qso)
            }
        }
        score.contacts = counted.count
        score.points = counted.count * points
        func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespaces).uppercased() }
        var multiplierValues = Set<String>()
        for qso in counted {
            for field in multipliers where !clean(qso[field]).isEmpty { multiplierValues.insert(field + " " + clean(qso[field])) }
        }
        score.multipliers = multiplierValues.count
        // C, T and S, once per station.
        var members: [String: Character] = [:]
        for qso in counted {
            let station = Self.baseCall(qso.call)
            guard members[station] == nil, let letter = Self.skccLetter(qso["skcc"]), skccBonus[letter] != nil
            else { continue }
            members[station] = letter
        }
        for letter in members.values {
            score.members[letter, default: 0] += 1
            score.memberPoints += skccBonus[letter] ?? 0
        }
        for station in bonusStations {
            let worked = counted.filter { Self.baseCall($0.call) == station.call }
            guard !worked.isEmpty else { continue }
            let times = station.perBand ? Set(worked.map { $0["band"].lowercased() }).count : 1
            score.bonusStations[station.call] = times
            score.bonusStationPoints += times * station.points
        }
        if gridBonus > 0 {
            score.grids = Set(counted.map { String(clean($0["gridsquare"]).prefix(4)) }.filter { $0.count == 4 }).count
            score.gridPoints = score.grids * gridBonus
        }
        if let nameBonus {
            score.named = Set(counted.filter { clean($0["name"]).hasSuffix(nameBonus.ending) }
                .map { Self.baseCall($0.call) }).count
            score.namedPoints = score.named * nameBonus.points
        }
        let base = multipliers.isEmpty ? score.points : score.points * score.multipliers
        score.total = base + score.memberPoints + score.bonusStationPoints + score.gridPoints + score.namedPoints
        return score
    }

    // The station behind a call, for bonuses counted once per station:
    // NX1K/4 and W1/NX1K are NX1K (the longest part).
    static func baseCall(_ call: String) -> String {
        let parts = call.trimmingCharacters(in: .whitespaces).uppercased().split(separator: "/").map(String.init)
        return parts.max { $0.count < $1.count } ?? call.uppercased()
    }

    // The award letter on an SKCC number: "12345T" -> T, "12345Tx2" ->
    // T, "12345" or "NONE" -> nil.
    static func skccLetter(_ number: String) -> Character? {
        let text = number.trimmingCharacters(in: .whitespaces).uppercased()
        guard let first = text.first, first.isNumber,
              let letter = text.first(where: { !$0.isNumber }), "CTS".contains(letter) else { return nil }
        return letter
    }

    // The score in words: what Say Contest Score says, and (one item a
    // line) what Contest Score… shows, in the order SKCC's forms ask.
    func scoreLines(_ score: Score) -> [String] {
        func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
        var lines = [count(score.contacts, "contact", "contacts")
                     + (score.dupes > 0 ? " (\(count(score.dupes, "dupe", "dupes")) not counted)" : "")]
        if points != 1 { lines.append("\(score.points) contact points") }
        if !multipliers.isEmpty { lines.append(count(score.multipliers, "multiplier", "multipliers")) }
        let names: [Character: (String, String)] = ["C": ("Centurion", "Centurions"), "T": ("Tribune", "Tribunes"),
                                                    "S": ("Senator", "Senators")]
        for letter in "CTS" where skccBonus[letter] != nil {
            let n = score.members[letter] ?? 0
            lines.append(count(n, names[letter]!.0, names[letter]!.1) + ", \(n * (skccBonus[letter] ?? 0)) points")
        }
        for station in bonusStations {
            let times = score.bonusStations[station.call] ?? 0
            let what = station.perBand ? count(times, "band", "bands") : times > 0 ? "worked" : "not worked"
            lines.append("\(station.call): \(what), \(times * station.points) points")
        }
        if gridBonus > 0 { lines.append(count(score.grids, "grid", "grids") + ", \(score.gridPoints) points") }
        if let nameBonus {
            lines.append("\(nameBonus.ending) stations: \(score.named), \(score.namedPoints) points")
        }
        if hasScoring { lines.append("Score \(score.total)") }
        return lines
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
                // than none (Scott's TS-590SG in a data mode, 17 November
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

    // SKCC's regular events (rules read 22 November 2026 at
    // skccgroup.com/operating_activities). They're straight key events (a
    // straight key, bug or sideswiper), so the files have no CW messages:
    // sent by the keyer, they'd break SKCC's key rule. SKCC takes your
    // totals in a web form, not a log, so each has its scoring.
    static let skccExchange = "rst sent, rst, spc, name, skcc"
    static let skccFooter = """
    # Exchange: RST (a real one), state or province (or the country's SPC
    # code outside the US and Canada), name and SKCC number with its C, T
    # or S. Non-members send NONE. Put yours in Exchange sent on the
    # profile, such as: PA SAM 12345T. Each station once per band.
    # File > Contests > Contest Score… gives the totals SKCC's form asks for.
    """

    static let skcc: [(file: String, text: String)] = [
        ("SKCC Sprint.txt", """
        # SKCC Sprint (SKS): the fourth Wednesday of each month, 0000 to
        # 0200 UTC (Tuesday evening in the US). 160 to 6 metres, no WARC
        # bands, no spotting. Score: contacts times SPCs, plus C 5, T 10,
        # S 15 (once each), plus the month's special station, 25 per band.
        # Change its call below each month (NX1K was November 2026's).
        # Submit your score on SKCC's site by the Sunday after.
        # Rules: https://www.skccgroup.com/operating_activities/weekday_sprint/
        \(skccFooter)
        name: SKCC Sprint
        id: SKCC-SKS
        exchange: \(skccExchange)
        dupes: band
        multipliers: spc
        skcc bonus: C 5, T 10, S 15
        bonus station: NX1K 25 per band

        """),
        ("SKCC Sprint Europe.txt", """
        # SKCC Sprint Europe (SKSE): the first Thursday of each month, two
        # hours: 2000 to 2200 UTC November to March, 1900 to 2100 UTC April
        # to October. 160 to 6 metres, no WARC bands. Score: contacts
        # times SPCs, plus C 5, T 10, S 15 (once each). Submit by 2359 UTC
        # the Thursday after.
        # Rules: https://www.skccgroup.com/operating_activities/skse/
        \(skccFooter)
        name: SKCC Sprint Europe
        id: SKCC-SKSE
        exchange: \(skccExchange)
        dupes: band
        multipliers: spc
        skcc bonus: C 5, T 10, S 15

        """),
        ("SKCC Asia Sprint.txt", """
        # SKCC Asia Sprint (SKSA): the second Friday of each month, 2200 to
        # 2359 UTC. Non-WARC bands 160 to 6 metres. Score: contacts times
        # SPCs, plus C 5, T 10, S 15 (once each), plus 30 for each station
        # whose name ends /BD (their birthday month). Submit within 72
        # hours, by the Sunday after.
        # Rules: https://www.skccgroup.com/operating_activities/sksa/
        \(skccFooter)
        name: SKCC Asia Sprint
        id: SKCC-SKSA
        exchange: \(skccExchange)
        dupes: band
        multipliers: spc
        skcc bonus: C 5, T 10, S 15
        name bonus: /BD 30

        """),
        ("SKCC Weekend Sprintathon.txt", """
        # SKCC Weekend Sprintathon (WES): the second weekend of each month,
        # 1200 UTC Saturday to 2359 UTC Sunday. 160 to 6 metres, no WARC
        # bands. Score: contacts times SPCs, plus C 5, T 10, S 15 (once
        # each), plus KS1KCC 25 per band. Each month has a theme bonus as
        # well, which you add up yourself (see the month's page). Submit by
        # 2359 UTC the Sunday after.
        # Rules: https://www.skccgroup.com/operating_activities/weekend_sprintathon/
        \(skccFooter)
        name: SKCC Weekend Sprintathon
        id: SKCC-WES
        exchange: \(skccExchange)
        dupes: band
        multipliers: spc
        skcc bonus: C 5, T 10, S 15
        bonus station: KS1KCC 25 per band

        """),
        ("SKCC QSO Party.txt", """
        # SKCC QSO Party: the third weekend of June, 1200 UTC Saturday to
        # 2359 UTC Sunday. 160 to 6 metres, no WARC bands. The exchange adds
        # a 4-character grid. Score: contacts times SPCs, plus C 5, T 10,
        # S 15 (once each), KS1KCC 25 per band, and 5 for each different
        # grid. A theme bonus and the 100-point photo bonus are added
        # outside Solid Copy. Submit by 2359 UTC the Sunday after.
        # Rules: https://www.skccgroup.com/operating_activities/QSO_Party/
        \(skccFooter)
        name: SKCC QSO Party
        id: SKCC-QSO-PARTY
        exchange: rst sent, rst, spc, name, grid, skcc
        dupes: band
        multipliers: spc
        skcc bonus: C 5, T 10, S 15
        bonus station: KS1KCC 25 per band
        grid bonus: 5

        """),
        ("SKCC Slow Speed Saunter.txt", """
        # SKCC Slow Speed Saunter: the first day of each month, 0000 to
        # 2359 UTC, at 12 words a minute or slower. Not a contest: you
        # report how many contacts you made, within 72 hours. 160 to 6
        # metres, WARC bands too.
        # Rules: https://www.skccgroup.com/operating_activities/slowspeed/
        \(skccFooter)
        name: SKCC Slow Speed Saunter
        id: SKCC-SAUNTER
        exchange: \(skccExchange)
        dupes: band

        """),
    ]

    // Every file Solid Copy has, Field Day first. One that's new in this
    // version is added to an existing Contests folder once (ContestList).
    static var startingFiles: [(file: String, text: String)] {
        [("ARRL Field Day.txt", fieldDayFile)] + skcc
    }

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

    Scoring (all optional; File > Contests > Contest Score… and Speech >
    Say Contest Score add it up):

    points: 1                     each contact that isn't a dupe
    multipliers: spc              a field whose different values multiply
    skcc bonus: C 5, T 10, S 15   once per station, by their SKCC letter
    bonus station: KS1KCC 25 per band   (or: 25 once); commas for more
    grid bonus: 5                 each different 4-character grid
    name bonus: /BD 30            each station whose name ends /BD

    Score is points times multipliers (just points without a
    multipliers line), plus the bonuses.

    Exchange words: exchange, name, state, province, spc, county, rst,
    rst sent, zone, itu zone, grid, park, summit, skcc, fists, cwops, licw,
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
        addStartingFiles(to: folder)
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

    // Solid Copy's own contest files, each written once: all of them in
    // a new folder, and in an existing one only those it hasn't had yet
    // (the SKCC files, new in 1.6), so a file you deleted or changed is
    // left alone. ".written" in the folder lists the files given so far;
    // a folder from before 1.6 has none, and had only Field Day's.
    static let writtenList = ".written"
    private static func addStartingFiles(to folder: URL) {
        let files = FileManager.default
        let isNew = !files.fileExists(atPath: folder.path)
        if isNew { try? files.createDirectory(at: folder, withIntermediateDirectories: true) }
        let listURL = folder.appendingPathComponent(writtenList)
        var written: Set<String> = isNew ? [] : ["ARRL Field Day.txt"]
        if let data = try? Data(contentsOf: listURL), data.count < 64_000, let text = String(data: data, encoding: .utf8) {
            written = Set(text.components(separatedBy: .newlines).filter { !$0.isEmpty })
        }
        let new = Contest.startingFiles.filter { !written.contains($0.file) }
        guard !new.isEmpty else { return }
        for file in new where !files.fileExists(atPath: folder.appendingPathComponent(file.file).path) {
            try? Data(file.text.utf8).write(to: folder.appendingPathComponent(file.file))
        }
        // The README is Solid Copy's: it's brought up to date with the files.
        try? Data(Contest.readme.utf8).write(to: folder.appendingPathComponent("README.txt"))
        written.formUnion(new.map(\.file))
        try? Data((written.sorted().joined(separator: "\n") + "\n").utf8).write(to: listURL)
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
