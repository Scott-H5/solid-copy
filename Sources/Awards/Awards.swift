// Awards.swift
//
// Award tracking (v1.5 item 2): how far the log is towards four awards,
// counted the way their sponsors count them.
//
//   DXCC (ARRL)  countries: 100 confirmed earns it
//   WAS  (ARRL)  the 50 US states (DC counts as Maryland, so isn't one)
//   WAZ  (CQ)    the 40 CQ zones
//   WPX  (CQ)    different prefixes: 400 for mixed modes, 300 for one
//   SKCC Centurion, Tribune and Senator: straight key members (below)
//   POTA Hunter  different parks hunted (below)
//
// Each can be for one band and one kind of mode (all CW on 20 meters, say),
// as the awards' own endorsements are.
//
// Worked and confirmed: an award counts only confirmed contacts. Here a
// contact is confirmed by LoTW or a paper card. eQSL and QRZ Logbook
// confirmations aren't counted: ARRL doesn't accept them for DXCC or WAS.
//
// Where each contact's place comes from, best first:
//   - LoTW's details (LoTW.swift), which are what LoTW credits: the
//     state, CQ zone and WPX prefix fields once LoTW has confirmed it
//   - a lookup or what was typed: the same fields
//   - the call itself: its country from cty.dat (Countries.swift), its
//     zone from cty.dat when the country is all in one zone, and its
//     prefix by WPX's rules (WPX.prefix below)
//
// SKCC (Straight Key Century Club) awards count members, not places, and
// need no QSL: a member counts if the contact was made by the rules,
// judged on the day of the contact from SKCC's member list (SKCCRoster),
// which says when each member joined and reached each level. From
// skccgroup.com/operating_awards (read 22 November 2026):
//   Centurion  100 different members; both stations members that day
//   Tribune    50 different Centurions, Tribunes or Senators, worked on
//              or after the day you became a Centurion and they had too;
//              from 1 March 2007. Tx2 is 100, Tx3 150, ... Tx10 500, then
//              Tx15 750, Tx20 1000, and on by 250.
//   Senator    after Tribune x8: 200 different Tribunes or Senators worked
//              on or after your Tx8 day, and after they were Tribunes;
//              from 1 August 2013. Sx2 is 400, up to Sx10.
// Each member counts once, by number (Senator's rule; Centurion's says
// by call, and a number follows a member who changes call). Only CW
// contacts count; the key used (straight, bug or cootie) isn't in the
// log, so that's taken on trust. K9SKC, the club's own call, doesn't
// count from the days the rules give.
//
// POTA (Parks on the Air) hunter awards count different parks, any band
// or mode: Bronze 10, Silver 20, Gold 30, Platinum 40, Diamond 50,
// Sapphire 75, then 100 to 1000 by 100, 1500 and 2000 (docs.pota.app,
// Achievements, read 22 November 2026; the higher ones have flower and
// animal names, said here as "the 300 park award"). Credit comes from the
// activators' logs, so pota.app's count is the official one: this is your
// own count of parks worked, from each contact's park (POTA_REF, or SIG
// POTA with SIG_INFO). A contact with several parks (a two-fer) counts
// each. Old US references (K-1333) are POTA's US-1333 now, so they're
// counted as that.
//
// No windows here, and the country data is passed in, so
// tools/check-awards.sh can check the counting with a made-up log.

import Foundation

enum Award: String, CaseIterable {
    case dxcc, was, waz, wpx, centurion, tribune, senator, pota

    var title: String {
        switch self {
        case .dxcc: "DXCC"
        case .was: "WAS"
        case .waz: "WAZ"
        case .wpx: "WPX"
        case .centurion: "SKCC Centurion"
        case .tribune: "SKCC Tribune"
        case .senator: "SKCC Senator"
        case .pota: "POTA Hunter"
        }
    }

    var isSKCC: Bool { [.centurion, .tribune, .senator].contains(self) }

    // What it counts, said after a number ("38 states").
    var counts: String {
        switch self {
        case .dxcc: "countries"
        case .was: "states"
        case .waz: "zones"
        case .wpx: "prefixes"
        case .centurion, .tribune, .senator: "members"
        case .pota: "parks"
        }
    }

