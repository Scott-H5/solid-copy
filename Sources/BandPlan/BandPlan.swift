// BandPlan.swift
//
// Band plans (v1.6 items 5 and 6): which frequencies each license class
// may use, and for what (CW, data, phone, image), plus well-known
// activity frequencies (FT8, calling frequencies, beacons). Window > Band
// Plan (Command-6) shows one as a table; the out-of-band warning
// (BandWarning.swift) checks the radio against it.
//
// Like contests, band plans are plain text files, in Solid Copy's Band
// Plans folder (Settings > Band Plan > Show Band Plan Files), so another
// country's plan, or a change in the rules, needs no new version of Solid
// Copy. The United States plan is written there the first time, from
// 47 CFR 97.301, 97.303(h) and 97.305 as amended 14 January 2026 (read
// 22 November 2026 at law.cornell.edu): the 60 meter band is now
// 5351.5-5366.5 kHz plus four channels.
//
// A file, one setting per line, "#" starts a comment:
//   name: United States (FCC)
//   classes: Extra, Advanced, General, Technician, Novice
//   segment: 14.000-14.025 | CW, data | Extra | a note, if any
//   activity: 14.074 | data | FT8
//   usual: 1.800-1.843 | CW       where a mode is the custom, though
//                                 others are allowed (160 meters)
// Frequencies are in MHz. Modes are CW, data, phone and image. A segment
// lists the classes that may use it for those modes; the same range can
// appear again for other classes with other modes (Technicians on 40
// meters: CW only). "all" means every class. An activity is a frequency
// where something usually happens; it gives no privileges.
//
// Foundation (and CryptoKit, for the files' SHA-256) only, so
// tools/check-bandplan.sh can check all of it.

import Foundation
import CryptoKit

struct BandPlan: Equatable {
    enum Mode: String, CaseIterable, Equatable {
        case cw = "CW", data, phone, image

        var title: String { self == .cw ? "CW" : rawValue.capitalized }
    }

    struct Segment: Equatable {
        var low: Int            // hertz
        var high: Int
        var modes: [Mode]
        var classes: [String]
        var note: String

        func contains(_ hertz: Int) -> Bool { hertz >= low && hertz <= high }
    }

    struct Activity: Equatable {
        var hertz: Int
        var mode: Mode?
        var what: String
    }

    var name: String
    var classes: [String]
    var segments: [Segment] = []
    var activities: [Activity] = []
    // Ranges where one mode is the custom (usual: lines).
    var usual: [(low: Int, high: Int, mode: Mode)] = []

    static func == (a: BandPlan, b: BandPlan) -> Bool {
        a.name == b.name && a.classes == b.classes && a.segments == b.segments && a.activities == b.activities
            && a.usual.map(\.low) == b.usual.map(\.low) && a.usual.map(\.high) == b.usual.map(\.high)
            && a.usual.map(\.mode) == b.usual.map(\.mode)
    }

    // MARK: Reading a file

