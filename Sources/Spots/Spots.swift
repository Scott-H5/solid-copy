// Spots.swift
//
// Spots: someone heard on the air, posted for others to find ("W1AW on
// 14.062 CW, in park US-1333"). The Spots window (SpotsWindowController)
// lists them; Return on one tunes the radio and fills in the form.
//
// Where they come from (each a "source"; more come later):
//   POTA   https://api.pota.app/spot/activator: every park activator
//          spotted lately, as JSON, for example
//            {"activator": "W1AW", "frequency": "14062", "mode": "CW",
//             "reference": "US-1333", "name": "Big Pocono State Park",
//             "locationDesc": "US-PA", "spotTime": "2026-11-15T23:32:21",
//             "comments": "QRV", "spotter": "K1ABC", ...}
//          The frequency is in kilohertz, the time in UTC (without a Z).
//   DX     a DX cluster node (DXCluster.swift), while turned on in
//          Settings > Spots.
//   SOTA   cluster spots whose comment names a SOTA summit (DXCluster.swift
//          says why not SOTA's own API).
//
// The list is fetched only while the Spots window is open, once a minute
// (POTA's own site refreshes about as often), and never moves focus or
// speaks when it changes (accessibility contract, rule 8).

import Foundation

struct Spot: Equatable {
    var source: String        // "POTA", "DX" or "SOTA"
    var call: String
    var hertz: Int
    var mode: String          // as spotted: "CW", "SSB", "FT8"
    var reference: String     // the park, for POTA; the summit, for SOTA
    var parkName: String
    var location: String      // "US-PA"
    var time: Date
    var comments: String
    // DX spots: who spotted it last, and everyone who has in the last 30
    // minutes (a busy station is heard by many skimmers; more means
    // stronger, and wider heard).
    var spotter = ""
    var spotters: Set<String> = []

    // The same spot in a later list (POTA spots are posted again as
    // they're re-spotted, with a new time).
    var key: String { "\(source) \(call) \(reference) \(band ?? "")" }

    var band: String? { Bands.name(forHertz: hertz) }

    // "Pennsylvania", from the place code, as for parks.
    var place: String { Park(reference: reference, name: parkName, location: location, grid: "").place }

    // The mode as a group, for the filter: "CW", "Phone" or "Data".
    var modeGroup: String { Self.group(of: mode) }

    static func group(of mode: String) -> String {
        switch mode.uppercased() {
        case "CW": return "CW"
        case "SSB", "USB", "LSB", "AM", "FM", "PHONE": return "Phone"
        default: return mode.isEmpty ? "" : "Data"
        }
    }

    // hamlib's mode for the radio: SSB becomes the band's usual sideband;
    // FT8, FT4, PSK and the rest are the radio's data mode.
    var radioMode: String? {
        switch mode.uppercased() {
        case "CW": return "CW"
        case "SSB", "PHONE": return hertz < 10_000_000 ? "LSB" : "USB"
        case "USB", "LSB", "AM", "FM", "RTTY": return mode.uppercased()
        case "": return nil
        default: return "PKTUSB"
        }
    }

    // One line, most important first, for VoiceOver and the screen:
    // "W1AW, 14.062 CW, US-1333 Big Pocono State Park, Pennsylvania, 3
    // minutes ago, worked today. QRV".
    // A DX spot also says its country and whether you need it:
    // "VP8XYZ, 14.025 CW, Falkland Islands, needed: new country, ...".
    func line(now: Date, worked: Bool, country: String? = nil, needed: String? = nil) -> String {
        let megahertz = RadioReading.trimmedMegahertz(hertz)
        let minutes = max(0, Int(now.timeIntervalSince(time) / 60))
        let age = minutes == 0 ? "just now" : minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        var parts = [call, [megahertz, mode].filter { !$0.isEmpty }.joined(separator: " ")]
        if source == "SOTA" { parts.append("summit " + reference) }
        else if !reference.isEmpty { parts.append([reference, parkName].filter { !$0.isEmpty }.joined(separator: " ")) }
        if !place.isEmpty { parts.append(place) }
        if let country { parts.append(country + (needed.map { ", needed: \($0)" } ?? "")) }
        if spotters.count > 1 { parts.append("heard by \(spotters.count)") }
        parts.append(age)
        if worked { parts.append("worked today") }
        let text = parts.joined(separator: ", ")
        let comment = comments.trimmingCharacters(in: .whitespacesAndNewlines)
        return comment.isEmpty ? text : "\(text). \(comment)"
    }

    // The log field the reference goes in: their park or their summit.
    var referenceField: String { source == "SOTA" ? "sota_ref" : "pota_ref" }