    // How many confirmed earn the basic award.
    func goal(mode: AwardMode) -> Int {
        switch self {
        case .dxcc: 100
        case .was: 50
        case .waz: 40
        case .wpx: mode == .mixed ? 400 : 300
        case .centurion: 100
        case .tribune: 50
        case .senator: 200
        case .pota: 10
        }
    }

    // SKCC's levels, lowest first: (how many members, its name).
    var levels: [(count: Int, name: String)] {
        switch self {
        case .centurion:
            return [(100, "Centurion")] + (2...10).map { ($0 * 100, "Cx\($0)") }
                + stride(from: 15, through: 100, by: 5).map { ($0 * 100, "Cx\($0)") }
        case .tribune:
            return [(50, "Tribune")] + (2...10).map { ($0 * 50, "Tx\($0)") }
                + stride(from: 15, through: 200, by: 5).map { ($0 * 50, "Tx\($0)") }
        case .senator:
            return [(200, "Senator")] + (2...10).map { ($0 * 200, "Sx\($0)") }
        case .pota:
            return [(10, "Bronze"), (20, "Silver"), (30, "Gold"), (40, "Platinum"), (50, "Diamond"), (75, "Sapphire")]
                + (stride(from: 100, through: 1000, by: 100).map { $0 } + [1500, 2000]).map { ($0, "the \($0) park award") }
        default:
            return []
        }
    }
}

// The kind of mode an award is for: mixed (any), or one of the three
// groups the Spots window uses (Spot.group): CW, phone and digital.
enum AwardMode: String, CaseIterable {
    case mixed, cw, phone, digital

    var title: String {
        switch self {
        case .mixed: "Mixed"
        case .cw: "CW"
        case .phone: "Phone"
        case .digital: "Digital"
        }
    }

    func includes(_ mode: String) -> Bool {
        switch self {
        case .mixed: true
        case .cw: Spot.group(of: mode) == "CW"
        case .phone: Spot.group(of: mode) == "Phone"
        case .digital: Spot.group(of: mode) == "Data"
        }
    }
}

// One country, state, zone or prefix, and how it stands.
struct AwardItem: Equatable {
    var key: String         // "TX", "5", "United States", "K3"
    var name: String        // "Texas", "Zone 5", "United States", "K3"
    var contacts = 0        // contacts that count for it
    var confirmedBy: [String] = []   // "LoTW", "card": any confirmation; "SKCC": it counts
    // For an SKCC member that doesn't count: why not.
    var why = ""
    // A park: there's no confirmation in the log to speak of (POTA credits
    // hunters from the activators' logs), so it's just worked.
    var noQSL = false

    var isWorked: Bool { contacts > 0 }
    var isConfirmed: Bool { !confirmedBy.isEmpty }

    // One line, read in one stop by VoiceOver.
    var line: String {
        let times = contacts == 1 ? "1 contact" : "\(contacts) contacts"
        if confirmedBy == ["SKCC"] { return "\(name): counts, \(times)" }
        if noQSL { return "\(name): worked, \(times)" }
        if !why.isEmpty { return "\(name): doesn't count, \(why), \(times)" }
        if isConfirmed { return "\(name): confirmed by \(confirmedBy.joined(separator: " and ")), \(times)" }
        if isWorked { return "\(name): worked, not confirmed, \(times)" }
        return "\(name): not worked"
    }
}

struct AwardProgress: Equatable {
    var award: Award
    var mode: AwardMode
    // Everything that could count, worked or not, in the order shown. For
    // WPX, only prefixes worked: there's no fixed list of them.
    var items: [AwardItem]
    // Said instead of the counts when the award can't be counted (SKCC
    // without the member list, say).
    var blocked: String?

    var worked: Int { items.filter(\.isWorked).count }
    var confirmed: Int { items.filter(\.isConfirmed).count }

