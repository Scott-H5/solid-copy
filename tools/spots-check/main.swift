// tools/spots-check/main.swift
//
// Checks spots (Spots.swift, SpotsWindowController.swift) without the
// internet, with POTA-style JSON of its own and a throwaway log:
//   - reading POTA's spots, and skipping ones without a call or frequency;
//   - the line VoiceOver reads, and the radio mode for each spot;
//   - "worked today" by POTA's rule (park, band, mode, UTC day);
//   - the window's filters, and the selection kept when the list changes;
//   - Return on a spot filling the logging form, and logging it;
//   - countries from cty.dat (prefixes, exact calls, calls with "/");
//   - DX cluster spot lines, their mode, and whether they're needed;
//   - SOTA spots from the cluster: the summit, the Source filter, "worked
//     today" by SOTA's rule, and logging one.
// Add --live to also fetch POTA's real spots.
//
// Run it with:  bash tools/check-spots.sh

import AppKit

func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }

let now = Date()
let stamp = POTASpots.spotTime.string(from: now.addingTimeInterval(-180))
let older = POTASpots.spotTime.string(from: now.addingTimeInterval(-600))
let json = """
[
 {"activator": "w1aw", "frequency": "14062", "mode": "CW", "reference": "US-1333", "name": "Big Pocono State Park",
  "locationDesc": "US-PA", "spotTime": "\(stamp)", "comments": "QRV", "spotter": "K1ABC"},
 {"activator": "K2XYZ", "frequency": "7185.5", "mode": "SSB", "reference": "US-0015",
  "name": "Chesapeake and Ohio Canal National Historical Park", "locationDesc": "US-DC,US-MD,US-WV",
  "spotTime": "\(older)", "comments": null},
 {"activator": "N3FT", "frequency": "14074", "mode": "FT8", "reference": "US-1334", "name": "Pocono Lake Preserve",
  "locationDesc": "US-PA", "spotTime": "\(older)", "comments": ""},
 {"activator": "", "frequency": "14000", "mode": "CW"},
 {"activator": "K9BAD", "frequency": null, "mode": "CW"}
]
"""

