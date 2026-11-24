// ClubAwards.swift
//
// Club awards: how many different members of a club you've worked, for
// SKCC, FISTS, LICW, CWops and the club fields you've named yourself
// (Settings > Clubs). Clubs run many kinds of award and challenge ("work
// 100 members", "most members worked in a month"), so this counts the
// plain thing they all start from, members worked, and lets you narrow it:
//
//   Band and mode   as the other awards (the Awards window's menus)
//   Dates           all dates, this month, last month, this year, last
//                   year, or between two dates; in UTC, as logs are
//   Goal            a number you set per club ("50"): how many more to go
//
// A member is counted once, by their number: the number logged with the
// contact, or the club's own list's number for the call (SKCC's member
// list, or a member list file for your own club fields). A contact with no
// number for the club isn't a member's. No QSL is needed: clubs credit a
// contact made, and each club's own rules (a key type, a minimum length)
// are taken on trust.
//
// Still needed: with a member list file (your own club fields only, from
// Settings > Clubs), the members on the list you haven't worked yet.
// SKCC's list is the whole membership since 2006, tens of thousands, so
// it's left out of Still needed; SKCC's own awards are counted separately
// (Awards.swift).
//
// No windows here, and every list is passed in, so tools/check-awards.sh
// can check the counting with a made-up log.

import Foundation

// The dates a club award counts, in UTC days.
enum ClubPeriod: String, CaseIterable {
    case all, thisMonth, lastMonth, thisYear, lastYear, between

    var title: String {
        switch self {
        case .all: "All dates"
        case .thisMonth: "This month"
        case .lastMonth: "Last month"
        case .thisYear: "This year"
        case .lastYear: "Last year"
        case .between: "Between dates"
        }
    }

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // The span it covers, as of `now`: from the start of the first day to
    // the start of the day after the last. Nil for all dates. For Between
    // dates, `from` and `to` are the chosen days (either order).
    func interval(now: Date, from: Date, to: Date) -> DateInterval? {
        let calendar = Self.utc
        func span(_ unit: Calendar.Component, back: Int) -> DateInterval? {
            guard let shifted = calendar.date(byAdding: unit, value: -back, to: now) else { return nil }
            return calendar.dateInterval(of: unit, for: shifted)
        }
        switch self {
        case .all: return nil
        case .thisMonth: return span(.month, back: 0)
        case .lastMonth: return span(.month, back: 1)
        case .thisYear: return span(.year, back: 0)
        case .lastYear: return span(.year, back: 1)
        case .between:
            let first = calendar.startOfDay(for: min(from, to))
            let last = calendar.startOfDay(for: max(from, to))
            guard let end = calendar.date(byAdding: .day, value: 1, to: last) else { return nil }
            return DateInterval(start: first, end: end)
        }
    }

    // "this month", "1 to 30 November 2026", for the window's status line.
    func spoken(_ interval: DateInterval?) -> String {
        guard self == .between, let interval else { return title.lowercased() }
        let format = DateFormatter()
        format.timeZone = Self.utc.timeZone
        format.dateStyle = .long
        format.timeStyle = .none
        let last = interval.end.addingTimeInterval(-1)
        return "from \(format.string(from: interval.start)) to \(format.string(from: last))"
    }
}

// One club, and how it stands.
struct ClubProgress: Equatable {
    var field: String        // "fists", "app_solidcopy_club1"
    var title: String        // "FISTS", "NAQCC"
    // Members worked (counted), then, with a member list, the ones not
    // worked yet; each by call.
    var items: [AwardItem]
    var goal: Int?
    // How many members the club's list has, and how many of them you've
    // worked, if there's a list. (Members can be worked who aren't on it:
    // a number logged from the contact, from a list that's out of date.)
    var listCount: Int?
    var listWorked = 0

    var worked: Int { items.filter(\.isConfirmed).count }

    // "NAQCC: 40 members worked, 38 of the 312 on its list; 10 more for
    // your goal of 50."
    var line: String {
        var text = "\(title): \(worked) \(worked == 1 ? "member" : "members") worked"
        if let listCount { text += ", \(listWorked) of the \(listCount) on its list" }
        if let goal {
            text += worked >= goal ? "; your goal of \(goal) is reached" : "; \(goal - worked) more for your goal of \(goal)"
        }
        return text + "."
    }
}

enum ClubAwards {
    // What a club award needs from outside, passed in so the check can use
    // its own. `listed` is the club's member list (call as lookups match it
    // -> number), if it has one; `number` finds a call's number in any list
    // the club has (SKCC's member list too).
    struct Club {
        var field: String
        var title: String
        var goal: Int?
        var listed: [String: String]?
        var number: (String) -> String? = { _ in nil }
    }

    // A number as it's compared: "12345T" and "12345" are one SKCC member
    // (the letter is a level reached); any other club's as typed, without
    // spaces, in capitals.
    static func key(_ number: String, field: String) -> String? {
        let trimmed = number.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else { return nil }
        if field == "skcc" { return SKCCRoster.digits(trimmed) }
        return trimmed.replacingOccurrences(of: " ", with: "")
    }

    static func progress(_ club: Club, log: [QSO], band: String?, mode: AwardMode,
                         period: DateInterval?) -> ClubProgress {
        var items: [String: AwardItem] = [:]
        for qso in log {
            if let band, qso["band"].lowercased() != band.lowercased() { continue }
            if let period, !period.contains(qso.timeOn) || qso.timeOn == period.end { continue }
            guard mode.includes(qso["mode"]) else { continue }
            let lookup = CallsignLookup.lookupCall(for: qso.call)
            let logged = qso[club.field].trimmingCharacters(in: .whitespaces)
            let number = logged.isEmpty ? (club.number(lookup) ?? "") : logged
            guard let id = key(number, field: club.field) else { continue }
            // Named by the first contact counted, as the log shows it.
            var item = items[id] ?? AwardItem(key: id, name: "\(qso.call), \(club.title) \(number.uppercased())",
                                              confirmedBy: ["club"])
            item.contacts += 1
            items[id] = item
        }
        var shown = items.values.sorted { $0.name < $1.name }
        var listIDs: Set<String>?
        // The club's members not worked yet, from its list.
        if let listed = club.listed {
            listIDs = Set(listed.values.compactMap { key($0, field: club.field) })
            var notWorked: [String: AwardItem] = [:]
            for (call, number) in listed {
                guard let id = key(number, field: club.field), items[id] == nil, notWorked[id] == nil else { continue }
                notWorked[id] = AwardItem(key: id, name: "\(call), \(club.title) \(number.uppercased())")
            }
            shown += notWorked.values.sorted { $0.name < $1.name }
        }
        return ClubProgress(field: club.field, title: club.title, items: shown, goal: club.goal,
                            listCount: listIDs?.count, listWorked: listIDs.map { $0.intersection(items.keys).count } ?? 0)
    }

    // Goals you've set, per club field ("fists": 50). Kept with the
    // Awards window's other choices.
    static func goal(for field: String) -> Int? {
        (UserDefaults.standard.dictionary(forKey: "awards.clubGoals")?[field] as? Int).flatMap { $0 > 0 ? $0 : nil }
    }

    static func setGoal(_ goal: Int?, for field: String) {
        var goals = UserDefaults.standard.dictionary(forKey: "awards.clubGoals") ?? [:]
        goals[field] = goal.flatMap { $0 > 0 ? $0 : nil }
        UserDefaults.standard.set(goals, forKey: "awards.clubGoals")
    }
}