    // "WAS: 38 states worked, 31 confirmed, 19 more confirmed for the award."
    var line: String {
        if let blocked { return "\(award.title): \(blocked)" }
        if award.isSKCC || award == .pota {
            // "SKCC Tribune: 120 members count, enough for Tx2; 30 more for Tx3."
            // "POTA Hunter: 63 parks worked, enough for Diamond; 12 more for Sapphire."
            let count = award == .pota ? worked : confirmed
            let start = award == .pota ? "\(award.title): \(count) \(count == 1 ? "park" : "parks") worked"
                : "\(award.title): \(count) \(count == 1 ? "member counts" : "members count")"
            let earned = award.levels.last { $0.count <= count }
            guard let next = award.levels.first(where: { $0.count > count }) else {
                return start + ", enough for \(earned?.name ?? award.title)."
            }
            let more = "\(next.count - count) more for \(next.name)."
            return start + (earned.map { ", enough for \($0.name); " + more } ?? ", " + more)
        }
        let goal = award.goal(mode: mode)
        let start = "\(award.title): \(worked) \(award.counts) worked, \(confirmed) confirmed"
        return confirmed >= goal ? start + ", enough for the award (\(goal))."
            : start + ", \(goal - confirmed) more confirmed for the award."
    }
}

enum Awards {
    // The 50 states, by their two letters (USStates names them).
    static let states = ["AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA", "HI", "ID", "IL", "IN", "IA",
                         "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
                         "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT",
                         "VA", "WA", "WV", "WI", "WY"]
    // cty.dat's names for the countries whose contacts count for WAS.
    static let wasCountries: Set<String> = ["United States", "Alaska", "Hawaii"]

    // The confirmations an award accepts: (name, status field).
    static let confirmations = [("LoTW", "lotw_qsl_rcvd"), ("card", "qsl_rcvd")]

    // How far the log is towards an award, on one band ("20m", or nil for
    // all) and kind of mode. `country` and `allCountries` are cty.dat's
    // (Countries.shared), passed in so the check can use its own.
    static func progress(_ award: Award, log: [QSO], band: String?, mode: AwardMode,
                         country: (String) -> Country?, allCountries: [Country],
                         skcc: SKCC? = nil, parkName: (String) -> String? = { _ in nil }) -> AwardProgress {
        if award.isSKCC { return skccProgress(award, log: log, band: band, skcc: skcc) }
        if award == .pota { return potaProgress(log: log, band: band, mode: mode, parkName: parkName) }
        var items: [String: AwardItem] = [:]
        var order: [String] = []
        func add(_ key: String, _ name: String) {
            guard items[key] == nil else { return }
            items[key] = AwardItem(key: key, name: name)
            order.append(key)
        }
        // Everything there is to work, in the order it's shown.
        switch award {
        case .dxcc: for item in allCountries.sorted(by: { $0.name < $1.name }) { add(item.name, item.name) }
        case .was:
            for code in states.sorted(by: { (USStates.name(for: $0) ?? $0) < (USStates.name(for: $1) ?? $1) }) {
                add(code, USStates.name(for: code) ?? code)
            }
        case .waz: for zone in 1...40 { add(String(zone), "Zone \(zone)") }
        case .wpx, .centurion, .tribune, .senator, .pota: break
        }

        for qso in log {
            if let band, qso["band"].lowercased() != band.lowercased() { continue }
            guard mode.includes(qso["mode"]), let key = key(for: award, qso, country: country) else { continue }
            if award == .wpx { add(key, key) }
            // A country cty.dat no longer lists (a deleted one) isn't counted.
            guard var item = items[key] else { continue }
            item.contacts += 1
            for (name, field) in confirmations where ["Y", "V"].contains(qso[field].uppercased())
                && !item.confirmedBy.contains(name) {
                item.confirmedBy.append(name)
            }
            items[key] = item
        }
        var shown = order.compactMap { items[$0] }
        if award == .wpx { shown.sort { $0.key < $1.key } }
        return AwardProgress(award: award, mode: mode, items: shown)
    }

    // What a contact counts for: its country, state, zone or prefix, or
    // nil if it counts for nothing (a Canadian call for WAS, say).
    static func key(for award: Award, _ qso: QSO, country: (String) -> Country?) -> String? {
        let place = country(qso.call)
        switch award {
        case .dxcc:
            return place?.name
        case .was:
            let state = qso["state"].uppercased()
            guard states.contains(state) else { return nil }
            // A state written on a DX contact isn't a US state. Without
            // cty.dat, the state is taken as it is.
            if let place, !wasCountries.contains(place.name) { return nil }
            return state
        case .waz:
            if let zone = Int(qso["cqz"]), (1...40).contains(zone) { return String(zone) }
            // From the country only if all of it is in one zone.
            guard let place, !place.spansZones, (1...40).contains(place.cqZone) else { return nil }
            return String(place.cqZone)
        case .wpx:
            let given = qso["pfx"].uppercased()
            return given.isEmpty ? WPX.prefix(qso.call) : given
        case .centurion, .tribune, .senator, .pota:
            return nil
        }
    }