MainActor.assumeIsolated {
    _ = NSApplication.shared
    // This check's own settings, left by the last run, start afresh.
    for key in ["spots.bandName", "spots.mode", "spots.hideWorked", "spots.source", "spots.neededOnly", "spots.nearMe"] {
        UserDefaults.standard.removeObject(forKey: key)
    }

    let spots = (try? POTASpots.spots(from: Data(json.utf8))) ?? []
    check(spots.count == 3, "three usable spots; one without a call and one without a frequency left out")
    check(spots[0].call == "W1AW" && spots[0].hertz == 14_062_000 && spots[1].hertz == 7_185_500,
          "calls in capitals, kilohertz to hertz")
    check((try? POTASpots.spots(from: Data("{\"not\": \"spots\"}".utf8))) == nil, "something else isn't taken as spots")
    check(spots[0].line(now: now, worked: false)
            == "W1AW, 14.062 CW, US-1333 Big Pocono State Park, Pennsylvania, 3 minutes ago. QRV",
          "the line read: \(spots[0].line(now: now, worked: false))")
    check(spots[1].line(now: now, worked: true).contains("District of Columbia, Maryland, West Virginia, 10 minutes ago, worked today"),
          "a park across three states, worked today")
    check(spots[0].radioMode == "CW" && spots[1].radioMode == "LSB" && spots[2].radioMode == "PKTUSB",
          "radio modes: CW, SSB below 10 MHz as LSB, FT8 as data")
    check(spots.map(\.modeGroup) == ["CW", "Phone", "Data"], "mode groups for the filter")

    // Worked today: the same park, band and mode, today (UTC).
    let today = POTASpots.utcDay.string(from: now)
    var qso = QSO(call: "W1AW", timeOn: now)
    qso["pota_ref"] = "US-1333"
    qso["band"] = "20m"
    qso["mode"] = "CW"
    check(spots[0].isWorked(by: qso, today: today), "worked: same park, band, mode and day")
    qso["band"] = "40m"
    check(!spots[0].isWorked(by: qso, today: today), "not worked on another band")
    qso["band"] = "20m"
    qso["pota_ref"] = "US-0015,US-1333"
    check(spots[0].isWorked(by: qso, today: today), "worked as part of a two-fer")
    let yesterday = QSO(call: "W1AW", timeOn: now.addingTimeInterval(-86_400 * 2))
    check(!spots[0].isWorked(by: yesterday, today: today), "not worked on another day")

    // The window: filters and selection.
    let logbook = try! Logbook(database: LogDatabase(fileURL: URL(fileURLWithPath: CommandLine.arguments[1])
        .appendingPathComponent("Logbook.sqlite")))
    let window = SpotsWindowController(logbook: logbook)
    SpotList.shared.set(spots, problem: nil)
    func table() -> NSTableView? {
        var found: NSTableView?
        func walk(_ v: NSView) { if let t = v as? NSTableView { found = t }; v.subviews.forEach(walk) }
        walk(window.window!.contentView!)
        return found
    }
    func popUp(_ label: String) -> NSPopUpButton? {
        var found: NSPopUpButton?
        func walk(_ v: NSView) {
            if let p = v as? NSPopUpButton, p.accessibilityLabel() == label { found = p }
            v.subviews.forEach(walk)
        }
        walk(window.window!.contentView!)
        return found
    }
    guard let list = table(), let mode = popUp("Mode") else { return check(false, "the window has its list and filters") }
    check(list.numberOfRows == 3, "every spot shown, newest first")
    list.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    mode.selectItem(withTitle: "Phone")
    _ = mode.target?.perform(mode.action, with: mode)
    check(list.numberOfRows == 1, "Mode: Phone shows only the SSB spot")
    mode.selectItem(withTitle: "All modes")
    _ = mode.target?.perform(mode.action, with: mode)
    guard let band = popUp("Band") else { return check(false, "the Band filter is there") }
    check(band.itemTitles.prefix(3) == ["All bands", "Current band", "160 meters"] && band.itemTitles.contains("20 meters"),
          "Band: All bands, Current band, then each band")
    band.selectItem(withTitle: "40 meters")
    _ = band.target?.perform(band.action, with: band)
    check(list.numberOfRows == 1, "Band: 40 meters shows only the 40 meter spot")
    band.selectItem(withTitle: "Current band")
    _ = band.target?.perform(band.action, with: band)
    check(list.numberOfRows == 3, "Current band without a radio shows every band")
    band.selectItem(withTitle: "All bands")
    _ = band.target?.perform(band.action, with: band)
    list.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
    var newer = spots
    newer[0].time = now
    SpotList.shared.set(newer, problem: nil)
    check(list.selectedRow == 2, "a new list keeps the same spot selected")

    // Return on a spot, with no radio: the form gets the call, park,
    // frequency, band and mode, and logging it keeps them.
    let form = LogEntryViewController(logbook: logbook)
    let main = NSWindow(contentViewController: form)
    main.layoutIfNeeded()
    form.useSpot(spots[0])
    check(form.callsignField.stringValue == "W1AW", "Return on a spot puts its call in Callsign")
    form.logContact(nil)
    let logged = logbook.contacts.last
    check(logged?.call == "W1AW" && logged?["pota_ref"] == "US-1333" && logged?["freq"] == "14.062"
          && logged?["band"] == "20m" && logged?["mode"] == "CW",
          "logged with the spot's park, frequency, band and mode: \(logged.map { "\($0["pota_ref"]) \($0["freq"]) \($0["band"]) \($0["mode"])" } ?? "nothing")")
    check(list.numberOfRows == 3 && (table()?.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)?
            .textField?.stringValue.contains("worked today") == true,
          "the spot now says worked today")

    if CommandLine.arguments.contains("--live") {
        let request = URLRequest(url: POTASpots.url, timeoutInterval: 20)
        var live: [Spot]?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            live = data.flatMap { try? POTASpots.spots(from: $0) }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 25)
        check(live != nil, "POTA's live spots read: \(live?.count ?? 0), the first \(live?.first?.line(now: Date(), worked: false) ?? "none")")
    }

    // MARK: DX cluster and countries

    let cty = """
    United States:            05:  08:  NA:   37.60:    91.87:     5.0:  K:
        AA,K,N,W,=VP2EXX;
    Canada:                   05:  09:  NA:   44.35:    78.75:     5.0:  VE:
        VA,VE,VY;
    Falkland Islands:         13:  16:  SA:  -51.63:    58.72:     4.0:  VP8:
        VP8;
    Anguilla:                 08:  11:  NA:   18.23:    63.00:     4.0:  VP2E:
        VP2E;
    Sicily:                   15:  28:  EU:   37.50:   -14.00:    -1.0:  *IT9:
        IT9;
    Italy:                    15:  28:  EU:   42.82:   -12.58:    -1.0:  I:
        I,IT;
    """
    let table = CountryTable(cty)
    check(table.count == 5, "cty.dat: 5 DXCC countries (Sicily is WAE only)")
    check(table.country(of: "W1AW")?.name == "United States" && table.country(of: "VE3ABC")?.name == "Canada",
          "countries by prefix")
    check(table.country(of: "VP8XYZ")?.name == "Falkland Islands" && table.country(of: "VP2EAB")?.name == "Anguilla",
          "the longest prefix wins (VP2E, not VP2 or V)")
    check(table.country(of: "VP2EXX")?.name == "United States", "an exact call overrides its prefix")
    check(table.country(of: "W1AW/VP2E")?.name == "Anguilla" && table.country(of: "VP2E/W1AW")?.name == "Anguilla",
          "a call operated from another country, either way round")
    check(table.country(of: "W1AW/P")?.name == "United States" && table.country(of: "W1AW/4")?.name == "United States",
          "portable and a new call area stay at home")
    check(table.country(of: "W1AW/MM") == nil, "at sea: no country")
    check(table.country(of: "IT9ABC")?.name == "Italy", "a WAE-only country's calls count for its DXCC country")
    let folder = URL(fileURLWithPath: CommandLine.arguments[1])
    Countries.shared.fileURL = folder.appendingPathComponent("cty.dat")
    try? cty.write(to: Countries.shared.fileURL, atomically: true, encoding: .utf8)

    let clusterLine = "DX de K1ABC:     14025.0  VP8XYZ       CQ CQ up 2                     1432Z\u{7}\r"
    let dx = DXCluster.spot(fromLine: clusterLine, now: now)
    check(dx?.call == "VP8XYZ" && dx?.hertz == 14_025_000 && dx?.mode == "CW" && dx?.source == "DX",
          "a cluster spot read: \(dx?.call ?? "nothing") \(dx?.hertz ?? 0) \(dx?.mode ?? "")")
    check(dx?.comments == "CQ CQ up 2, spotted by K1ABC", "its comment, and who spotted it")
    check(DXCluster.spot(fromLine: "Hello K1ABC, welcome to VE7CC", now: now) == nil
          && DXCluster.spot(fromLine: "DX de K1ABC: not a spot", now: now) == nil, "other lines aren't spots")
    check(DXCluster.mode(hertz: 14_074_000, comment: "") == "FT8" && DXCluster.mode(hertz: 14_200_000, comment: "") == "SSB"
          && DXCluster.mode(hertz: 7_030_000, comment: "") == "CW" && DXCluster.mode(hertz: 14_025_000, comment: "rtty") == "RTTY",
          "modes: FT8 by frequency, phone and CW by the band plan, RTTY from the comment")

    check(DXCluster.commands(skimmer: true, ft8: false) == ["SET/SKIMMER", "SET/NOFT8", "SET/NOFT4"]
          && DXCluster.commands(skimmer: false, ft8: true) == ["SET/NOSKIMMER", "SET/FT8", "SET/FT4"],
          "skimmer and FT8 spots asked for, on or off")
    let skimmed = DXCluster.spot(fromLine: "DX de W3LPL-#:   14023.5  DL1ABC       CW 21 dB 26 WPM CQ              0102Z", now: now)
    check(skimmed?.call == "DL1ABC" && skimmed?.mode == "CW", "a skimmer spot read: \(skimmed?.comments ?? "nothing")")

    // Needed, against the log so far (W1AW on 20m CW, United States).
    var fresh = dx!
    fresh.time = now
    let needs = WorkedCountries()
    check(needs.needed(fresh, country: table.country(of: "VP8XYZ"), log: logbook.contacts) == "new country",
          "a country never worked: new country")
    var usa = fresh
    usa.call = "K5ABC"
    check(needs.needed(usa, country: table.country(of: "K5ABC"), log: logbook.contacts) == nil,
          "a country worked on this band and mode: not needed")
    usa.hertz = 7_030_000
    check(needs.needed(usa, country: table.country(of: "K5ABC"), log: logbook.contacts) == "new band", "another band: new band")
    usa.hertz = 14_200_000
    usa.mode = "SSB"
    check(needs.needed(usa, country: table.country(of: "K5ABC"), log: logbook.contacts) == "new mode", "phone: new mode")
    // The same for the call in the logging form (CLAUDE.md item 6).
    let k5 = table.country(of: "K5ABC")
    check(needs.needed(country: table.country(of: "VP8XYZ"), band: "20m", modeGroup: "CW", log: logbook.contacts)
          == "new country", "form: a country never worked")
    check(needs.needed(country: k5, band: "20m", modeGroup: "CW", log: logbook.contacts) == nil
          && needs.needed(country: k5, band: "40m", modeGroup: "CW", log: logbook.contacts) == "new band"
          && needs.needed(country: k5, band: "20m", modeGroup: "Phone", log: logbook.contacts) == "new mode",
          "form: worked, new band, new mode")
    check(needs.needed(country: k5, band: nil, modeGroup: "", log: logbook.contacts) == nil,
          "form: band and mode unknown, only a new country is said")

    // In the window: the line says the country and that it's needed, and
    // DX: needed only leaves out the rest.
    // The needed sound as spots come in (CLAUDE.md item 9): a new country
    // chimes, once; a worked one doesn't; a second new one within 30
    // seconds doesn't either.
    UserDefaults.standard.removeObject(forKey: "sound.neededSpots")
    var chimes = 0
    SpotList.shared.chime = { chimes += 1 }
    SpotList.shared.addClusterSpot(fresh)
    check(chimes == 1, "a needed DX spot (new country) plays the needed sound")
    SpotList.shared.addClusterSpot(fresh)
    check(chimes == 1, "the same spot again: no second sound")
    usa.mode = "CW"
    usa.hertz = 14_030_000
    SpotList.shared.addClusterSpot(usa)
    var other = fresh
    other.call = "VE3ABC"  // Canada: never worked, so needed too
    SpotList.shared.addClusterSpot(other)
    check(chimes == 1, "a worked country: no sound; another new one within 30 seconds: none either")
    check(Tone.wav(Tone.samples(.buzz, [Tone.Note(hertz: 150, ms: 100)], level: 0.11)).count == 44 + 2 * (Tone.rate / 10 + Tone.rate / 50),
          "a sound is a WAV: header and samples")
    let loudest = Tone.samples(.bell, [Tone.Note(hertz: 1047, ms: 300)], level: 0.105).map { abs(Int($0)) }.max() ?? 0
    check(loudest > 0 && loudest <= Int(0.105 * Double(Int16.max)) + 1, "the bell stays under its level: \(loudest)")
    UserDefaults.standard.set("gone", forKey: "sound.dupe")
    check(Settings.alertSound(for: .dupe) == "buzz" && Settings.alertSound(for: .needed) == "bell",
          "the standard sounds: buzz for a dupe, bells for needed (an unknown choice falls back)")
    UserDefaults.standard.removeObject(forKey: "sound.dupe")
    SpotList.shared.chime = {}
    let lines = (0..<list.numberOfRows).compactMap {
        (list.view(atColumn: 0, row: $0, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue
    }
    check(lines.contains { $0.hasPrefix("VP8XYZ, 14.025 CW, Falkland Islands, needed: new country, just now") },
          "a DX spot's line: \(lines.first { $0.hasPrefix("VP8") } ?? "none")")
    func box(_ title: String) -> NSButton? {
        var found: NSButton?
        func walk(_ v: NSView) { if let b = v as? NSButton, b.title == title { found = b }; v.subviews.forEach(walk) }
        walk(window.window!.contentView!)
        return found
    }
    guard let neededOnly = box("DX: needed only") else { return check(false, "the needed-only box is there") }
    neededOnly.state = .on
    _ = neededOnly.target?.perform(neededOnly.action, with: neededOnly)
    check(list.numberOfRows == 5, "DX: needed only hides the K5ABC spot (\(list.numberOfRows) shown: 3 POTA, 2 DX)")
    neededOnly.state = .off
    _ = neededOnly.target?.perform(neededOnly.action, with: neededOnly)

    // Heard by: a second skimmer spotting VP8XYZ adds to the count.
    check(DXCluster.spotterCall("DL1ABC-2-#") == "DL1ABC" && DXCluster.spotterCall("K1ABC") == "K1ABC",
          "a skimmer's call without its ending")
    var again = DXCluster.spot(fromLine: "DX de VE3XX-#:   14025.0  VP8XYZ       CW 12 dB 25 WPM CQ             1433Z", now: now)!
    again.time = now
    SpotList.shared.addClusterSpot(again)
    let vp8 = (0..<list.numberOfRows).compactMap {
        (list.view(atColumn: 0, row: $0, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue
    }.first { $0.hasPrefix("VP8XYZ") } ?? ""
    check(vp8.contains("heard by 2"), "a station heard by two: \(vp8)")

    // Heard near me (N0CALL, North America): a spot heard only in South
    // America is left out; one heard in Canada too stays.
    var profile = Settings.currentProfile
    profile.station["station_callsign"] = "N0CALL"
    Settings.currentProfile = profile
    var far = DXCluster.spot(fromLine: "DX de VP8AA-#:   7010.0  K7XYZ        CW 9 dB 20 WPM CQ               1433Z", now: now)!
    far.time = now
    SpotList.shared.addClusterSpot(far)
    guard let near = box("DX: heard near me") else { return check(false, "the heard-near-me box is there") }
    let before = list.numberOfRows
    near.state = .on
    _ = near.target?.perform(near.action, with: near)
    let nearLines = (0..<list.numberOfRows).compactMap {
        (list.view(atColumn: 0, row: $0, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue
    }
    check(list.numberOfRows == before - 1 && !nearLines.contains { $0.hasPrefix("K7XYZ") }
          && nearLines.contains { $0.hasPrefix("VP8XYZ") },
          "DX: heard near me leaves out a spot heard only in South America")
    near.state = .off
    _ = near.target?.perform(near.action, with: near)

    // SOTA: a cluster spot whose comment names a summit.
    check(DXCluster.summit(in: "sota w4c/cm-001 qrp") == "W4C/CM-001" && DXCluster.summit(in: "G/LD-003") == "G/LD-003"
          && DXCluster.summit(in: "VK3/VE-123 SSB") == "VK3/VE-123",
          "summits found in comments")
    check(DXCluster.summit(in: "UP 2 US-1333") == nil && DXCluster.summit(in: "W1AW/AB-1234") == nil
          && DXCluster.summit(in: "KD2ABC/W4C/CM-001") == nil, "parks and calls with a slash aren't summits")
    var sota = DXCluster.spot(fromLine: "DX de K4XX:      14062.0  W4ABC/P      SOTA W4C/CM-001 CW          1440Z", now: now)!
    check(sota.source == "SOTA" && sota.reference == "W4C/CM-001" && sota.referenceField == "sota_ref",
          "a SOTA spot: \(sota.source) \(sota.reference)")
    sota.time = now
    SpotList.shared.addClusterSpot(sota)
    guard let source = popUp("Source") else { return check(false, "the Source filter is there") }
    source.selectItem(withTitle: "SOTA")
    _ = source.target?.perform(source.action, with: source)
    let sotaLine = (list.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue ?? ""
    check(list.numberOfRows == 1 && sotaLine.hasPrefix("W4ABC/P, 14.062 CW, summit W4C/CM-001, United States"),
          "Source: SOTA shows only the SOTA spot: \(sotaLine)")

    // Worked today, by SOTA's rule: the summit and the UTC day, any band.
    var chased = QSO(call: "W4ABC/P", timeOn: now)
    chased["sota_ref"] = "w4c/cm-001"
    chased["band"] = "40m"
    check(sota.isWorked(by: chased, today: today), "SOTA: worked on another band still counts")
    chased["sota_ref"] = "W4C/CM-002"
    check(!sota.isWorked(by: chased, today: today), "SOTA: another summit isn't this one")

    // Return on it: logged with their summit, not as a park.
    form.useSpot(sota)
    form.logContact(nil)
    let chasedLog = logbook.contacts.last
    check(chasedLog?.call == "W4ABC/P" && chasedLog?["sota_ref"] == "W4C/CM-001" && chasedLog?["pota_ref"] == "",
          "logged with the spot's summit: \(chasedLog?["sota_ref"] ?? "nothing")")
    check(list.numberOfRows == 1 && ((list.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)?
            .textField?.stringValue.contains("worked today") ?? false), "the SOTA spot now says worked today")

    // A park you tuned to yourself (v1.6 item 1): the call is spotted at
    // a park on POTA, so the park is logged though no spot was picked.
    func spot(_ call: String, _ park: String, minutesAgo: Double) -> Spot {
        Spot(source: "POTA", call: call, hertz: 7_040_000, mode: "CW", reference: park, parkName: "",
             location: "", time: now.addingTimeInterval(-minutesAgo * 60), comments: "")
    }
    let hunted = [spot("K8XYZ", "US-0001", minutesAgo: 20), spot("K8XYZ", "US-0002", minutesAgo: 5),
                  spot("N2OLD", "US-0003", minutesAgo: 90)]
    check(POTASpots.matchingPark(for: "K8XYZ", in: hunted, now: now)?.reference == "US-0002",
          "the call's newest spot gives the park")
    check(POTASpots.matchingPark(for: "K8XYZ/P", in: hunted, now: now)?.reference == "US-0002",
          "signing /P still matches")
    check(POTASpots.matchingPark(for: "N2OLD", in: hunted, now: now) == nil, "a spot over an hour old doesn't")
    check(POTASpots.matchingPark(for: "W9NOT", in: hunted, now: now) == nil, "a call not spotted gets no park")
    SpotList.shared.set(hunted, problem: nil)
    func leaveCallsign(_ call: String) {
        form.callsignField.stringValue = call
        form.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: form.callsignField))
    }
    leaveCallsign("W9NOT")
    leaveCallsign("K8XYZ")
    // No radio and no band: the first Return warns, the second logs.
    form.logContact(nil); form.logContact(nil)
    check(logbook.contacts.last?.call == "K8XYZ" && logbook.contacts.last?["pota_ref"] == "US-0002",
          "typed, not picked: logged with the park it's spotted at (\(logbook.contacts.last?["pota_ref"] ?? "nothing"))")
    leaveCallsign("K8XYZ")
    leaveCallsign("W9NOT")
    form.logContact(nil); form.logContact(nil)
    check(logbook.contacts.last?.call == "W9NOT" && logbook.contacts.last?["pota_ref"] == "",
          "changing the call takes the spotted park back out")

    // The Spots window's Refresh pace (RefreshPacer.swift).
    func run(for seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    var shows = 0
    let pacer = RefreshPacer(interval: nil) { shows += 1 }
    pacer.changed(); pacer.changed()
    check(shows == 2, "Live: each change is shown at once")
    shows = 0
    pacer.interval = 0.3
    pacer.changed(); pacer.changed(); pacer.changed()
    check(shows == 0, "every so often: changes wait")
    run(for: 0.5)
    check(shows == 1, "and are shown together at the next tick (\(shows))")
    run(for: 0.7)
    check(shows == 1, "nothing new: nothing shown again")
    pacer.changed()
    pacer.showNow()
    check(shows == 2, "your own change (a filter) is shown at once")
    run(for: 0.5)
    check(shows == 2, "and isn't shown twice at the tick")
    pacer.changed()
    pacer.interval = nil
    check(shows == 3, "back to Live: what was waiting is shown at once")
    check(RefreshPacer.choices.map(\.title) == ["Live", "Every 15 seconds", "Every 30 seconds", "Every 45 seconds", "Every minute"],
          "the choices: Live, 15, 30, 45 seconds, a minute")
    pacer.stop()
}