    // True if this contact counts as this spot already worked: POTA counts
    // a hunter's contact once per park, band and mode each UTC day; SOTA a
    // chaser's once per summit each UTC day, on any band or mode.
    func isWorked(by qso: QSO, today: String) -> Bool {
        guard Callsign.normalized(qso.call) == Callsign.normalized(call),
              POTASpots.utcDay.string(from: qso.timeOn) == today else { return false }
        if source == "SOTA" { return qso["sota_ref"].uppercased() == reference.uppercased() }
        if !reference.isEmpty,
           !ParkSearch.parts(of: qso["pota_ref"]).contains(where: { $0.uppercased() == reference.uppercased() }) {
            return false
        }
        if let band, !qso["band"].isEmpty, qso["band"].lowercased() != band.lowercased() { return false }
        if !qso["mode"].isEmpty, !mode.isEmpty, Self.group(of: qso["mode"]) != modeGroup { return false }
        return true
    }
}

// POTA's spots: fetching and reading them.
enum POTASpots {
    static let url = URL(string: "https://api.pota.app/spot/activator")!

    // One spot as POTA sends it. Every field may be missing or null.
    private struct Entry: Decodable {
        var activator: String?
        var frequency: String?
        var mode: String?
        var reference: String?
        var name: String?
        var locationDesc: String?
        var spotTime: String?
        var comments: String?
    }

    // Reads POTA's JSON. Spots without a call or a usable frequency are
    // left out; so is anything that isn't POTA's list at all.
    static func spots(from data: Data) throws -> [Spot] {
        try JSONDecoder().decode([Entry].self, from: data).compactMap { entry in
            guard let call = entry.activator?.trimmingCharacters(in: .whitespaces).uppercased(), !call.isEmpty,
                  let kilohertz = entry.frequency.flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }),
                  kilohertz > 0 else { return nil }
            return Spot(source: "POTA", call: call, hertz: Int((kilohertz * 1_000).rounded()),
                        mode: (entry.mode ?? "").uppercased(), reference: (entry.reference ?? "").uppercased(),
                        parkName: entry.name ?? "", location: entry.locationDesc ?? "",
                        time: entry.spotTime.flatMap { spotTime.date(from: $0) } ?? Date(),
                        comments: entry.comments ?? "")
        }
    }

    // "2026-11-15T23:32:21", in UTC.
    static let spotTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    // "2026-11-15", the UTC day, for "worked today".
    static let utcDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

// The spots now, fetched once a minute while something wants them.
@MainActor
final class SpotList {
    static let shared = SpotList()
    static let didChange = Notification.Name("SolidCopySpotsDidChange")
    static let refreshSeconds: TimeInterval = 60

    // Every spot, newest first: POTA's and the DX cluster's (SOTA's too).
    var spots: [Spot] { (potaSpots + clusterSpots.values).sorted { $0.time > $1.time } }
    private(set) var potaSpots: [Spot] = []
    // DX cluster spots, one per call and band (the latest), for 30 minutes.
    private var clusterSpots: [String: Spot] = [:]
    static let clusterKeepSeconds: TimeInterval = 30 * 60
    static let clusterMostSpots = 2_000
    private(set) var fetched: Date?
    // What went wrong with the last fetch, or nil.
    private(set) var problem: String?
    private var timer: Timer?
    private var fetching = false
    let cluster = DXCluster()
    let worked = WorkedCountries()
    // Cluster spots come in all the time; the window is told at most
    // every 10 seconds, so the list doesn't change under you constantly.
    private var pendingPost: Task<Void, Never>?
    // The log, for "needed" (set by the Spots window).
    var log: () -> [QSO] = { [] }
    // The needed sound for a new DX spot: once per call
    // and band, and at most once every 30 seconds, so a burst of spots (as
    // when the cluster first connects) is one sound, not twenty.
    private var chimed: Set<String> = []
    private var lastChime: Date?
    static let chimeEvery: TimeInterval = 30
    // How the sound is played; the checks listen in here.
    var chime: () -> Void = { Alert.needed.play() }

