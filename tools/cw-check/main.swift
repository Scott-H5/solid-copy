// tools/cw-check/main.swift
//
// Checks CW messages and what's sent to the WinKeyer, with no keyer
// plugged in (nothing is sent anywhere):
//   - fill-ins are filled, any case; empty or unknown ones are left out;
//   - the starting messages give the SKCC Sprint exchange;
//   - only characters CW can carry are sent, upper case, single spaces;
//   - speeds stay within the WinKeyer's 5 to 99.
//
// Run it with:  bash tools/check-cw.sh

import AppKit

func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }

let values = ["MYCALL": "N3BYY", "MYNAME": "Scott", "MYSTATE": "MD", "NR": "42",
              "CALL": "K5AX", "NAME": "Tom", "STATE": "TX", "SKCC": "26050T", "RST": "599"]
check(CWMessages.expand(CWMessages.defaults[0], values: values) == "CQ CQ N3BYY N3BYY K", "F1: CQ with your call")
check(CWMessages.expand(CWMessages.defaults[1], values: values) == "K5AX 599 Scott MD",
      "F2: their call, RST, your name and state")
check(CWMessages.expand("{CALL} 5NN {nr}", values: values) == "K5AX 5NN 42", "{NR}: your serial number")
check(CWMessages.expand("TU {name} {Call}", values: values) == "TU Tom K5AX", "fill-ins in any case")
check(CWMessages.expand("{CALL} {NAME} {MYNAME}", values: ["CALL": "W1AW"]) == "W1AW",
      "empty fill-ins are left out, with no extra spaces")
check(CWMessages.expand("{NOPE} AGN?", values: values) == "AGN?", "an unknown fill-in is left out")
check(CWMessages.expand("{CALL", values: values) == "{CALL", "an unclosed brace is kept as typed")
check(CWMessages.defaults.count == CWMessages.count, "eight starting messages")
check(CWMessages.fieldDay.count == CWMessages.count, "eight Field Day messages")
let fdValues = ["MYCALL": "N3BYY", "CALL": "W1AW", "SENT": "1D MDC"]
check(CWMessages.expand(CWMessages.fieldDay[0], values: fdValues) == "CQ FD N3BYY N3BYY FD", "Field Day CQ")
check(CWMessages.expand(CWMessages.fieldDay[1], values: fdValues) == "W1AW 1D MDC",
      "Field Day exchange: their call, then your class and section from {SENT}")

check(WinKeyer.sendable("cq de n3byy/qrp, k") == "CQ DE N3BYY/QRP, K", "upper case, / and , kept")
check(WinKeyer.sendable("Tom's  rig: 100w!") == "TOMS RIG 100W", "characters CW can't carry are left out")
check(WinKeyer.sendable("  ") == "", "only spaces: nothing to send")
check(WinKeyer.clamp(2) == 5 && WinKeyer.clamp(150) == 99 && WinKeyer.clamp(25) == 25, "speeds kept to 5 to 99")
// Serial numbers (Contest.nextSerial): per contest, after the highest.
func logged(_ contest: String, _ stx: String) -> QSO {
    var qso = QSO(call: "W1AW", timeOn: Date()); qso["contest_id"] = contest; qso["stx"] = stx; return qso
}
check(Contest.nextSerial(in: [], contest: "CQ-WW-CW") == 1, "the first serial is 1")
let serials = [logged("CQ-WW-CW", "1"), logged("CQ-WW-CW", "2"), logged("CQ-WW-CW", "5"), logged("NAQP-CW", "40"),
               logged("cq-ww-cw ", "x"), logged("", "7")]
check(Contest.nextSerial(in: serials, contest: "cq-ww-cw") == 6, "after the highest logged, any case, gaps kept")
check(Contest.nextSerial(in: serials, contest: "NAQP-CW") == 41, "each contest counts on its own")
check(Contest.nextSerial(in: serials, contest: "") == 8, "contacts with no contest count together")

