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

let values = ["MYCALL": "N0CALL", "MYNAME": "the author", "MYSTATE": "MD", "NR": "42",
              "CALL": "K5ZZZ", "NAME": "Tom", "STATE": "TX", "SKCC": "26050T", "RST": "599"]
check(CWMessages.expand(CWMessages.defaults[0], values: values) == "CQ CQ N0CALL N0CALL K", "F1: CQ with your call")
check(CWMessages.expand(CWMessages.defaults[1], values: values) == "K5ZZZ 599 the author MD",
      "F2: their call, RST, your name and state")
check(CWMessages.expand("{CALL} 5NN {nr}", values: values) == "K5ZZZ 5NN 42", "{NR}: your serial number")
check(CWMessages.expand("TU {name} {Call}", values: values) == "TU Tom K5ZZZ", "fill-ins in any case")
check(CWMessages.expand("{CALL} {NAME} {MYNAME}", values: ["CALL": "W1AW"]) == "W1AW",
      "empty fill-ins are left out, with no extra spaces")
check(CWMessages.expand("{NOPE} AGN?", values: values) == "AGN?", "an unknown fill-in is left out")
check(CWMessages.expand("{CALL", values: values) == "{CALL", "an unclosed brace is kept as typed")
check(CWMessages.defaults.count == CWMessages.count, "eight starting messages")
check(CWMessages.fieldDay.count == CWMessages.count, "eight Field Day messages")
let fdValues = ["MYCALL": "N0CALL", "CALL": "W1AW", "SENT": "1D MDC"]
check(CWMessages.expand(CWMessages.fieldDay[0], values: fdValues) == "CQ FD N0CALL N0CALL FD", "Field Day CQ")
check(CWMessages.expand(CWMessages.fieldDay[1], values: fdValues) == "W1AW 1D MDC",
      "Field Day exchange: their call, then your class and section from {SENT}")

check(WinKeyer.sendable("cq de n0call/qrp, k") == "CQ DE N0CALL/QRP, K", "upper case, / and , kept")
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
let worked = [qso("W1AW", "20m", "CW"), qso("K5ZZZ", "40m", "SSB"), qso("N0FT", "20m", "FT8")]
check(fd.dupe(of: "W1AW", band: "20m", mode: "CW", in: worked) != nil, "band and mode: same band, same mode, a dupe")
check(fd.dupe(of: "W1AW", band: "20m", mode: "SSB", in: worked) == nil, "band and mode: CW then phone is new")
check(fd.dupe(of: "W1AW", band: "40m", mode: "CW", in: worked) == nil, "band and mode: another band is new")
check(fd.dupe(of: "K5ZZZ", band: "40m", mode: "USB", in: worked) != nil, "SSB and USB are both phone")
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
                              contestName: "ARRL Field Day", myCall: "N0CALL")
check(sheet.hasPrefix("ARRL Field Day dupe sheet, N0CALL\n5 contacts\n"), "headed with the contest and your call")
let blocks = sheet.components(separatedBy: "\n\n").dropFirst().map { $0.components(separatedBy: "\n").first ?? "" }
check(blocks == ["80m CW (1)", "40m Phone (1)", "20m CW (1)", "20m Digital (1)"],
      "by band, longest first, then CW, phone, digital; repeats counted once: \(blocks)")

// MARK: The Contests folder
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("contests-check-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: folder) }
var loaded = ContestList.load(from: folder)
check(loaded.contests.map(\.id) == ["ARRL-FIELD-DAY"] && loaded.problems.isEmpty
      && FileManager.default.fileExists(atPath: folder.appendingPathComponent("README.txt").path),
      "a new folder gets Field Day's file and a README")
try! Data("name: Broken\n".utf8).write(to: folder.appendingPathComponent("Broken.txt"))
try! Data("name: Field Day copy\nid: ARRL-FIELD-DAY\n".utf8).write(to: folder.appendingPathComponent("Copy.txt"))
try! Data(naqp.fileText.utf8).write(to: folder.appendingPathComponent("NAQP CW.txt"))
loaded = ContestList.load(from: folder)
check(Set(loaded.contests.map(\.id)) == ["ARRL-FIELD-DAY", "NAQP-CW"], "good files are used: \(loaded.contests.map(\.id))")
check(loaded.problems.count == 2 && loaded.problems.contains { $0.hasPrefix("Broken.txt") }
      && loaded.problems.contains { $0.contains("already has id") }, "bad files are named, with why: \(loaded.problems)")
print("All CW checks passed.")