    static func parse(_ text: String) -> Result<BandPlan, BandPlanError> {
        var name = "", classes: [String] = []
        var segments: [Segment] = [], activities: [Activity] = []
        var usual: [(low: Int, high: Int, mode: Mode)] = []
        for (number, raw) in text.components(separatedBy: .newlines).enumerated() {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first
                .map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !line.isEmpty else { continue }
            guard let colon = line.firstIndex(of: ":") else {
                return .failure(.init("line \(number + 1) has no colon: \(line)"))
            }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            let parts = value.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            func problem(_ why: String) -> Result<BandPlan, BandPlanError> {
                .failure(.init("line \(number + 1): \(why)"))
            }
            switch key {
            case "name":
                name = String(value.prefix(60))
            case "classes":
                classes = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            case "segment":
                guard parts.count == 3 || parts.count == 4 else {
                    return problem("a segment is a range | modes | classes, and maybe | a note")
                }
                guard let range = Self.range(parts[0]) else {
                    return problem("\(parts[0]) isn't a range in MHz, like 14.000-14.025")
                }
                var modes: [Mode] = []
                for word in parts[1].split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
                    guard let mode = Mode(rawValue: word == "cw" ? "CW" : word) else {
                        return problem("mode \"\(word)\" isn't CW, data, phone or image")
                    }
                    if !modes.contains(mode) { modes.append(mode) }
                }
                let who = parts[2].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                let allowed = who.map { $0.lowercased() } == ["all"] ? classes : who
                guard !modes.isEmpty, !allowed.isEmpty else { return problem("a segment needs modes and classes") }
                for one in allowed where !classes.contains(one) {
                    return problem("class \"\(one)\" isn't in the classes: line (put that line first)")
                }
                segments.append(Segment(low: range.low, high: range.high, modes: modes, classes: allowed,
                                        note: parts.count == 4 ? String(parts[3].prefix(120)) : ""))
            case "activity":
                guard parts.count == 3, let hertz = Self.hertz(parts[0]) else {
                    return problem("an activity is a frequency in MHz | a mode or nothing | what")
                }
                let word = parts[1].lowercased()
                let mode = word.isEmpty ? nil : Mode(rawValue: word == "cw" ? "CW" : word)
                guard word.isEmpty || mode != nil else { return problem("mode \"\(word)\" isn't CW, data, phone or image") }
                activities.append(Activity(hertz: hertz, mode: mode, what: String(parts[2].prefix(120))))
            case "usual":
                let word = parts.count == 2 ? parts[1].lowercased() : ""
                guard parts.count == 2, let range = Self.range(parts[0]),
                      let mode = Mode(rawValue: word == "cw" ? "CW" : word) else {
                    return problem("a usual line is a range in MHz | a mode, like 1.800-1.843 | CW")
                }
                usual.append((range.low, range.high, mode))
            default:
                return problem("\(key) isn't a band plan setting (name, classes, segment, activity, usual)")
            }
            guard segments.count + activities.count < 2_000 else { return problem("too many lines for a band plan") }
        }
        guard !name.isEmpty else { return .failure(.init("it needs a name: line")) }
        guard !classes.isEmpty else { return .failure(.init("it needs a classes: line")) }
        guard !segments.isEmpty else { return .failure(.init("it has no segment: lines")) }
        return .success(BandPlan(name: name, classes: classes, segments: segments.sorted { ($0.low, $0.high) < ($1.low, $1.high) },
                                 activities: activities.sorted { $0.hertz < $1.hertz }, usual: usual))
    }

    // "14.074" MHz -> 14074000 hertz. Nil outside 8 kHz to 300 GHz.
    static func hertz(_ text: String) -> Int? {
        guard let megahertz = Double(text.trimmingCharacters(in: .whitespaces)),
              megahertz >= 0.008, megahertz <= 300_000 else { return nil }
        return Int((megahertz * 1_000_000).rounded())
    }

    static func range(_ text: String) -> (low: Int, high: Int)? {
        let ends = text.split(separator: "-").map(String.init)
        guard ends.count == 2, let low = hertz(ends[0]), let high = hertz(ends[1]), low < high else { return nil }
        return (low, high)
    }

    // MARK: Questions about a frequency

    // The modes a radio mode counts as: hamlib's names (CW, USB, PKTUSB…).
    static func mode(ofRadioMode radio: String) -> Mode? {
        let mode = radio.uppercased()
        if mode.hasPrefix("CW") { return .cw }
        if mode.hasPrefix("PKT") || mode.hasPrefix("RTTY") || mode.hasPrefix("FSK") || mode.contains("DATA")
            || mode.hasSuffix("-D") { return .data }
        if ["USB", "LSB", "AM", "FM", "WFM", "AMS", "SAM", "DSB"].contains(mode) { return .phone }
        return nil
    }

    // What a class may do at a frequency: every mode of every segment
    // there for it, in the plan's order (CW, data, phone, image).
    func modes(at hertz: Int, for licenseClass: String) -> [Mode] {
        let found = Set(segments.filter { $0.contains(hertz) && $0.classes.contains(licenseClass) }.flatMap(\.modes))
        return Mode.allCases.filter(found.contains)
    }

    enum Verdict: Equatable {
        case allowed
        case modeNotAllowed(Mode, allowed: [Mode], whereAllowed: String)
        case outsidePrivileges(String)   // what's nearby, in words
        case notNearABand                // general coverage: nothing to say
    }

    // Whether a class may be at a frequency in a mode (nil: mode unknown,
    // so only the frequency is checked).
    func verdict(at hertz: Int, mode: Mode?, for licenseClass: String) -> Verdict {
        let allowed = modes(at: hertz, for: licenseClass)
        if !allowed.isEmpty {
            guard let mode, !allowed.contains(mode) else { return .allowed }
            return .modeNotAllowed(mode, allowed: allowed, whereAllowed: nearest(mode, to: hertz, for: licenseClass))
        }
        // Outside your privileges: in a band (someone's segment), or just
        // past an edge; elsewhere it's listening, not a warning.
        let margin = hertz < 30_000_000 ? 50_000 : 500_000
        guard segments.contains(where: { hertz >= $0.low - margin && hertz <= $0.high + margin }) else { return .notNearABand }
        let yours = segments.filter { $0.classes.contains(licenseClass) }
        guard let closest = yours.min(by: { distance(hertz, $0) < distance(hertz, $1) }),
              distance(hertz, closest) < 2_000_000 else { return .outsidePrivileges("") }
        return .outsidePrivileges("Nearest: \(Self.spokenRange(closest.low, closest.high))")
    }

    private func distance(_ hertz: Int, _ segment: Segment) -> Int {
        hertz < segment.low ? segment.low - hertz : hertz > segment.high ? hertz - segment.high : 0
    }

    // Where in the same band a class may use a mode: "14.150 to 14.350".
    private func nearest(_ mode: Mode, to hertz: Int, for licenseClass: String) -> String {
        let band = Bands.name(forHertz: hertz)
        let places = segments.filter { $0.classes.contains(licenseClass) && $0.modes.contains(mode)
            && Bands.name(forHertz: $0.low) == band }
        // Touching segments read as one range.
        var merged: [(Int, Int)] = []
        for segment in places.sorted(by: { $0.low < $1.low }) {
            if let last = merged.last, segment.low <= last.1 { merged[merged.count - 1].1 = max(last.1, segment.high) }
            else { merged.append((segment.low, segment.high)) }
        }
        return merged.map { Self.spokenRange($0.0, $0.1) }.joined(separator: " and ")
    }

    // MARK: The usual mode

    // The mode a frequency typed in Callsign should get (hamlib's names:
    // CW, USB, LSB, FM, PKTUSB), or nil to leave the radio's as it is:
    //   - an activity within 1 kHz: its mode (FM if it's an FM one);
    //   - a usual: range: its mode;
    //   - HF and 6 meters: SSB where phone is allowed (any class), on the
    //     usual sideband; otherwise CW, or data if the radio's already in
    //     a data mode and data's allowed there;
    //   - above 6 meters (FM and SSB share the bands): left as it is.
    func usualMode(at hertz: Int, radioMode: String) -> String? {
        func radio(_ mode: Mode) -> String {
            switch mode {
            case .cw: return "CW"
            case .data: return "PKTUSB"
            case .phone, .image: return RadioEntry.sideband(at: hertz)
            }
        }
        if let activity = activities.filter({ abs($0.hertz - hertz) <= 1_000 && $0.mode != nil })
            .min(by: { abs($0.hertz - hertz) < abs($1.hertz - hertz) }), let mode = activity.mode {
            return activity.what.uppercased().contains("FM") ? "FM" : radio(mode)
        }
        if let custom = usual.first(where: { hertz >= $0.low && hertz <= $0.high }) { return radio(custom.mode) }
        guard hertz < 54_000_000 else { return nil }
        let modes = Set(segments.filter { $0.contains(hertz) }.flatMap(\.modes))
        guard !modes.isEmpty else { return nil }
        if modes.contains(.phone) { return radio(.phone) }
        if Self.mode(ofRadioMode: radioMode) == .data, modes.contains(.data) { return nil }
        if modes.contains(.cw) { return "CW" }
        return modes.contains(.data) ? "PKTUSB" : nil
    }

    // MARK: Words

    // "14.074", "7.0475", "5.3515", "146.52": MHz with 3 decimals or more
    // as needed.
    static func megahertz(_ hertz: Int) -> String {
        var text = String(format: "%.4f", Double(hertz) / 1_000_000)
        while text.hasSuffix("0"), let dot = text.firstIndex(of: "."), text.distance(from: dot, to: text.endIndex) > 4 {
            text.removeLast()
        }
        return text
    }

    static func spokenRange(_ low: Int, _ high: Int) -> String { "\(megahertz(low)) to \(megahertz(high))" }

    // "CW and data", "CW, phone and image".
    static func spoken(_ modes: [Mode]) -> String {
        let words = modes.map { $0 == .cw ? "CW" : $0.rawValue }
        guard words.count > 1 else { return words.first ?? "" }
        return words.dropLast().joined(separator: ", ") + " and " + words.last!
    }

    static func spoken(classes: [String], of all: [String]) -> String {
        if classes.count == all.count, Set(classes) == Set(all) { return "all classes" }
        let ordered = all.filter(classes.contains)
        guard ordered.count > 1 else { return (ordered.first ?? "") + " only" }
        return ordered.dropLast().joined(separator: ", ") + " and " + ordered.last!
    }

    // A table row for a segment: "14.000 to 14.025 MHz, 20 meters: CW and
    // data. Extra only."
    func line(for segment: Segment) -> String {
        let band = Bands.name(forHertz: segment.low).map { ", " + Bands.spoken($0) } ?? ""
        let note = segment.note.isEmpty ? "" : " " + segment.note + (segment.note.hasSuffix(".") ? "" : ".")
        return "\(Self.spokenRange(segment.low, segment.high)) MHz\(band): \(Self.spoken(segment.modes)). "
            + "\(Self.spoken(classes: segment.classes, of: classes)).\(note)"
    }

    func line(for activity: Activity) -> String {
        let band = Bands.name(forHertz: activity.hertz).map { ", " + Bands.spoken($0) } ?? ""
        return "\(Self.megahertz(activity.hertz)) MHz\(band): \(activity.what)."
    }

    // Where the radio is, in a sentence: what your class may do there, and
    // any activity within 2 kHz.
    func whereYouAre(_ hertz: Int, licenseClass: String) -> String {
        let here = "\(Self.megahertz(hertz)) MHz"
        var text: String
        if licenseClass.isEmpty {
            let any = segments.filter { $0.contains(hertz) }
            text = any.isEmpty ? "\(here): not in a band in this plan."
                : "\(here): " + any.map { "\(Self.spoken($0.modes)), \(Self.spoken(classes: $0.classes, of: classes))" }
                    .joined(separator: "; ") + "."
        } else {
            let modes = self.modes(at: hertz, for: licenseClass)
            text = modes.isEmpty ? "\(here): outside your \(licenseClass) privileges."
                : "\(here): \(Self.spoken(modes)) for \(licenseClass)."
        }
        if let near = activities.first(where: { abs($0.hertz - hertz) <= 2_000 }) { text += " \(near.what)." }
        return text
    }
}

