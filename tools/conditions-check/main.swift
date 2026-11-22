// Checks band conditions (BandConditions.swift) with N0NBH's XML as it
// came on 22 November 2026, and a pretend fetch: nothing is fetched
// unless you add --live.
import AppKit

func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }

let sample = """
<?xml version="1.0" encoding="UTF-8" ?>
<solar><solardata>
<source url="http://www.hamqsl.com/solar.html">N0NBH</source>
<updated> 22 Nov 2026 1814 GMT</updated>
<solarflux>99</solarflux><aindex> 6</aindex><kindex> 0</kindex><kindexnt>No Report</kindexnt>
<calculatedconditions>
<band name="80m-40m" time="day">Good</band><band name="30m-20m" time="day">Good</band>
<band name="17m-15m" time="day">Fair</band><band name="12m-10m" time="day">Poor</band>
<band name="80m-40m" time="night">Good</band><band name="30m-20m" time="night">Good</band>
<band name="17m-15m" time="night">Poor</band><band name="12m-10m" time="night">Poor</band>
</calculatedconditions>
<calculatedvhfconditions>
<phenomenon name="vhf-aurora" location="northern_hemi">Band Closed</phenomenon>
<phenomenon name="E-Skip" location="north_america">50MHz ES</phenomenon>
</calculatedvhfconditions>
<geomagfield>INACTIVE</geomagfield><signalnoise>S0-S1</signalnoise>
</solardata></solar>
"""

@MainActor func run() async {
    guard let conditions = BandConditions.parse(Data(sample.utf8)) else { return check(false, "N0NBH's XML reads") }
    check(conditions.solarFlux == "99" && conditions.aIndex == "6" && conditions.kIndex == "0"
          && conditions.geomagneticField == "INACTIVE" && conditions.noise == "S0-S1", "the figures, trimmed")
    check(conditions.bands.map(\.name) == ["80m-40m", "30m-20m", "17m-15m", "12m-10m"]
          && conditions.bands[2].day == "Fair" && conditions.bands[2].night == "Poor", "each band pair, day and night, in order")
    let day = conditions.lines(isDay: true)
    check(day == ["Now, daytime here: 80 to 40 meters good, 30 to 20 good, 17 to 15 fair, 12 to 10 poor.",
                  "Tonight: 17 to 15 poor.", "Solar flux 99, A index 6, K index 0.",
                  "Geomagnetic field inactive, noise S0 to S1.", "VHF: E skip, North America: 50MHz ES.",
                  "From HAMQSL.com, N0NBH, updated 1814 UTC."], "by day, a line each: \(day)")
    let night = conditions.lines(isDay: false, age: 90 * 60)
    check(night.first == "Now, night here: 80 to 40 meters good, 30 to 20 good, 17 to 15 poor, 12 to 10 poor."
          && night[1] == "By day: 17 to 15 fair." && night.last?.hasSuffix("fetched 90 minutes ago.") == true,
          "at night, with the day's difference, and how old: \(night)")

    check(BandConditions.parse(Data("<html><body>Not found</body></html>".utf8)) == nil, "a page that isn't N0NBH's isn't used")
    check(BandConditions.parse(Data("not xml at all".utf8)) == nil, "nor is something that isn't XML")
    check(BandConditions.plain("  Good\u{7}<script>  ") == "Goodscript", "odd characters from outside are dropped")

    // The sun: Philadelphia at noon and midnight local (EST, UTC-5).
    let philly = GreatCircle.Position(latitude: 39.95, longitude: -75.17)
    let noon = ISO8601DateFormatter().date(from: "2026-11-22T17:00:00Z")!
    let midnight = ISO8601DateFormatter().date(from: "2026-11-23T05:00:00Z")!
    check(BandConditions.isDay(at: philly, on: noon) && !BandConditions.isDay(at: philly, on: midnight),
          "day at noon, night at midnight")
    let tokyo = GreatCircle.Position(latitude: 35.7, longitude: 139.7)
    check(!BandConditions.isDay(at: tokyo, on: noon), "and night in Tokyo at the same moment")

    // Fetching: once, then kept an hour (N0NBH asks for no more).
    let source = BandConditionsSource.shared
    var fetches = 0, shown: [(String, [String])] = [], said: [String] = []
    source.fetch = {
        fetches += 1
        return Data(sample.utf8)
    }
    source.show = { shown.append(($0, $1)) }
    source.say = { said.append($0) }
    func settle() async { for _ in 0..<50 where shown.isEmpty { try? await Task.sleep(nanoseconds: 20_000_000) } }
    source.showConditions(); await settle()
    check(fetches == 1 && said == ["Getting band conditions."] && shown.first?.0 == "Band Conditions"
          && shown.first?.1.first?.hasPrefix("Now,") == true, "fetched (said as getting), then shown in the window")
    shown = []; said = []
    source.showConditions()
    check(fetches == 1 && shown.count == 1 && said.isEmpty, "asked again within the hour: shown without fetching")

    if CommandLine.arguments.contains("--live") {
        source.fetch = {
            var request = URLRequest(url: BandConditions.url, timeoutInterval: 20)
            request.setValue("Solid Copy", forHTTPHeaderField: "User-Agent")
            return try await URLSession.shared.data(for: request).0
        }
        let live = BandConditions.parse(try! await source.fetch())
        check(live != nil && !(live?.bands.isEmpty ?? true), "live: N0NBH's data reads (\(live?.lines(isDay: true).joined(separator: " ") ?? "nothing"))")
    }
    print("All band conditions checks passed.")
}

let done = Task { @MainActor in await run(); exit(0) }
RunLoop.main.run()