// MARK: Contest files
let known = Set(LogField.all.map(\.adif))
guard case .success(let fd) = Contest.parse(Contest.fieldDayFile, knownFields: known) else {
    check(false, "Field Day's file reads"); exit(1)
}
check(fd.id == "ARRL-FIELD-DAY" && fd.name == "ARRL Field Day" && fd.exchange == ["srx_string"] && !fd.serial
      && fd.dupes == .bandAndMode && fd.messages.count == 8 && fd.submit == .dupeSheet, "Field Day's file reads right")
guard case .success(let plain) = Contest.parse("name: Test Party\nid: test-party", knownFields: known) else {
    check(false, "a two-line file reads"); exit(1)
}
check(plain.id == "TEST-PARTY" && plain.exchange == ["srx_string"] && plain.dupes == .bandAndMode && !plain.serial
      && plain.messages.isEmpty && plain.submit == .none, "only name and id needed; the rest has defaults")
guard case .success(let naqp) = Contest.parse("""
    # comment line
    name: NAQP CW   # a comment after
    id: NAQP-CW
    exchange: name, state, srx
    serial: yes
    dupes: band
    """, knownFields: known) else { check(false, "NAQP reads"); exit(1) }
check(naqp.exchange == ["name", "state", "srx"] && naqp.serial && naqp.dupes == .band,
      "exchange words and ADIF names, serial, dupe rule, comments")
func problem(_ text: String) -> String? {
    if case .failure(let error) = Contest.parse(text, knownFields: known) { return error.message } else { return nil }
}
check(problem("id: X")?.contains("name") == true, "no name: said")
check(problem("name: X")?.contains("id") == true && problem("name: X\nid: has space")?.contains("id") == true,
      "no id, or a bad one: said")
check(problem("name: X\nid: X\nexchange: shoe size")?.contains("shoe size") == true, "an unknown exchange word: named")
check(problem("name: X\nid: X\nserial: maybe") != nil && problem("name: X\nid: X\ndupes: weekly") != nil
      && problem("name: X\nid: X\nsubmit: fax") != nil && problem("name: X\nid: X\njust words") != nil,
      "bad values and lines without a colon: said")
if case .success(let back) = Contest.parse(naqp.fileText, knownFields: known) {
    check(back == naqp, "a contest written out (Save Profile as Contest) reads back the same")
} else { check(false, "written file reads back") }

// MARK: Dupe rules
func qso(_ call: String, _ band: String, _ mode: String) -> QSO {
    var q = QSO(call: call, timeOn: Date()); q["band"] = band; q["mode"] = mode; return q
}
let worked = [qso("W1AW", "20m", "CW"), qso("K5AX", "40m", "SSB"), qso("N0FT", "20m", "FT8")]
check(fd.dupe(of: "W1AW", band: "20m", mode: "CW", in: worked) != nil, "band and mode: same band, same mode, a dupe")
check(fd.dupe(of: "W1AW", band: "20m", mode: "SSB", in: worked) == nil, "band and mode: CW then phone is new")
check(fd.dupe(of: "W1AW", band: "40m", mode: "CW", in: worked) == nil, "band and mode: another band is new")
check(fd.dupe(of: "K5AX", band: "40m", mode: "USB", in: worked) != nil, "SSB and USB are both phone")
check(fd.dupe(of: "N0FT", band: "20m", mode: "RTTY", in: worked) != nil, "FT8 and RTTY are both digital")
check(fd.dupe(of: "W1AW", band: "20m", mode: "", in: worked) == nil,
      "band and mode: an unknown mode is never a dupe (a TS-590SG data mode warned of CW)")
check(fd.dupe(of: "N0FT", band: "20m", mode: "DATA", in: worked) != nil
      && fd.dupe(of: "W1AW", band: "20m", mode: "DATA", in: worked) == nil, "the radio's data modes count as digital")
var once = fd; once.dupes = .once
var perBand = fd; perBand.dupes = .band
check(once.dupe(of: "W1AW", band: "80m", mode: "SSB", in: worked) != nil, "once: any band, any mode")
check(perBand.dupe(of: "W1AW", band: "20m", mode: "SSB", in: worked) != nil
      && perBand.dupe(of: "W1AW", band: "15m", mode: "CW", in: worked) == nil, "band: any mode on the same band")

