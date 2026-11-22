// BandConditions.swift
//
// Speech > Say Band Conditions (Option-Command-B; v1.6 item 3): how the
// bands are, said in one go: "Band conditions, daytime here: 80 to 40
// meters good, 30 to 20 good, 17 to 15 fair, 12 to 10 poor. Tonight, 17
// to 15 poor. Solar flux 99, A index 6, K index 0, geomagnetic field
// inactive, noise S0 to S1. From HAMQSL.com, N0NBH, updated 1814 UTC."
//
// Where it comes from: N0NBH's solar data at hamqsl.com, the same figures
// many ham sites and clocks show. It's an XML feed (solarxml.php) of
// today's solar flux, A and K indexes, geomagnetic field, noise and
// N0NBH's own estimate of each band pair, day and night. Nothing is sent
// but the request. N0NBH's page (22 November 2026) asks for credit to
// HAMQSL.com, which every answer gives, and for no more than an hourly
// fetch ("that is the update period for the flux parameters"), so it's
// fetched at most once an hour, and only when you ask. A failed fetch
// says the last figures it has, with how old they are. See docs/CREDITS.md.
//
// Day or night: by the sun at the grid in your profile (above the
// horizon is day), or by the Mac's clock (6 am to 6 pm) without one.
//
// The XML is read as untrusted: only the fields used are kept, each
// short and plain; a file that isn't N0NBH's isn't used.

import Foundation

struct BandConditions: Equatable {
    struct Band: Equatable {
        var name: String     // "80m-40m"
        var day: String      // "Good", "Fair", "Poor"
        var night: String
    }

    var updated = ""         // "22 Nov 2026 1814 GMT"
    var solarFlux = ""
    var aIndex = ""
    var kIndex = ""
    var geomagneticField = ""
    var noise = ""
    var bands: [Band] = []
    // VHF openings N0NBH reports, as "E-Skip, north_america" and its state.
    var vhf: [(what: String, state: String)] = []

    static func == (a: BandConditions, b: BandConditions) -> Bool {
        a.updated == b.updated && a.solarFlux == b.solarFlux && a.aIndex == b.aIndex && a.kIndex == b.kIndex
            && a.geomagneticField == b.geomagneticField && a.noise == b.noise && a.bands == b.bands
            && a.vhf.map(\.what) == b.vhf.map(\.what) && a.vhf.map(\.state) == b.vhf.map(\.state)
    }

    static let url = URL(string: "https://www.hamqsl.com/solarxml.php")!

    // MARK: Reading N0NBH's XML

    // Nil if it isn't N0NBH's solar data (no solar flux and no bands).
    static func parse(_ data: Data) -> BandConditions? {
        guard data.count < 100_000 else { return nil }
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse() else { return nil }
        let found = reader.found
        guard !found.solarFlux.isEmpty || !found.bands.isEmpty else { return nil }
        return found
    }

    private final class Reader: NSObject, XMLParserDelegate {
        var found = BandConditions()
        private var text = ""
        private var attributes: [String: String] = [:]
        private var days: [String: String] = [:], nights: [String: String] = [:], order: [String] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            text = ""
            self.attributes = attributes
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if text.count < 200 { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = BandConditions.plain(text)
            switch name {
            case "updated": found.updated = value
            case "solarflux": found.solarFlux = value
            case "aindex": found.aIndex = value
            case "kindex": found.kIndex = value
            case "geomagfield": found.geomagneticField = value
            case "signalnoise": found.noise = value
            case "band":
                let band = BandConditions.plain(attributes["name"] ?? "")
                guard !band.isEmpty, order.count < 20 else { break }
                if !order.contains(band) { order.append(band) }
                if attributes["time"] == "night" { nights[band] = value } else { days[band] = value }
            case "phenomenon":
                guard found.vhf.count < 20 else { break }
                let what = [attributes["name"], attributes["location"]].compactMap { $0 }.map(BandConditions.plain)
                found.vhf.append((what.joined(separator: ", "), value))
            default: break
            }
            text = ""
        }

        func parserDidEndDocument(_ parser: XMLParser) {
            found.bands = order.map { Band(name: $0, day: days[$0] ?? "", night: nights[$0] ?? "") }
        }
    }

