// tools/clubs-check/main.swift
//
// Checks club numbers (SKCCRoster.swift, ClubNumbers.swift, the club
// fields in LogField.swift), with no internet and nothing of yours:
//   - SKCC's file is read right: numbers with award letters, silent keys
//     and former members left out, repeated header lines skipped, junk
//     ignored, a call listed twice taking its newest number;
//   - a typed SKCC number is checked against the call, with whose it is;
//   - club numbers come from the newest contact with the same call, and
//     SKCC's list wins for SKCC;
//   - your club fields are hidden until named, and take your name.
// Give it SKCC's real file to read that too:
//   bash tools/check-clubs.sh [path to skccdata.txt]

import AppKit

func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }

// Settings of the check's own (it isn't Solid Copy, so not yours).
UserDefaults.standard.set(true, forKey: "skccLookup")
UserDefaults.standard.removeObject(forKey: "clubNames")

MainActor.assumeIsolated {
    // MARK: SKCC's file
    let sample = """
    SKCCNR|CALL|NAME|QTH|SPC|OLDCALL|SKCC|DXCODE|JOINDATE|CENTDATE|TRIBDATE|TX8DATE|SENDATE|DXENTITY
    1|KC9ECI|Tom|Galesville|WI|M0KCE|1|291|02 Jan 2006|||||USA
    2C|KI4CIA|Melinda|Fayette|AL||2|291|02 Jan 2006|15 Jan 2007||||USA
    3S|N6WK/SK|Gordon|Santa Ana|CA|N6WK|3|291|02 Jan 2006|19 Oct 2006|09 Sep 2007|14 Feb 2013|02 Nov 2013|USA
    170|call|name|qth|spc|oldcall|skcc|||||||
    12345T|W1ABC|Ann|Hartford|CT||12345|291|01 Jan 2010|||||USA
    20000|K1XYZ/EX|Bob|Boston|MA||20000|291|01 Jan 2012|||||USA
    20500|K2OLD|Cy|Albany|NY||20500|291|01 Jan 2013|||||USA
    30000|K2OLD|Cy|Albany|NY||30000|291|01 Jan 2020|||||USA
    31000|N3ABC/W3ZZZ|Di|Erie|PA||31000|291|01 Jan 2024|||||USA
    garbage line
    99x|W9BAD|Bad|Nowhere|XX||99|291||||||USA
    """
    let roster = SKCCRoster.shared
    roster.use(sample)
    check(roster.number(for: "W1ABC") == "12345T", "a member's number keeps its award letter")
    check(roster.number(for: "w1abc/p") == "12345T", "W1ABC/P is looked up as W1ABC")
    check(roster.number(for: "KI4CIA") == "2C", "Centurion letter kept")
    check(roster.number(for: "N6WK") == nil, "silent keys (/SK) are left out")
    check(roster.number(for: "K1XYZ") == nil, "former members (/EX) are left out")
    check(roster.number(for: "CALL") == nil, "repeated header lines are skipped")
    check(roster.number(for: "W9BAD") == nil, "a number that isn't one is skipped")
    check(roster.number(for: "K2OLD") == "30000", "a call listed twice takes its newest number")
    check(roster.number(for: "N3ABC") == "31000", "an extra /part is dropped from the call")
    check(roster.call(forNumber: "12345") == "W1ABC" && roster.call(forNumber: "012345t") == "W1ABC",
          "numbers are found with or without the letter or leading zeros")
    check(roster.members.count == 5, "five members read from the sample (\(roster.members.count))")

    // MARK: Numbers
    check(SKCCRoster.digits("12345T") == "12345" && SKCCRoster.digits(" 7 ") == "7", "digits without the letter")
    check(SKCCRoster.digits("12A45") == nil && SKCCRoster.digits("") == nil && SKCCRoster.digits("T") == nil,
          "not numbers are refused")
    check(SKCCRoster.spoken("12345T") == "12345 Tribune" && SKCCRoster.spoken("2C") == "2 Centurion"
          && SKCCRoster.spoken("3S") == "3 Senator" && SKCCRoster.spoken("1") == "1", "award letters said in words")

    // MARK: Checking a typed number
    check(roster.problem(withNumber: "12345", for: "W1ABC") == nil, "the right number, no letter: fine")
    check(roster.problem(withNumber: "12345t", for: "W1ABC") == nil, "the right number with its letter: fine")
    check(roster.problem(withNumber: "", for: "W1ABC") == nil, "nothing typed: nothing said")
    check(roster.problem(withNumber: "30000", for: "W1ABC") == "SKCC 30000 is K2OLD. W1ABC is SKCC 12345T.",
          "someone else's number: says whose, and the call's own")
    check(roster.problem(withNumber: "77777", for: "W1ABC") == "No SKCC member has number 77777. W1ABC is SKCC 12345T.",
          "a number nobody has")
    check(roster.problem(withNumber: "12345", for: "W1ABD") == "SKCC 12345 is W1ABC. W1ABD isn't in SKCC's list.",
          "a miscopied call: the number says whose it really is")
    check(roster.problem(withNumber: "1x2", for: "W1ABC") == "SKCC number 1X2 isn't a number."
          || roster.problem(withNumber: "1x2", for: "W1ABC") == "SKCC number 1x2 isn't a number.",
          "a typed number that isn't one")
    check(roster.problem(withNumber: "30000", for: "W1ABC", callText: { "<\($0)>" })
          == "SKCC 30000 is <K2OLD>. <W1ABC> is SKCC 12345T.", "calls can be spelled out for speech")
    UserDefaults.standard.set(false, forKey: "skccLookup")
    check(roster.number(for: "W1ABC") == nil && roster.problem(withNumber: "30000", for: "W1ABC") == nil,
          "with SKCC's list off, nothing is filled or checked")
    UserDefaults.standard.set(true, forKey: "skccLookup")

    // MARK: Numbers from your log
    func contact(_ call: String, _ time: String, _ fields: [String: String]) -> QSO {
        QSO(id: UUID(), call: call, timeOn: QSO.date(adifDate: "20260101", adifTime: time)!, storedFields: fields)
    }
    let log = [
        contact("K3FST", "100000", ["fists": "1111", "app_solidcopy_licw": "50"]),
        contact("K3FST/P", "110000", ["fists": "2222"]),
        contact("K3FST", "120000", ["name": "Ed"]),
        contact("W1ABC", "130000", ["skcc": "12345C"]),
    ]
    let k3 = ClubNumbers.numbers(for: "K3FST", in: log)
    check(k3["fists"] == "2222", "the newest number wins, and K3FST/P counts as K3FST")
    check(k3["app_solidcopy_licw"] == "50", "an older contact fills what newer ones lack")
    check(k3["name"] == nil, "only club numbers are filled, not other fields")
    check(ClubNumbers.numbers(for: "W1ABC", in: log)["skcc"] == "12345T",
          "SKCC's list wins over the log (a newer award letter)")
    check(ClubNumbers.numbers(for: "K2OLD", in: [])["skcc"] == "30000", "SKCC from the list with no contacts")
    check(ClubNumbers.numbers(for: "N0NE", in: log).isEmpty, "a new call: nothing")
    check(ClubNumbers.shown(k3) == "FISTS 2222, LICW 50", "shown in the field list's order")
    check(ClubNumbers.spoken(["skcc": "12345T"]) == "SKCC 12345 Tribune", "SKCC said with its award")

    // MARK: Your club fields
    let slot = LogField.named("app_solidcopy_club1")!
    check(slot.isUnnamedClubField && !slot.canGoOnForm && slot.label == "Club field 1",
          "an unnamed club field is hidden from the form")
    ClubNames.setName("  NAQCC number  ", for: 1)
    let named = LogField.named("app_solidcopy_club1")!
    check(!named.isUnnamedClubField && named.canGoOnForm && named.label == "NAQCC number",
          "a named club field takes your name and can go on the form")
    check(ClubNumbers.shortName("app_solidcopy_club1") == "NAQCC", "its short name drops \"number\"")
    let naqcc = ClubNumbers.numbers(for: "K3FST", in: [contact("K3FST", "100000", ["app_solidcopy_club1": "4321"])])
    check(naqcc["app_solidcopy_club1"] == "4321", "your club fields fill from the log too")
    ClubNames.setName("", for: 1)
    check(LogField.named("app_solidcopy_club1")!.isUnnamedClubField, "clearing the name hides it again")
    ClubNames.setName("X", for: 0)
    ClubNames.setName("X", for: LogField.clubSlots + 1)
    check((UserDefaults.standard.stringArray(forKey: "clubNames") ?? []).count == LogField.clubSlots,
          "names for slots that don't exist are ignored")
    check(LogField.all.filter { $0.clubSlot != nil }.count == LogField.clubSlots
          && LogField.clubNumberFields.allSatisfy { LogField.named($0) != nil }, "every club field is in the list")

    // MARK: SKCC's real file, if given
    if CommandLine.arguments.count > 1 {
        let path = CommandLine.arguments[1]
        let start = Date()
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { check(false, "read \(path)"); return }
        roster.use(text)
        let seconds = Date().timeIntervalSince(start)
        check(roster.members.count > 30_000, "real file: \(roster.members.count) members")
        check(roster.number(for: "KC9ECI") == "1", "real file: member 1 is KC9ECI")
        check(roster.number(for: "N6WK") == nil, "real file: silent keys left out")
        check(seconds < 2, "real file read in \(String(format: "%.2f", seconds)) seconds")
    }
    UserDefaults.standard.removeObject(forKey: "clubNames")
    UserDefaults.standard.removeObject(forKey: "skccLookup")
    // Member lists from files (ClubLists.swift): the CSV is read as call and number,
// a header and blank lines are skipped, quotes and extra columns ignored,
// and a portable call matches its main part. (Saving a list writes into
// Solid Copy's Application Support folder, so only the reading is checked here.)
let listed = ClubLists.parse("""
call,number
"w1aw",12345
K1ABC, 678 , note
W1AW/P,99999

not a line
""")
check(listed["W1AW"] == "99999", "club list: a portable call is kept under its main call, later line wins")
check(listed["K1ABC"] == "678", "club list: quotes, spaces and extra columns are ignored")
check(listed.count == 2 && listed["CALL"] == nil, "club list: the header and junk lines are skipped")
check(ClubLists.parse("nothing here").isEmpty, "club list: text with no members gives none")

// A club field named for a club Solid Copy has built in is refused.
check(ClubNames.builtInField(for: "LICW #696") == "LICW number" && ClubNames.builtInField(for: "FISTS #5030") == "FISTS number"
      && ClubNames.builtInField(for: "cwops") == "CWops number" && ClubNames.builtInField(for: "SKCC") == "SKCC number",
      "built-in clubs are recognised, numbers and case aside")
check(ClubNames.builtInField(for: "NAQCC number") == nil && ClubNames.builtInField(for: "QCWA") == nil
      && ClubNames.builtInField(for: "Skccers fan club") == nil, "other clubs are club fields (whole words only)")

print("All club checks passed.")
}