    init() {
        cluster.onSpot = { [weak self] spot in self?.add(spot) }
        cluster.onState = { [weak self] in self?.postSoon() }
        // Another profile may have another callsign to log in with.
        NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SpotList.shared.applyClusterSettings() }
        }
    }

    // Connects to (or leaves) the DX cluster as Settings > Spots says.
    func applyClusterSettings() {
        let call = Settings.currentProfile.station["station_callsign"] ?? ""
        guard timer != nil, Settings.clusterEnabled, Callsign.looksValid(call) else {
            cluster.stop()
            if timer != nil { clusterSpots = [:] }
            return post()
        }
        Countries.shared.fetchIfNeeded { [weak self] in
            self?.worked.reset()
            self?.post()
        }
        cluster.start(host: Settings.clusterHost, port: Settings.clusterPort, call: call,
                      commands: DXCluster.commands(skimmer: Settings.clusterSkimmer, ft8: Settings.clusterFT8))
    }

    // What the cluster is doing, for the window: "Connected to …", or why
    // it's off.
    var clusterState: String {
        if !Settings.clusterEnabled { return "DX cluster off (Settings > Spots)." }
        let call = Settings.currentProfile.station["station_callsign"] ?? ""
        if !Callsign.looksValid(call) { return "DX cluster needs your callsign, in Settings > Profiles." }
        return "DX cluster: " + cluster.state
    }

    private func add(_ spot: Spot) {
        let cutoff = Date().addingTimeInterval(-Self.clusterKeepSeconds)
        guard spot.time >= cutoff else { return }
        let key = "\(spot.call) \(spot.band ?? "")"
        // The latest spot, with everyone who's spotted it lately.
        var spot = spot
        if let earlier = clusterSpots[key] { spot.spotters.formUnion(earlier.spotters) } else { chimeIfNeeded(spot, key: key) }
        clusterSpots[key] = spot
        if clusterSpots.count > Self.clusterMostSpots {
            clusterSpots = clusterSpots.filter { $0.value.time >= cutoff }
            // Still too many: the oldest go.
            if clusterSpots.count > Self.clusterMostSpots {
                let keep = clusterSpots.sorted { $0.value.time > $1.value.time }.prefix(Self.clusterMostSpots)
                clusterSpots = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
            }
        }
        postSoon()
    }

    private func chimeIfNeeded(_ spot: Spot, key: String, now: Date = Date()) {
        let wanted = Settings.neededSpotSound
        guard wanted != .off, spot.source == "DX", !chimed.contains(key),
              lastChime.map({ now.timeIntervalSince($0) >= Self.chimeEvery }) ?? true,
              let needed = worked.needed(spot, country: Countries.shared.country(of: spot.call), log: log()),
              wanted == .anyNeeded || needed == "new country" else { return }
        if chimed.count > 5_000 { chimed = [] }
        chimed.insert(key)
        lastChime = now
        chime()
    }

    private func postSoon() {
        guard pendingPost == nil else { return }
        pendingPost = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self else { return }
            self.pendingPost = nil
            self.post()
        }
    }

    private func post() {
        // Old cluster spots go.
        let cutoff = Date().addingTimeInterval(-Self.clusterKeepSeconds)
        clusterSpots = clusterSpots.filter { $0.value.time >= cutoff }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    // Starts fetching (now, then once a minute), or stops.
    func start() {
        guard timer == nil else { return }
        defer { applyClusterSettings() }
        refresh()
        let timer = Timer(timeInterval: Self.refreshSeconds, repeats: true) { _ in
            MainActor.assumeIsolated { SpotList.shared.refresh() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cluster.stop()
        clusterSpots = [:]
    }

    func refresh() {
        guard !fetching else { return }
        fetching = true
        Task {
            do {
                var request = URLRequest(url: POTASpots.url, timeoutInterval: 20)
                request.setValue("Solid Copy", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw DatabaseError(message: "POTA didn't send its spots.")
                }
                let spots = try POTASpots.spots(from: data)
                noteFetch(problem: nil, count: spots.count)
                set(spots, problem: nil)
            } catch {
                let message = "Couldn't get POTA spots. \(error.localizedDescription)"
                noteFetch(problem: message, count: 0)
                set(potaSpots, problem: message)
            }
        }
    }

    // Window > Activity gets POTA's spots once, when they first arrive,
    // and after that only when they stop or start working again: not
    // every minute.
    private var spotsListed = false
    private var spotProblem: String?
    private func noteFetch(problem: String?, count: Int) {
        if let problem {
            if problem != spotProblem { Activity.shared.record("POTA", "Spots", ok: false, latest: problem) }
            spotProblem = problem
        } else {
            if spotProblem != nil {
                Activity.shared.record("POTA", "Spots", ok: true, latest: "Spots are back: \(count) spots.")
            } else if !spotsListed {
                Activity.shared.record("POTA", "Spots", ok: true, latest: "\(count) spots fetched.")
            }
            spotsListed = true
            spotProblem = nil
        }
    }

    // POTA's spots. Also used by the checks, with spots of their own.
    func set(_ newSpots: [Spot], problem newProblem: String?) {
        fetching = false
        potaSpots = newSpots
        if newProblem == nil { fetched = Date() }
        problem = newProblem
        post()
    }

    // For the checks: a cluster spot, as if it had come in.
    func addClusterSpot(_ spot: Spot) {
        add(spot)
        pendingPost?.cancel()
        pendingPost = nil
        post()
    }
}
