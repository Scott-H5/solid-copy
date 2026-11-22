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
    print("All award checks passed.")
}

MainActor.assumeIsolated { run() }