    // MARK: - POTA

    // Each park worked, by reference, named from POTA's park list
    // ("US-1333, Big Pocono State Park, Pennsylvania") when it's there.
    static func potaProgress(log: [QSO], band: String?, mode: AwardMode,
                             parkName: (String) -> String?) -> AwardProgress {
        var items: [String: AwardItem] = [:]
        for qso in log {
            if let band, qso["band"].lowercased() != band.lowercased() { continue }
            guard mode.includes(qso["mode"]) else { continue }
            for park in parks(in: qso) {
                var item = items[park] ?? AwardItem(key: park, name: parkName(park) ?? park, noQSL: true)
                item.contacts += 1
                items[park] = item
            }
        }
        return AwardProgress(award: .pota, mode: mode, items: items.values.sorted { $0.key < $1.key })
    }

    // The parks a contact was with: "US-1333", or several for a two-fer.
    static func parks(in qso: QSO) -> [String] {
        var text = qso["pota_ref"]
        if text.isEmpty, qso["sig"].uppercased() == "POTA" { text = qso["sig_info"] }
        var parks: [String] = []
        for part in text.split(separator: ",") {
            // ADIF allows a place after "@" ("US-1333@US-PA"); it isn't
            // part of the park.
            var park = part.split(separator: "@").first.map(String.init)?
                .trimmingCharacters(in: .whitespaces).uppercased() ?? ""
            if park.hasPrefix("K-") { park = "US-" + park.dropFirst(2) }
            // "US-1333": letters or digits, a dash, then the number. Anything
            // else (a typing slip) isn't a park.
            let halves = park.split(separator: "-", omittingEmptySubsequences: false)
            guard halves.count == 2, (1...4).contains(halves[0].count), halves[0].allSatisfy({ $0.isLetter || $0.isNumber }),
                  (4...6).contains(halves[1].count), halves[1].allSatisfy(\.isNumber), !parks.contains(park) else { continue }
            parks.append(park)
        }
        return parks
    }

    // MARK: - SKCC

    // What the SKCC awards need from the member list, passed in so the
    // check can use its own: your dates (nil if your call isn't in the
    // list), and a member's number and dates.
    struct SKCC {
        var mine: SKCCDates?
        var number: (String) -> String?        // a call's number ("12345T")
        var dates: (String) -> SKCCDates?      // a number's dates
    }

    // The days the rules start from, and K9SKC's (the club call's) last.
    static let tribuneFrom = day(2007, 3, 1)
    static let senatorFrom = day(2013, 8, 1)
    static let clubCallUntil: [Award: Date] = [.centurion: day(2009, 12, 1), .tribune: day(2008, 10, 1)]

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static func skccProgress(_ award: Award, log: [QSO], band: String?, skcc: SKCC?) -> AwardProgress {
        func blocked(_ why: String) -> AwardProgress { AwardProgress(award: award, mode: .cw, items: [], blocked: why) }
        guard let skcc else { return blocked("turn on SKCC numbers in Settings > Clubs to count it.") }
        guard let mine = skcc.mine, mine.joined != nil else {
            return blocked("your callsign (Settings > Profiles) isn't in SKCC's member list.")
        }
        if award == .tribune, mine.centurion == nil { return blocked("it starts once you're a Centurion.") }
        if award == .senator, mine.tribuneX8 == nil { return blocked("it starts once you're Tribune x8.") }

        var items: [String: AwardItem] = [:]
        for qso in log where Spot.group(of: qso["mode"]) == "CW" {
            if let band, qso["band"].lowercased() != band.lowercased() { continue }
            // Their number as logged, or from the list by call.
            let logged = qso["skcc"].isEmpty ? (skcc.number(qso.call) ?? "") : qso["skcc"]
            guard let number = SKCCRoster.digits(logged) else { continue }
            var item = items[number] ?? AwardItem(key: number, name: "\(qso.call), SKCC \(logged.uppercased())")
            item.contacts += 1
            if !item.isConfirmed {
                let why = Self.why(award, qso, theirs: skcc.dates(number), mine: mine)
                if why.isEmpty {
                    item.confirmedBy = ["SKCC"]
                    item.why = ""
                    // The contact that counts names the member.
                    item.name = "\(qso.call), SKCC \(logged.uppercased())"
                } else if item.why.isEmpty {
                    item.why = why
                }
            }
            items[number] = item
        }
        // Members that count first, then the rest, each by call.
        let shown = items.values.sorted {
            $0.isConfirmed != $1.isConfirmed ? $0.isConfirmed : $0.name < $1.name
        }
        return AwardProgress(award: award, mode: .cw, items: shown)
    }

