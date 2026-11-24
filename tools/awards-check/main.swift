// Checks award counting (Sources/Awards/Awards.swift) with a made-up log
// and a small cty.dat of its own: nothing real is read or changed.

import Foundation

func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }

@MainActor func run() {
    let cty = """
    United States:            05:  08:  NA:   37.60:    91.87:     5.0:  K:
        AA,K,N,W,=K6XX(3)[6];
    Canada:                   05:  09:  NA:   44.35:    78.75:     5.0:  VE:
        VE,VA;
    Falkland Islands:         13:  16:  SA:  -51.63:    58.72:     4.0:  VP8:
        VP8;
    Sicily:                   15:  28:  EU:   37.50:   -14.00:    -1.0:  *IT9:
        IT9;
    Italy:                    15:  28:  EU:   42.82:   -12.58:    -1.0:  I:
        I;
    """
    let table = CountryTable(cty)
    let country: (String) -> Country? = { table.country(of: $0) }

    // cty.dat: zones, and countries that span them.
    check(table.all.map(\.name) == ["United States", "Canada", "Falkland Islands", "Italy"],
          "every DXCC country, not WAE-only ones: \(table.all.map(\.name))")
    check(country("VP8XYZ")?.cqZone == 13 && country("VP8XYZ")?.spansZones == false, "a one-zone country's zone")
    check(country("W1AW")?.spansZones == true && country("K6XX")?.spansZones == true,
          "a country with a call in another zone spans zones")

    // WPX prefixes.
    let prefixes = ["N3ABC": "N3", "2E0ABC": "2E0", "9A1A": "9A1", "RAEM": "RA0", "W1AW/3": "W3",
                    "KH6/W1AW": "KH6", "W1AW/KH6": "KH6", "DL/W1AW": "DL0", "W1AW/P": "W1", "VP2E/W1AW": "VP2",
                    "KB3CFK/QRP": "KB3", "HG19A": "HG19"]
    for (call, expected) in prefixes.sorted(by: { $0.key < $1.key }) {
        check(WPX.prefix(call) == expected, "WPX: \(call) is \(expected) (\(WPX.prefix(call) ?? "none"))")
    }
    check(WPX.prefix("") == nil && WPX.prefix("W1A#") == nil, "WPX: no prefix from nothing or odd text")

    // A log.
    var log: [QSO] = []
    func add(_ call: String, band: String = "20m", mode: String = "CW", state: String = "", cqz: String = "",
             pfx: String = "", lotw: Bool = false, card: Bool = false, eqsl: Bool = false) {
        var qso = QSO(call: call, timeOn: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + log.count * 60)))
        qso["band"] = band; qso["mode"] = mode; qso["state"] = state; qso["cqz"] = cqz; qso["pfx"] = pfx
        if lotw { qso["lotw_qsl_rcvd"] = "Y" }
        if card { qso["qsl_rcvd"] = "Y" }
        if eqsl { qso["eqsl_qsl_rcvd"] = "Y" }
        log.append(qso)
    }
    add("W1AW", state: "CT", cqz: "5", lotw: true)
    add("W1AW", band: "40m", mode: "SSB", state: "CT", cqz: "5")
    add("K6XX", state: "CA", cqz: "3", card: true)
    add("N3ABC", mode: "FT8", state: "PA")
    add("W4DC", state: "DC", lotw: true)
    add("VE3ABC", state: "ON", lotw: true)
    add("VP8XYZ", band: "40m", eqsl: true)
    add("I2ABC", state: "NY", lotw: true)
    add("K3LR", state: "PA", pfx: "K3", eqsl: true)

    func progress(_ award: Award, band: String? = nil, mode: AwardMode = .mixed) -> AwardProgress {
        Awards.progress(award, log: log, band: band, mode: mode, country: country, allCountries: table.all)
    }

    // WAS.
    let was = progress(.was)
    check(was.items.count == 50, "WAS lists the 50 states")
    check(was.worked == 3 && was.confirmed == 2, "WAS: CT, CA, PA worked; CT (LoTW) and CA (card) confirmed; "
          + "DC isn't a state, Ontario and an Italian 'NY' aren't US, eQSL doesn't count (\(was.worked), \(was.confirmed))")
    let ct = was.items.first { $0.key == "CT" }!
    check(ct.line == "Connecticut: confirmed by LoTW, 2 contacts", "a state's line: \(ct.line)")
    check(was.items.first { $0.key == "PA" }!.line == "Pennsylvania: worked, not confirmed, 2 contacts", "worked, not confirmed")
    check(was.items.first { $0.key == "UT" }!.line == "Utah: not worked", "not worked")
    check(was.items.first?.name == "Alabama" && was.items.last?.name == "Wyoming", "states in name order")
    check(was.line == "WAS: 3 states worked, 2 confirmed, 48 more confirmed for the award.", "the award's line: \(was.line)")

    // Band and mode.
    check(progress(.was, band: "40m").worked == 1, "on 40 meters, only the 40 meter contact")
    check(progress(.was, mode: .digital).worked == 1 && progress(.was, mode: .phone).worked == 1
          && progress(.was, mode: .cw).worked == 3, "digital, phone and CW counted apart")

    // DXCC.
    let dxcc = progress(.dxcc)
    check(dxcc.items.map(\.name) == ["Canada", "Falkland Islands", "Italy", "United States"], "every country, by name")
    check(dxcc.worked == 4 && dxcc.confirmed == 3, "DXCC: 4 worked; the Falklands only by eQSL (\(dxcc.confirmed))")

    // WAZ: the zone field, or a one-zone country's zone.
    let waz = progress(.waz)
    let zones = waz.items.filter(\.isWorked).map(\.key)
    check(zones == ["3", "5", "13", "15"], "zones 3 and 5 from the field (and Canada, all zone 5 here), 13 from the "
          + "Falklands, 15 from Italy; no guess for the US call without one: \(zones)")
    check(waz.items.first { $0.key == "5" }!.contacts == 3, "zone 5: W1AW twice and VE3ABC; not N3ABC, whose zone isn't known")

    // WPX: LoTW's prefix first, then the call's.
    let wpx = progress(.wpx)
    check(wpx.items.map(\.key) == ["I2", "K3", "K6", "N3", "VE3", "VP8", "W1", "W4"], "prefixes worked: \(wpx.items.map(\.key))")
    check(progress(.wpx, mode: .cw).line.hasSuffix("295 more confirmed for the award.")
          && wpx.line.hasSuffix("395 more confirmed for the award."), "WPX: 300 for one mode, 400 mixed")

    // Earned.
    var many = AwardProgress(award: .waz, mode: .mixed, items: (1...40).map { AwardItem(key: "\($0)", name: "Zone \($0)", contacts: 1, confirmedBy: ["LoTW"]) })
    check(many.line == "WAZ: 40 zones worked, 40 confirmed, enough for the award (40).", "earned: \(many.line)")
    many.items[0].confirmedBy = []
    check(many.line.hasSuffix("1 more confirmed for the award."), "one to go")
    // SKCC.
    func on(_ text: String) -> Date { SKCCRoster.date(text)! }
    let roster = SKCCRoster.parse("""
    SKCCNR|CALL|NAME|QTH|SPC|OLDCALL|SKCC|DXCODE|JOINDATE|CENTDATE|TRIBDATE|TX8DATE|SENDATE|DXENTITY
    100T|N3ABC|Me|Here|PA||100|291|01 Jan 2010|01 Jan 2012|01 Jan 2014|01 Jan 2016||USA
    200C|K1AAA|A|There|CT||200|291|01 Jan 2010|01 Jun 2015||||USA
    300T|K2BBB|B|There|NY||300|291|01 Jan 2011|01 Jan 2012|01 Jan 2017|||USA
    400|K3CCC|C|There|PA||400|291|01 Jan 2020|||||USA
    500S|W9OLD/SK|D|There|IL||500|291|01 Jan 2008|01 Jan 2009|01 Jan 2010|01 Jan 2011|01 Jan 2012|USA
    """)
    check(roster.dates["100"] == SKCCDates(joined: on("01 Jan 2010"), centurion: on("01 Jan 2012"), tribune: on("01 Jan 2014"),
                                           tribuneX8: on("01 Jan 2016"), senator: nil), "SKCC: a member's dates read")
    check(roster.dates["500"]?.senator == on("01 Jan 2012") && roster.byCall["W9OLD"] == nil,
          "a silent key's dates are kept, though the call isn't looked up")
    let skcc = Awards.SKCC(mine: roster.dates["100"], number: { roster.byCall[$0] }, dates: { roster.dates[SKCCRoster.digits($0) ?? ""] })

    var keyLog: [QSO] = []
    func key(_ call: String, _ day: String, skcc number: String = "", mode: String = "CW", band: String = "20m") {
        var qso = QSO(call: call, timeOn: on(day).addingTimeInterval(3600)); qso["mode"] = mode; qso["band"] = band
        qso["skcc"] = number
        keyLog.append(qso)
    }
    key("K1AAA", "01 Jan 2016", skcc: "200C")   // counts for C and T (a Centurion since June 2015)
    key("K1AAA", "01 Feb 2016", skcc: "200C")   // the same member again
    key("K2BBB", "01 Jun 2013")                 // number from the list by call; T: counts (both C by then)
    key("K3CCC", "01 Jun 2019", skcc: "400")    // before they joined
    key("W9OLD", "01 Jun 2017", skcc: "500S")   // a silent key since: still counts
    key("K2BBB", "01 Jan 2018", mode: "SSB")    // not CW: left out
    key("W1NOT", "01 Jan 2018", skcc: "99999")  // not in the list
    key("K9SKC", "01 Jan 2018", skcc: "1")      // the club call
    func skccLine(_ award: Award, _ log: [QSO]) -> AwardProgress {
        Awards.progress(award, log: log, band: nil, mode: .mixed, country: country, allCountries: [], skcc: skcc)
    }
    let cent = skccLine(.centurion, keyLog)
    check(cent.confirmed == 3, "Centurion: K1AAA, K2BBB and the silent key count (\(cent.confirmed)): \(cent.items.map(\.line))")
    check(cent.items.first { $0.key == "200" }!.line == "K1AAA, SKCC 200C: counts, 2 contacts", "a member counts once")
    check(cent.items.first { $0.key == "400" }!.line == "K3CCC, SKCC 400: doesn't count, they hadn't joined SKCC yet, 1 contact",
          "before they joined")
    check(cent.items.first { $0.key == "99999" }!.why == "not in SKCC's member list", "a number not in the list")
    check(cent.items.first { $0.key == "1" }!.why == "the club's own call doesn't count", "K9SKC")
    check(cent.line == "SKCC Centurion: 3 members count, 97 more for Centurion.", "Centurion's line: \(cent.line)")
    let trib = skccLine(.tribune, keyLog)
    check(trib.confirmed == 3 && trib.items.first { $0.key == "300" }!.isConfirmed, "Tribune: C or higher, both, that day")
    let sen = skccLine(.senator, keyLog)
    let senCounts = sen.items.filter(\.isConfirmed).map(\.key)
    check(senCounts == ["500"], "Senator: only the Tribune worked after your Tx8 day (\(senCounts))")
    check(sen.items.first { $0.key == "200" }!.why == "they weren't a Tribune yet", "a Centurion isn't enough for Senator")
    check(sen.items.first { $0.key == "300" }!.why == "before Senator began, 1 August 2013", "Senator's start")
    var before = keyLog; before.removeAll { $0.call != "K2BBB" }
    let early = Awards.progress(.tribune, log: before, band: nil, mode: .mixed, country: country, allCountries: [],
                                skcc: Awards.SKCC(mine: SKCCDates(joined: on("01 Jan 2010"), centurion: on("01 Jan 2014")),
                                                  number: skcc.number, dates: skcc.dates))
    check(early.items.first?.why == "you weren't a Centurion yet", "Tribune: not before your own Centurion day")
    check(Awards.progress(.senator, log: keyLog, band: nil, mode: .mixed, country: country, allCountries: [],
                          skcc: Awards.SKCC(mine: SKCCDates(joined: on("01 Jan 2010")), number: skcc.number, dates: skcc.dates)).line
          == "SKCC Senator: it starts once you're Tribune x8.", "Senator waits for Tx8")
    check(skccLine(.centurion, keyLog).items.count == 6 && skccLine(.centurion, keyLog.filter { $0["band"] == "40m" }).items.isEmpty,
          "SSB left out; band filter")
    check(Awards.progress(.centurion, log: keyLog, band: nil, mode: .mixed, country: country, allCountries: []).line
          == "SKCC Centurion: turn on SKCC numbers in Settings > Clubs to count it.", "no member list")
    var levels = AwardProgress(award: .tribune, mode: .cw, items: (1...120).map { AwardItem(key: "\($0)", name: "", contacts: 1, confirmedBy: ["SKCC"]) })
    check(levels.line == "SKCC Tribune: 120 members count, enough for Tx2; 30 more for Tx3.", "levels: \(levels.line)")
    levels.items = Array(levels.items.prefix(1))
    check(levels.line == "SKCC Tribune: 1 member counts, 49 more for Tribune.", "one member")
    // POTA.
    var parkLog: [QSO] = []
    func hunt(_ call: String, _ park: String, sig: String = "", band: String = "20m", mode: String = "CW") {
        var qso = QSO(call: call, timeOn: Date(timeIntervalSince1970: TimeInterval(1_750_000_000 + parkLog.count * 60)))
        qso["band"] = band; qso["mode"] = mode
        if sig == "POTA" { qso["sig"] = sig; qso["sig_info"] = park } else { qso["pota_ref"] = park; qso["sig"] = sig }
        parkLog.append(qso)
    }
    hunt("K3AAA", "US-1333")
    hunt("K3BBB", "K-1333", mode: "SSB")                   // the old prefix: the same park
    hunt("K3CCC", "US-0001, US-0002@US-PA", band: "40m")   // a two-fer, with a place after "@"
    hunt("K3DDD", "VE-0100", sig: "POTA")                 // in SIG and SIG_INFO
    hunt("K3EEE", "US-12x4")                              // a slip: not a park
    hunt("K3FFF", "US-0003", sig: "WWFF")                 // POTA_REF is used whatever SIG says
    check(Awards.parks(in: parkLog[2]) == ["US-0001", "US-0002"] && Awards.parks(in: parkLog[1]) == ["US-1333"],
          "parks: a two-fer is two parks; K-1333 is US-1333")
    let names = ["US-1333": "US-1333, Big Pocono State Park, Pennsylvania"]
    let pota = Awards.progress(.pota, log: parkLog, band: nil, mode: .mixed, country: country, allCountries: [],
                               parkName: { names[$0] })
    check(pota.items.map(\.key) == ["US-0001", "US-0002", "US-0003", "US-1333", "VE-0100"], "parks worked: \(pota.items.map(\.key))")
    check(pota.items.first { $0.key == "US-1333" }!.line == "US-1333, Big Pocono State Park, Pennsylvania: worked, 2 contacts",
          "a park's line, named from the park list")
    check(pota.items.first { $0.key == "VE-0100" }!.line == "VE-0100: worked, 1 contact", "a park not in the list: its reference")
    check(pota.line == "POTA Hunter: 5 parks worked, 5 more for Bronze.", "POTA's line: \(pota.line)")
    check(Awards.progress(.pota, log: parkLog, band: "40m", mode: .mixed, country: country, allCountries: []).worked == 2
          && Awards.progress(.pota, log: parkLog, band: nil, mode: .phone, country: country, allCountries: []).worked == 1,
          "band and mode")
    let lots = AwardProgress(award: .pota, mode: .mixed, items: (1...312).map { AwardItem(key: "US-\($0)", name: "", contacts: 1, noQSL: true) })
    check(lots.line == "POTA Hunter: 312 parks worked, enough for the 300 park award; 88 more for the 400 park award.",
          "higher levels: \(lots.line)")

    // Club awards (ClubAwards.swift): different members worked.
    let utc = ClubPeriod.utc
    func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }
    var clubLog: [QSO] = []
    func member(_ call: String, _ field: String, _ number: String, on date: Date, band: String = "20m", mode: String = "CW") {
        var qso = QSO(call: call, timeOn: date)
        qso["band"] = band; qso["mode"] = mode; qso[field] = number
        clubLog.append(qso)
    }
    member("W1AAA", "fists", "1234", on: day(2026, 11, 2))
    member("W1AAA", "fists", " 1234 ", on: day(2026, 11, 3), band: "40m")    // the same member again
    member("W1BBB", "fists", "2345", on: day(2026, 10, 31, 23))            // last month, just
    member("W1CCC", "fists", "3456", on: day(2026, 11, 30, 23), mode: "SSB")
    member("W1DDD", "fists", "", on: day(2026, 11, 5))                      // no number: not counted
    member("W1EEE", "skcc", "12345T", on: day(2026, 11, 6))
    member("W1EEE/P", "skcc", "12345", on: day(2026, 11, 7))                // one SKCC member, two levels
    let fists = ClubAwards.Club(field: "fists", title: "FISTS", goal: 5)
    let all = ClubAwards.progress(fists, log: clubLog, band: nil, mode: .mixed, period: nil)
    check(all.worked == 3 && all.items.first { $0.key == "1234" }?.contacts == 2,
          "club: each member once, by number (\(all.worked) worked)")
    check(all.items.first { $0.key == "1234" }!.line == "W1AAA, FISTS 1234: worked, 2 contacts", "club: a member's line")
    check(all.line == "FISTS: 3 members worked; 2 more for your goal of 5.", "club: the line with a goal: \(all.line)")
    let now = day(2026, 11, 24)
    let november = ClubPeriod.thisMonth.interval(now: now, from: now, to: now)
    check(ClubAwards.progress(fists, log: clubLog, band: nil, mode: .mixed, period: november).worked == 2,
          "club: this month leaves out 31 October 23:00 UTC")
    let october = ClubPeriod.lastMonth.interval(now: now, from: now, to: now)
    check(ClubAwards.progress(fists, log: clubLog, band: nil, mode: .mixed, period: october).worked == 1, "club: last month")
    let between = ClubPeriod.between.interval(now: now, from: day(2026, 11, 3), to: day(2026, 11, 2))
    check(ClubAwards.progress(fists, log: clubLog, band: nil, mode: .mixed, period: between).worked == 1
          && between?.end == day(2026, 11, 4, 0), "club: between two days, either order, the last day included")
    check(ClubAwards.progress(fists, log: clubLog, band: "40m", mode: .mixed, period: nil).worked == 1
          && ClubAwards.progress(fists, log: clubLog, band: nil, mode: .cw, period: nil).worked == 2,
          "club: band and mode")
    check(ClubPeriod.all.interval(now: now, from: now, to: now) == nil
          && ClubPeriod.thisYear.interval(now: now, from: now, to: now)?.start == day(2026, 1, 1, 0),
          "club: all dates, and this year")
    let skccClub = ClubAwards.Club(field: "skcc", title: "SKCC")
    check(ClubAwards.progress(skccClub, log: clubLog, band: nil, mode: .mixed, period: nil).worked == 1,
          "club: SKCC 12345T and 12345 are one member")
    // A member list: numbers for calls logged without one, and Still needed.
    let listed = ["W1DDD": "4567", "W1AAA": "1234", "W1ZZZ": "9999"]
    let withList = ClubAwards.Club(field: "fists", title: "NAQCC", goal: 3, listed: listed, number: { listed[$0] })
    let fromList = ClubAwards.progress(withList, log: clubLog, band: nil, mode: .mixed, period: nil)
    check(fromList.worked == 4, "club: the list gives a number for a call logged without one")
    check(fromList.items.filter { !$0.isConfirmed }.map(\.line) == ["W1ZZZ, NAQCC 9999: not worked"],
          "club: still needed is the list's members not worked")
    check(fromList.line == "NAQCC: 4 members worked, 2 of the 3 on its list; your goal of 3 is reached.", "club: with a list: \(fromList.line)")
    print("All award checks passed.")
}

MainActor.assumeIsolated { run() }
