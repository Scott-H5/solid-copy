// Awards.swift
//
// Award tracking (v1.5 item 2): how far the log is towards four awards,
// counted the way their sponsors count them.
//
//   DXCC (ARRL)  countries: 100 confirmed earns it
//   WAS  (ARRL)  the 50 US states (DC counts as Maryland, so isn't one)
//   WAZ  (CQ)    the 40 CQ zones
//   WPX  (CQ)    different prefixes: 400 for mixed modes, 300 for one
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
// No windows here, and the country data is passed in, so
// tools/check-awards.sh can check the counting with a made-up log.

import Foundation

enum Award: String, CaseIterable {
    case dxcc, was, waz, wpx

    var title: String {
        switch self {
        case .dxcc: "DXCC"
        case .was: "WAS"
        case .waz: "WAZ"
        case .wpx: "WPX"
        }
    }

    // What it counts, said after a number ("38 states").
    var counts: String {
        switch self {
        case .dxcc: "countries"
        case .was: "states"
        case .waz: "zones"
        case .wpx: "prefixes"
        }
    }

    // How many confirmed earn the basic award.
    func goal(mode: AwardMode) -> Int {
        switch self {
        case .dxcc: 100
        case .was: 50
        case .waz: 40
        case .wpx: mode == .mixed ? 400 : 300
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
    var confirmedBy: [String] = []   // "LoTW", "card": any confirmation

    var isWorked: Bool { contacts > 0 }
    var isConfirmed: Bool { !confirmedBy.isEmpty }

    // One line, read in one stop by VoiceOver.
    var line: String {
        let times = contacts == 1 ? "1 contact" : "\(contacts) contacts"
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

    var worked: Int { items.filter(\.isWorked).count }
    var confirmed: Int { items.filter(\.isConfirmed).count }

    // "WAS: 38 states worked, 31 confirmed, 19 more confirmed for the award."
    var line: String {
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
                         country: (String) -> Country?, allCountries: [Country]) -> AwardProgress {
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
        case .wpx: break
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
        }
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