// MARK: Dupe sheet
let sheet = Contest.dupeSheet(worked + [qso("W1AW", "20m", "CW"), qso("AA1A", "80m", "CW")],
                              contestName: "ARRL Field Day", myCall: "N3BYY")
check(sheet.hasPrefix("ARRL Field Day dupe sheet, N3BYY\n5 contacts\n"), "headed with the contest and your call")
let blocks = sheet.components(separatedBy: "\n\n").dropFirst().map { $0.components(separatedBy: "\n").first ?? "" }
check(blocks == ["80m CW (1)", "40m Phone (1)", "20m CW (1)", "20m Digital (1)"],
      "by band, longest first, then CW, phone, digital; repeats counted once: \(blocks)")

// MARK: The Contests folder
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("contests-check-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: folder) }
var loaded = ContestList.load(from: folder)
check(loaded.contests.map(\.id).sorted() == ["ARRL-FIELD-DAY", "SKCC-QSO-PARTY", "SKCC-SAUNTER", "SKCC-SKS",
                                               "SKCC-SKSA", "SKCC-SKSE", "SKCC-WES"] && loaded.problems.isEmpty
      && FileManager.default.fileExists(atPath: folder.appendingPathComponent("README.txt").path),
      "a new folder gets Field Day's and SKCC's files and a README: \(loaded.problems)")
try! Data("name: Broken\n".utf8).write(to: folder.appendingPathComponent("Broken.txt"))
try! Data("name: Field Day copy\nid: ARRL-FIELD-DAY\n".utf8).write(to: folder.appendingPathComponent("Copy.txt"))
try! Data(naqp.fileText.utf8).write(to: folder.appendingPathComponent("NAQP CW.txt"))
loaded = ContestList.load(from: folder)
let starting = Set(Contest.startingFiles.map { $0.file.replacingOccurrences(of: ".txt", with: "") })
check(Set(loaded.contests.map(\.name)).isSuperset(of: ["ARRL Field Day", "NAQP CW", "SKCC Sprint"])
      && loaded.contests.count == starting.count + 1, "good files are used: \(loaded.contests.map(\.id))")
check(loaded.problems.count == 2 && loaded.problems.contains { $0.hasPrefix("Broken.txt") }
      && loaded.problems.contains { $0.contains("already has id") }, "bad files are named, with why: \(loaded.problems)")

// MARK: Scoring (v1.6 item 2)
// A folder from before 1.6 (Field Day only, one SKCC file deleted by
// hand later): the SKCC files are added once, and not again.
let older = FileManager.default.temporaryDirectory.appendingPathComponent("contests-old-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: older) }
try! FileManager.default.createDirectory(at: older, withIntermediateDirectories: true)
try! Data("name: My Field Day\nid: ARRL-FIELD-DAY\n".utf8).write(to: older.appendingPathComponent("ARRL Field Day.txt"))
var olderLoaded = ContestList.load(from: older)
check(olderLoaded.contests.count == 7 && olderLoaded.contests.contains { $0.name == "My Field Day" },
      "an older folder gets the SKCC files, and its own Field Day is kept: \(olderLoaded.contests.map(\.name))")
try! FileManager.default.removeItem(at: older.appendingPathComponent("SKCC Asia Sprint.txt"))
olderLoaded = ContestList.load(from: older)
check(olderLoaded.contests.count == 6, "a file you deleted isn't put back")

guard let sks = olderLoaded.contests.first(where: { $0.id == "SKCC-SKS" }),
      let qp = olderLoaded.contests.first(where: { $0.id == "SKCC-QSO-PARTY" }),
      let saunter = olderLoaded.contests.first(where: { $0.id == "SKCC-SAUNTER" }) else { fatalError("SKCC files") }
check(sks.exchange == ["rst_sent", "rst_rcvd", "state", "name", "skcc"] && sks.dupes == .band && sks.messages.isEmpty,
      "SKS: RST both ways, SPC, name, SKCC; once per band; no keyer messages (straight key)")
check(Contest.parse(sks.fileText, knownFields: Set(LogField.all.map(\.adif))) == .success(sks),
      "a scoring file written out reads back the same")
func entry(_ call: String, _ band: String, _ spc: String, _ skcc: String, minute: Double,
           grid: String = "", name: String = "") -> QSO {
    var q = QSO(call: call, timeOn: Date(timeIntervalSince1970: 1_800_000_000 + minute * 60))
    q["band"] = band; q["mode"] = "CW"; q["state"] = spc; q["skcc"] = skcc; q["gridsquare"] = grid; q["name"] = name
    return q
}
let sprint = [entry("W1AAA", "40m", "MA", "1234T", minute: 1), entry("W1AAA", "20m", "MA", "1234T", minute: 2),
              entry("W1AAA", "40m", "MA", "1234T", minute: 3),   // a dupe
              entry("K4BBB", "40m", "va", "22C", minute: 4), entry("VE3CCC", "40m", "ON", "333S", minute: 5),
              entry("N5DDD", "40m", "TX", "NONE", minute: 6), entry("NX1K", "40m", "CT", "4444S", minute: 7),
              entry("NX1K/4", "20m", "CT", "4444S", minute: 8)]
let sprintScore = sks.score(sprint)
// 7 contacts x 5 SPCs (MA VA ON TX CT) = 35; C 5 + T 10 + S 15 x2 = 45; NX1K on 2 bands = 50.
check(sprintScore.contacts == 7 && sprintScore.dupes == 1 && sprintScore.multipliers == 5,
      "contacts once per band, the dupe left out, SPCs once each (any case)")
check(sprintScore.members == ["C": 1, "T": 1, "S": 2] && sprintScore.memberPoints == 45,
      "C, T and S once per station, whatever the bands: \(sprintScore.members)")
check(sprintScore.bonusStations == ["NX1K": 2] && sprintScore.bonusStationPoints == 50, "the special station, per band, /4 too")
check(sprintScore.total == 35 + 45 + 50, "score: contacts times SPCs, plus the bonuses (\(sprintScore.total))")
let said = sks.scoreLines(sprintScore)
check(said == ["7 contacts (1 dupe not counted)", "5 multipliers", "1 Centurion, 5 points", "1 Tribune, 10 points",
               "2 Senators, 30 points", "NX1K: 2 bands, 50 points", "Score 130"], "said as SKCC's form asks: \(said)")
let party = [entry("W1AAA", "40m", "MA", "1234T", minute: 1, grid: "FN42ab"), entry("K4BBB", "40m", "VA", "22", minute: 2, grid: "fn42"),
             entry("KS1KCC", "80m", "MA", "1C", minute: 3, grid: "FN32")]
let partyScore = qp.score(party)
check(partyScore.grids == 2 && partyScore.gridPoints == 10 && partyScore.total == 3 * 2 + 10 + 5 + 10 + 25,
      "QSO Party: different 4-character grids, 5 each, with KS1KCC (\(partyScore.total))")
let asia = Contest.parse("name: A\nid: A\nname bonus: /BD 30\nmultipliers: spc\n", knownFields: [])
if case .success(let sksa) = asia {
    let s = sksa.score([entry("JA1AAA", "40m", "JPN", "", minute: 1, name: "hiro/bd"), entry("JA1AAA", "20m", "JPN", "", minute: 2, name: "HIRO/BD")])
    check(s.named == 1 && s.total == 2 * 1 + 30, "a /BD station once, 30 points")
} else { check(false, "name bonus reads") }
check(saunter.scoreLines(saunter.score(sprint)) == ["7 contacts (1 dupe not counted)"], "the Saunter: just a count")
check(Contest.skccLetter("12345Tx2") == "T" && Contest.skccLetter("NONE") == nil && Contest.skccLetter("12345") == nil,
      "the SKCC letter: Tx2 is T, NONE and plain numbers have none")
for bad in ["skcc bonus: X 5", "bonus station: KS1KCC lots", "points: many", "multipliers: shoe size"] {
    if case .success = Contest.parse("name: B\nid: B\n\(bad)\n", knownFields: []) { check(false, "refused: \(bad)") }
}
check(true, "bad scoring lines are refused, with why")
print("All CW checks passed.")