struct BandPlanError: Error, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
}

// MARK: - The Band Plans folder

enum BandPlanList {
    struct Loaded {
        var plans: [BandPlan]
        var problems: [String]
    }

    static func folder(in base: URL) -> URL { base.appendingPathComponent("Band Plans", isDirectory: true) }

    // Solid Copy's own files. Each is written once; when a new version of
    // Solid Copy has a newer one, it replaces the old only if you haven't
    // changed it (its SHA-256 still matches what was written), and a file
    // you deleted stays deleted. ".written" lists each file given and the
    // SHA-256 of the version given.
    static let startingFiles: [(file: String, text: String)] = [("United States (FCC).txt", BandPlan.unitedStates)]
    static let writtenList = ".written"
    // What 1.6 wrote, before ".written" kept a SHA-256 (its list has the
    // name only).
    static let earlierVersions: [String: String] = [
        "United States (FCC).txt": "0b57d4c9b8fbffe6d74734f433b0a13281e9e3be9b1f9bb2cf352e4e5bd41c91",
    ]
    // The checks stand in their own earlier version here.
    nonisolated(unsafe) static var earlierVersionsForChecks: [String: String]?

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func load(from folder: URL) -> Loaded {
        let files = FileManager.default
        let isNew = !files.fileExists(atPath: folder.path)
        if isNew { try? files.createDirectory(at: folder, withIntermediateDirectories: true) }
        let listURL = folder.appendingPathComponent(writtenList)
        // File name -> the SHA-256 given (or "" if the list didn't say).
        var written: [String: String] = [:]
        for line in ((try? String(contentsOf: listURL, encoding: .utf8)) ?? "").components(separatedBy: .newlines)
        where !line.isEmpty {
            let parts = line.components(separatedBy: "\t")
            written[parts[0]] = parts.count > 1 ? parts[1] : ((earlierVersionsForChecks ?? earlierVersions)[parts[0]] ?? "")
        }
        var changed = false
        for file in startingFiles {
            let url = folder.appendingPathComponent(file.file)
            let newest = sha256(file.text)
            guard written[file.file] != newest else { continue }
            if let given = written[file.file] {
                // A newer version: in place of the old one, only if it's
                // still exactly as given.
                if let text = try? String(contentsOf: url, encoding: .utf8), !given.isEmpty, sha256(text) == given {
                    try? Data(file.text.utf8).write(to: url)
                }
            } else if !files.fileExists(atPath: url.path) {
                try? Data(file.text.utf8).write(to: url)
            }
            written[file.file] = newest
            changed = true
        }
        if changed {
            try? Data(BandPlan.readme.utf8).write(to: folder.appendingPathComponent("README.txt"))
            let lines = written.keys.sorted().map { "\($0)\t\(written[$0] ?? "")" }
            try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: listURL)
        }
        var loaded = Loaded(plans: [], problems: [])
        let names = ((try? files.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.lowercased().hasSuffix(".txt") && $0 != "README.txt" }.sorted()
        for name in names {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)), data.count < 256_000,
                  let text = String(data: data, encoding: .utf8) else {
                loaded.problems.append("\(name): couldn't be read as text.")
                continue
            }
            switch BandPlan.parse(text) {
            case .success(let plan):
                if loaded.plans.contains(where: { $0.name == plan.name }) {
                    loaded.problems.append("\(name): another file is already named \(plan.name).")
                } else {
                    loaded.plans.append(plan)
                }
            case .failure(let error):
                loaded.problems.append("\(name): \(error.message).")
            }
        }
        return loaded
    }

    static func load() -> Loaded {
        guard let base = try? LogList.baseFolder() else {
            return Loaded(plans: [], problems: ["Solid Copy's folder couldn't be found."])
        }
        return load(from: folder(in: base))
    }

    // The plan Settings > Band Plan names, or the first one (the United
    // States plan, if it's there), or the built-in one if the folder has
    // none that read.
    static func current(named name: String, in loaded: Loaded) -> BandPlan {
        if let plan = loaded.plans.first(where: { $0.name == name }) { return plan }
        if let plan = loaded.plans.first(where: { $0.name == "United States (FCC)" }) ?? loaded.plans.first { return plan }
        if case .success(let plan) = BandPlan.parse(BandPlan.unitedStates) { return plan }
        return BandPlan(name: "None", classes: [])
    }
}
