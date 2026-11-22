// Checks band plans (BandPlan.swift), the United States plan's
// privileges, and the out-of-band warning (BandWarning.swift), with a
// throwaway folder and a pretend radio. Nothing is tuned.
import AppKit

func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }

@MainActor func run() async {
    guard case .success(let us) = BandPlan.parse(BandPlan.unitedStates) else { return check(false, "the US plan reads") }
    check(us.classes == ["Extra", "Advanced", "General", "Technician", "Novice"] && us.segments.count == 50
          && us.activities.count == 60, "the US plan: five classes, its segments and activities")
    func modes(_ mhz: Double, _ who: String) -> [BandPlan.Mode] { us.modes(at: Int(mhz * 1_000_000), for: who) }
    check(modes(14.010, "Extra") == [.cw, .data] && modes(14.010, "General").isEmpty, "14.010: Extra's, not General's")
    check(modes(14.160, "Extra") == [.cw, .phone, .image] && modes(14.160, "Advanced").isEmpty
          && modes(14.200, "Advanced") == [.cw, .phone, .image] && modes(14.200, "General").isEmpty
          && modes(14.250, "General") == [.cw, .phone, .image], "20 meter phone: Extra 14.150, Advanced 14.175, General 14.225")
    check(modes(7.050, "Technician") == [.cw] && modes(7.050, "General") == [.cw, .data], "40 meters: Technicians CW only")
    check(modes(7.150, "General").isEmpty && modes(7.150, "Advanced") == [.cw, .phone, .image], "7.150: Advanced, not General")
    check(modes(28.400, "Technician") == [.cw, .phone] && modes(28.600, "Technician").isEmpty, "10 meters: Technicians to 28.500")
    check(modes(5.357, "General") == [.cw, .data, .phone] && modes(5.360, "Technician").isEmpty
          && modes(5.332, "Extra") == [.cw, .data, .phone] && modes(5.340, "Extra").isEmpty,
          "60 meters: the 15 kHz band and the channels, not between them")
    check(modes(1.900, "Technician").isEmpty && modes(10.120, "General") == [.cw, .data], "160 for General up, 30 for CW and data")
    check(modes(50.050, "Technician") == [.cw] && modes(146.52, "Technician") == [.cw, .data, .phone, .image]
          && modes(146.52, "Novice").isEmpty && modes(223.5, "Novice").count == 4, "VHF: CW only below 50.1; Novices on 222")

    // Verdicts and the warning's words.
    let extra = "Extra"
    func hz(_ mhz: Double) -> Int { Int((mhz * 1_000_000).rounded()) }
    check(us.verdict(at: hz(14.074), mode: .data, for: extra) == .allowed, "FT8 on 14.074: fine")
    check(us.verdict(at: hz(9.600), mode: .phone, for: extra) == .notNearABand, "a broadcast station: not a warning")
    if case .outsidePrivileges(let nearest) = us.verdict(at: hz(14.352), mode: .phone, for: extra) {
        check(nearest == "Nearest: 14.225 to 14.350", "just past 20 meters: outside, with the nearest (\(nearest))")
    } else { check(false, "just past 20 meters: outside") }
    if case .modeNotAllowed(.phone, let allowed, let whereAllowed) = us.verdict(at: hz(14.100), mode: .phone, for: extra) {
        check(allowed == [.cw, .data] && whereAllowed == "14.150 to 14.350", "phone at 14.100: where phone is (\(whereAllowed))")
    } else { check(false, "phone at 14.100 isn't allowed") }
    if case .outsidePrivileges = us.verdict(at: hz(14.010), mode: .cw, for: "General") {} else {
        check(false, "General at 14.010: outside")
    }
    check(BandPlan.mode(ofRadioMode: "PKTUSB") == .data && BandPlan.mode(ofRadioMode: "USB") == .phone
          && BandPlan.mode(ofRadioMode: "CWR") == .cw && BandPlan.mode(ofRadioMode: "XYZ") == nil, "radio modes as the plan's")
    check(us.line(for: us.segments.first { $0.low == hz(14.000) }!) == "14.000 to 14.025 MHz, 20 meters: CW and data. Extra only.",
          "a segment's line")
    check(us.line(for: us.activities.first { $0.hertz == hz(14.074) }!) == "14.074 MHz, 20 meters: FT8.", "an activity's line")
    check(us.whereYouAre(hz(14.074), licenseClass: extra) == "14.074 MHz: CW and data for Extra. FT8.", "where the radio is")
    check(BandPlan.megahertz(hz(7.0475)) == "7.0475" && BandPlan.megahertz(hz(5.3515)) == "5.3515"
          && BandPlan.megahertz(hz(146.52)) == "146.520", "frequencies, with as many decimals as needed")

    // Files: bad lines are refused with why; the folder gets the US plan once.
    for bad in ["name: X\nclasses: A\nsegment: 14-13 | CW | A\n", "name: X\nclasses: A\nsegment: 14.0-14.1 | voice | A\n",
                "name: X\nclasses: A\nsegment: 14.0-14.1 | CW | B\n", "classes: A\nsegment: 14.0-14.1 | CW | A\n",
                "name: X\nclasses: A\nwhatever: 1\n"] {
        if case .success = BandPlan.parse(bad) { check(false, "refused: \(bad)") }
    }
    check(true, "bad band plan lines are refused, with why")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bandplans-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    var loaded = BandPlanList.load(from: folder)
    check(loaded.plans.map(\.name) == ["United States (FCC)"] && loaded.problems.isEmpty
          && FileManager.default.fileExists(atPath: folder.appendingPathComponent("README.txt").path),
          "a new folder gets the US plan and a README")
    try! FileManager.default.removeItem(at: folder.appendingPathComponent("United States (FCC).txt"))
    try! Data("name: Testland\nclasses: Full\nsegment: 7.000-7.200 | all words | Full\n".utf8)
        .write(to: folder.appendingPathComponent("Testland.txt"))
    loaded = BandPlanList.load(from: folder)
    check(loaded.plans.isEmpty && loaded.problems.count == 1 && loaded.problems[0].hasPrefix("Testland.txt"),
          "a deleted US plan isn't put back; a bad file is named: \(loaded.problems)")
    check(BandPlanList.current(named: "United States (FCC)", in: loaded).name == "United States (FCC)",
          "with no plan that reads, the built-in US one is used")

    // The warning: a pretend radio, settled 0.1 s here.
    let warning = BandWarning.shared
    warning.use(us)
    warning.settle = 0.1
    var said: [String] = []
    warning.say = { said.append($0) }
    var reading = RadioReading(hertz: hz(14.074), mode: "PKTUSB")
    warning.reading = { reading }
    Settings.licenseClass = "Extra"
    Settings.bandWarning = true
    RadioReading.digitalMode = nil
    func wait() async { try? await Task.sleep(nanoseconds: 250_000_000) }
    warning.radioChanged(); await wait()
    check(said.isEmpty, "FT8 on 14.074 in a data mode: quiet")
    reading = RadioReading(hertz: hz(14.352), mode: "USB")
    // A real radio is read several times a second: each reading lands
    // here, and the wait mustn't start again each time.
    // Readings for 0.4 s, longer than the 0.1 s wait, and none after.
    for _ in 0..<10 { warning.radioChanged(); try? await Task.sleep(nanoseconds: 40_000_000) }
    check(said == ["Outside your Extra privileges: 14.352 MHz. Nearest: 14.225 to 14.350."], "past the edge: said once (\(said))")
    reading.hertz = hz(14.355)
    warning.radioChanged(); await wait()
    check(said.count == 1, "tuning further out: not said again")
    reading = RadioReading(hertz: hz(14.300), mode: "USB")
    warning.radioChanged(); await wait()
    reading = RadioReading(hertz: hz(14.100), mode: "USB")
    warning.radioChanged(); await wait()
    check(said.last == "Phone isn't allowed at 14.100 MHz for Extra; here it's CW and data. Phone: 14.150 to 14.350.",
          "phone in the data segment: said (\(said.last ?? ""))")
    RadioReading.digitalMode = ("FT8", "", Date())
    reading = RadioReading(hertz: hz(14.074), mode: "USB")
    said = []
    warning.radioChanged(); await wait()
    check(said.isEmpty, "USB on 14.074 while WSJT-X is working: data, so quiet")
    RadioReading.digitalMode = nil
    reading = RadioReading(hertz: hz(14.352), mode: "USB")
    warning.radioChanged()
    reading = RadioReading(hertz: hz(14.250), mode: "USB")
    warning.radioChanged(); await wait()
    check(said.isEmpty, "crossing out and back before it settles: quiet")
    Settings.licenseClass = ""
    reading = RadioReading(hertz: hz(14.352), mode: "USB")
    warning.radioChanged(); await wait()
    check(said.isEmpty, "no license class: no warnings")
    for key in ["bandPlan.class", "bandPlan.warn"] { UserDefaults.standard.removeObject(forKey: key) }
    print("All band plan checks passed.")
}

Task { @MainActor in await run(); exit(0) }
RunLoop.main.run()