    // Why a contact doesn't count for an SKCC award, or "" if it does.
    static func why(_ award: Award, _ qso: QSO, theirs: SKCCDates?, mine: SKCCDates) -> String {
        let on = qso.timeOn
        // A date is "by the day of the contact" if it's no later than it.
        func by(_ date: Date?) -> Bool { date.map { $0 <= on } ?? false }
        if Callsign.normalized(qso.call).hasPrefix("K9SKC"), clubCallUntil[award].map({ on >= $0 }) ?? true {
            return "the club's own call doesn't count"
        }
        guard let theirs, theirs.joined != nil else { return "not in SKCC's member list" }
        guard by(theirs.joined) else { return "they hadn't joined SKCC yet" }
        guard by(mine.joined) else { return "you hadn't joined SKCC yet" }
        switch award {
        case .tribune:
            guard on >= tribuneFrom else { return "before Tribune began, 1 March 2007" }
            guard by(mine.centurion) else { return "you weren't a Centurion yet" }
            guard by(theirs.centurion) else { return "they weren't a Centurion yet" }
        case .senator:
            guard on >= senatorFrom else { return "before Senator began, 1 August 2013" }
            guard by(mine.tribuneX8) else { return "you weren't Tribune x8 yet" }
            guard by(theirs.tribune) else { return "they weren't a Tribune yet" }
        default:
            break
        }
        return ""
    }
}

// CQ's WPX prefix rules, for a call LoTW hasn't given one for:
//   N3ABC -> N3, 2E0ABC -> 2E0, 9A1A -> 9A1, RAEM (no digit) -> RA0
//   W1AW/3 -> W3 (a new call area)
//   KH6/W1AW and W1AW/KH6 -> KH6; DL/W1AW -> DL0 (no digit: add 0)
//   /P, /M, /MM, /AM, /QRP and the like are left out
enum WPX {
    static let modifiers: Set<String> = ["P", "M", "MM", "AM", "QRP", "QRPP", "A", "R", "LH", "B", "BCN", "J"]

    static func prefix(_ raw: String) -> String? {
        var parts = raw.uppercased().split(separator: "/").map(String.init)
        parts.removeAll { modifiers.contains($0) }
        // The call is the longest part; of two the same length, the second
        // ("VP2E/W1AW": a place first is the usual way to write it).
        guard let base = parts.reversed().max(by: { $0.count < $1.count }), base.count > 1 else { return nil }
        var others = parts
        others.remove(at: parts.lastIndex(of: base)!)
        // W1AW/3: the call area changes.
        if let area = others.first(where: { $0.count == 1 && $0.first!.isNumber }), let own = ofCall(base) {
            return String(own.reversed().drop { $0.isNumber }.reversed()) + area
        }
        // KH6/W1AW or DL/W1AW: where it's operated from.
        if let place = others.first(where: { $0.count > 1 }) {
            return place.contains(where: \.isNumber) ? ofCall(place) : place + "0"
        }
        return ofCall(base)
    }

    // A plain call's prefix: up to and including its last digit that has
    // letters after it ("N3ABC" -> "N3", "VP2E" -> "VP2"); a call with no
    // digit gets its first two letters and a 0.
    static func ofCall(_ call: String) -> String? {
        let letters = Array(call)
        guard !letters.isEmpty, letters.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        guard let lastDigit = letters.indices.last(where: { letters[$0].isNumber }) else {
            return String(letters.prefix(2)) + "0"
        }
        // A call ending in digits ("VP2E" isn't one) uses the last digit
        // before its last letters.
        let end = letters.indices.last(where: { letters[$0].isNumber && $0 + 1 < letters.count
            && letters[($0 + 1)...].allSatisfy(\.isLetter) }) ?? lastDigit
        return String(letters[...end])
    }
}