    // Trimmed, at most 40 characters, letters, figures and a little
    // punctuation only: nothing odd from outside is ever said.
    static func plain(_ text: String) -> String {
        let kept = text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || " .-_:/+".unicodeScalars.contains($0) }
        return String(String.UnicodeScalarView(kept).prefix(40))
    }

    // MARK: Saying it

    // "80m-40m" -> "80 to 40 meters" (the first) or "80 to 40".
    static func spokenBand(_ name: String, first: Bool) -> String {
        let parts = name.lowercased().replacingOccurrences(of: "m", with: "").split(separator: "-")
        let words = parts.count == 2 ? "\(parts[0]) to \(parts[1])" : name
        return first ? words + " meters" : words
    }

    // N0NBH's words for VHF, in plain speech: "E-Skip, north_america" ->
    // "E skip, North America".
    static func spokenVHF(_ what: String) -> String {
        let words: [String: String] = ["vhf-aurora": "VHF aurora", "E-Skip": "E skip", "northern_hemi": "northern hemisphere",
                                       "north_america": "North America", "europe": "Europe",
                                       "europe_6m": "Europe on 6 meters", "europe_4m": "Europe on 4 meters"]
        return what.components(separatedBy: ", ").map { words[$0] ?? $0.replacingOccurrences(of: "_", with: " ") }
            .joined(separator: ", ")
    }

    // Everything, for where you are now (day or night).
    func spoken(isDay: Bool, age: TimeInterval? = nil) -> String {
        var parts: [String] = []
        let now = bands.enumerated().map { index, band in
            "\(Self.spokenBand(band.name, first: index == 0)) \((isDay ? band.day : band.night).lowercased())"
        }
        if !now.isEmpty { parts.append("Band conditions, \(isDay ? "daytime" : "night") here: " + now.joined(separator: ", ")) }
        // The other half of the day, only where it's different.
        let changes = bands.filter { $0.day != $0.night && !$0.day.isEmpty && !$0.night.isEmpty }.map { band in
            "\(Self.spokenBand(band.name, first: false)) \((isDay ? band.night : band.day).lowercased())"
        }
        if !now.isEmpty {
            parts.append(changes.isEmpty ? "The same \(isDay ? "tonight" : "by day")"
                         : "\(isDay ? "Tonight" : "By day"), " + changes.joined(separator: ", "))
        }
        let figures = [("Solar flux", solarFlux), ("A index", aIndex), ("K index", kIndex),
                       ("geomagnetic field", geomagneticField.lowercased()),
                       ("noise", noise.replacingOccurrences(of: "-", with: " to "))]
            .filter { !$0.1.isEmpty && $0.1.lowercased() != "no report" }.map { "\($0.0) \($0.1)" }
        if !figures.isEmpty { parts.append(figures.joined(separator: ", ")) }
        // VHF only when something's open: "Band Closed" is the usual answer.
        let open = vhf.filter { !$0.state.isEmpty && $0.state.lowercased() != "band closed" }
            .map { "\(Self.spokenVHF($0.what)): \($0.state)" }
        if !open.isEmpty { parts.append("VHF: " + open.joined(separator: "; ")) }
        var source = "From HAMQSL.com, N0NBH"
        if let time = updated.split(separator: " ").dropFirst(3).first, time.count == 4 { source += ", updated \(time) UTC" }
        if let age, age > 60 * 60 {
            let minutes = Int(age / 60)
            source += minutes < 120 ? ", fetched \(minutes) minutes ago" : ", fetched \(minutes / 60) hours ago"
        }
        parts.append(source)
        return parts.joined(separator: ". ") + "."
    }

    // MARK: Day or night

    // Whether the sun is up at a place: its height from the usual
    // approximate sums (good to a degree or so, plenty for "day").
    static func isDay(at position: GreatCircle.Position, on date: Date = Date()) -> Bool {
        let day = date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_545.0   // days since J2000
        let meanLongitude = (280.46 + 0.985_647_4 * day).truncatingRemainder(dividingBy: 360)
        let anomaly = ((357.528 + 0.985_600_3 * day).truncatingRemainder(dividingBy: 360)) * .pi / 180
        let eclipticLongitude = (meanLongitude + 1.915 * sin(anomaly) + 0.020 * sin(2 * anomaly)) * .pi / 180
        let obliquity = (23.439 - 0.000_000_4 * day) * .pi / 180
        let declination = asin(sin(obliquity) * sin(eclipticLongitude))
        let rightAscension = atan2(cos(obliquity) * sin(eclipticLongitude), cos(eclipticLongitude))
        let sidereal = (280.460_618_37 + 360.985_647_366_29 * day) * .pi / 180
        let hourAngle = sidereal + position.longitude * .pi / 180 - rightAscension
        let latitude = position.latitude * .pi / 180
        let height = asin(sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(hourAngle))
        return height > 0
    }
}

// Fetching, at most once an hour (N0NBH's request), and saying.
@MainActor
final class BandConditionsSource {
    static let shared = BandConditionsSource()
    static let keepSeconds: TimeInterval = 60 * 60

    private(set) var latest: (conditions: BandConditions, fetched: Date)?
    private var fetching = false
    // Swappable for the checks.
    var fetch: () async throws -> Data = {
        var request = URLRequest(url: BandConditions.url, timeoutInterval: 20)
        request.setValue("Solid Copy", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw DatabaseError(message: "hamqsl.com didn't send the solar data.")
        }
        return data
    }
    var say: (String) -> Void = { Speaker.announce($0) }

    // Says the conditions: the ones it has if they're under an hour old,
    // otherwise fetched first.
    func sayConditions() {
        if let latest, Date().timeIntervalSince(latest.fetched) < Self.keepSeconds {
            return say(latest.conditions.spoken(isDay: Self.isDayHere()))
        }
        guard !fetching else { return say("Getting band conditions.") }
        fetching = true
        Task {
            defer { fetching = false }
            do {
                guard let conditions = BandConditions.parse(try await fetch()) else {
                    throw DatabaseError(message: "What hamqsl.com sent isn't the solar data.")
                }
                latest = (conditions, Date())
                say(conditions.spoken(isDay: Self.isDayHere()))
            } catch {
                let problem = "Couldn't get band conditions. \(error.localizedDescription)"
                Activity.shared.record("Band conditions", "N0NBH", ok: false, latest: problem)
                if let latest {
                    say(problem + " The last ones: " + latest.conditions.spoken(
                        isDay: Self.isDayHere(), age: Date().timeIntervalSince(latest.fetched)))
                } else {
                    say(problem)
                }
            }
        }
    }

    // Day by the sun at the profile's grid, or by the clock without one.
    static func isDayHere(now: Date = Date()) -> Bool {
        if let here = GreatCircle.position(grid: Settings.currentProfile.station["my_gridsquare"] ?? "") {
            return BandConditions.isDay(at: here, on: now)
        }
        let hour = Calendar.current.component(.hour, from: now)
        return (6..<18).contains(hour)
    }
}
