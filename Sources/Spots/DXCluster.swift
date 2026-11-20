// DXCluster.swift
//
// DX cluster spots: a cluster node is a server hams connect to over the
// internet (telnet, plain text) that passes on every spot posted by
// anyone on the network, thousands an hour. After logging in with your
// callsign, each spot arrives as a line like:
//
//   DX de K1ABC:     14025.0  VP8XYZ       CQ CQ up 2              1432Z
//
// that is: who spotted it, the frequency in kilohertz, the call heard,
// a comment, and the time (UTC). Lines that aren't spots (greetings,
// announcements, the prompt) are ignored.
//
// The node is a setting (Settings > Spots): VE7CC (dxc.ve7cc.net, port
// 23) unless you choose another. After logging in, Solid Copy tells the
// node whether to send skimmer (machine-heard CW) and FT8/FT4 spots,
// which CC Cluster nodes such as VE7CC leave out unless asked (found
// logging in to VE7CC, 15 November 2026: two spots in two minutes
// without them). The node remembers these for your call, so both are
// always sent, on or off. A node that doesn't know a command just says
// so, and the line is ignored. It's connected only while the Spots
// window is open and DX cluster spots are turned on, and connected again
// 30 seconds after it drops, for as long as that's so.
//
// A spot has no mode, so it's worked out: from the comment if it says
// ("FT8", "SSB"), or else from where on the band the frequency is (the
// FT8 frequencies, the CW and phone parts of the band plan).
//
// A spot whose comment names a SOTA summit ("W4C/CM-001", "G/LD-003") is
// a SOTA activation, and is listed as a SOTA spot, with its summit. This
// is how Solid Copy gets SOTA spots without SOTA's own API, whose terms
// (api-db2.sota.org.uk/docs, read 16 November 2026) don't allow
// AI-assisted software without SOTA's approval. Only the spots someone
// posts to the cluster are seen, so it's most, not all, of them.

import Foundation
import Network

@MainActor
final class DXCluster {
    // Ready-made nodes for Settings > Spots.
    static let nodes: [(name: String, host: String, port: Int)] = [
        ("VE7CC, Vancouver", "dxc.ve7cc.net", 23),
        ("W3LPL, Maryland", "dxc.w3lpl.net", 7373),
        // AR-Cluster at a well-known contest station (answered 15 November 2026).
        ("K3LR, Pennsylvania", "dx.k3lr.com", 23),
    ]

    // Called with each spot, and when the state changes.
    var onSpot: ((Spot) -> Void)?
    var onState: (() -> Void)?
    // "Connected to dxc.ve7cc.net", "Connecting…", "Couldn't connect…".
    private(set) var state = "Off."

    private var connection: NWConnection?
    // Window > Activity hears about the connection when it first comes up,
    // when it comes back, and when there's new trouble: not each retry.
    private var listedUp = false
    private var listedProblem: String?
    private var buffer = Data()
    private var loggedIn = false
    private var running = false
    private var retry: Task<Void, Never>?
    private var loginTimer: Task<Void, Never>?
    private var host = ""
    private var call = ""
    private var port = 0
    // What to ask the node for after logging in ("SET/SKIMMER", ...).
    private var commands: [String] = []

    // The commands for skimmer and FT8/FT4 spots, on or off.
    static func commands(skimmer: Bool, ft8: Bool) -> [String] {
        [skimmer ? "SET/SKIMMER" : "SET/NOSKIMMER"]
            + (ft8 ? ["SET/FT8", "SET/FT4"] : ["SET/NOFT8", "SET/NOFT4"])
    }

    // Connects to a node and logs in with `call`, and keeps at it. Only
    // the commands changed: they're sent, without connecting again.
    func start(host: String, port: Int, call: String, commands: [String]) {
        if running, host == self.host, port == self.port, call == self.call {
            if commands != self.commands {
                self.commands = commands
                if loggedIn { send(commands) }
            }
            return
        }
        stop()
        running = true
        self.host = host
        self.port = port
        self.call = call
        self.commands = commands
        connect(port: port)
    }

    func stop() {
        running = false
        listedUp = false
        listedProblem = nil
        retry?.cancel()
        loginTimer?.cancel()
        connection?.cancel()
        connection = nil
        set("Off.")
    }

    private func connect(port: Int) {
        guard running, let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            return set("The DX cluster's port isn't a number from 1 to 65535.")
        }
        buffer.removeAll()
        loggedIn = false
        let options = NWProtocolTCP.Options()
        // Keep-alives, so a quiet connection isn't dropped along the way.
        options.enableKeepalive = true
        options.keepaliveIdle = 60
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort,
                                      using: NWParameters(tls: nil, tcp: options))
        self.connection = connection
        set("Connecting to \(host)…")
        connection.stateUpdateHandler = { [weak self] newState in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.changed(newState, connection, port: port) }
            }
        }
        connection.start(queue: .main)
    }

    private func changed(_ newState: NWConnection.State, _ from: NWConnection, port: Int) {
        guard from === connection else { return }
        switch newState {
        case .ready:
            set("Connected to \(host).")
            if listedProblem != nil {
                Activity.shared.record("DX cluster", "Connection", ok: true, latest: "Connected again to \(host).")
            } else if !listedUp {
                Activity.shared.record("DX cluster", "Connection", ok: true, latest: "Connected to \(host).")
            }
            listedUp = true
            listedProblem = nil
            receive(on: from, port: port)
            // If the node never asks for a call, send it anyway.
            loginTimer = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled else { return }
                self?.logIn()
            }
        case .failed(let error):
            dropped("Couldn't connect to \(host): \(error.localizedDescription)", port: port)
        case .waiting(let error):
            dropped("Waiting to connect to \(host): \(error.localizedDescription)", port: port)
        default:
            break
        }
    }

    // Lost: try again in 30 seconds, while still wanted.
    private func dropped(_ why: String, port: Int) {
        connection?.cancel()
        connection = nil
        loginTimer?.cancel()
        if why != listedProblem {
            Activity.shared.record("DX cluster", "Connection", ok: false, latest: why)
        }
        listedProblem = why
        set(why + " Trying again shortly.")
        retry?.cancel()
        retry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            self?.connect(port: port)
        }
    }

    private func receive(on connection: NWConnection, port: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, done, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, connection === self.connection else { return }
                    if let data, !data.isEmpty { self.received(data) }
                    if done || error != nil {
                        self.dropped("\(self.host) closed the connection.", port: port)
                    } else {
                        self.receive(on: connection, port: port)
                    }
                }
            }
        }
    }

    private func received(_ data: Data) {
        buffer.append(data)
        // A node that's flooding without line breaks isn't a cluster.
        if buffer.count > 65_536 { buffer.removeAll() }
        while let end = buffer.firstIndex(of: 10) {
            let line = String(decoding: buffer[..<end], as: UTF8.self)
            buffer.removeSubrange(...end)
            if let spot = Self.spot(fromLine: line, now: Date()) { onSpot?(spot) }
        }
        // The login prompt has no line break after it: "login: ".
        let waiting = String(decoding: buffer, as: UTF8.self).lowercased()
        if !loggedIn, waiting.contains("login") || waiting.contains("call") { logIn() }
    }

    private func logIn() {
        guard !loggedIn, let connection else { return }
        loggedIn = true
        loginTimer?.cancel()
        connection.send(content: Data((call + "\r\n").utf8), completion: .contentProcessed { _ in })
        // The node's own settings, once it's had a moment to log us in.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, connection === self.connection else { return }
            self.send(self.commands)
        }
    }

    private func send(_ lines: [String]) {
        guard let connection, !lines.isEmpty else { return }
        let text = lines.map { $0 + "\r\n" }.joined()
        connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in })
    }

    private func set(_ newState: String) {
        state = newState
        onState?()
    }

    // MARK: - Reading spots

    // A "DX de" line as a spot, or nil. Its time is today (UTC), or
    // yesterday if that would be more than an hour ahead.
    nonisolated static func spot(fromLine raw: String, now: Date) -> Spot? {
        // Bells and other control characters some nodes send.
        let line = String(raw.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 }.map(Character.init))
        guard line.hasPrefix("DX de ") else { return nil }
        let pattern = #"^DX de\s+([^:\s]+):\s*([0-9]+(?:\.[0-9]+)?)\s+(\S+)\s*(.*?)\s*([0-9]{4})Z"#
        guard let match = line.range(of: pattern, options: .regularExpression) else { return nil }
        let text = String(line[match])
        let regex = try? NSRegularExpression(pattern: pattern)
        guard let result = regex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ index: Int) -> String {
            Range(result.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
        guard let kilohertz = Double(group(2)), kilohertz > 0 else { return nil }
        let call = group(3).uppercased()
        guard Callsign.looksValid(call) else { return nil }
        let hertz = Int((kilohertz * 1_000).rounded())
        let comment = group(4)
        let time = spotTime(group(5), now: now)
        let spotter = group(1).uppercased()
        let summitRef = Self.summit(in: comment)
        return Spot(source: summitRef == nil ? "DX" : "SOTA", call: call, hertz: hertz,
                    mode: mode(hertz: hertz, comment: comment),
                    reference: summitRef ?? "", parkName: "", location: "", time: time,
                    comments: [comment, "spotted by \(spotter)"].filter { !$0.isEmpty }.joined(separator: ", "),
                    spotter: spotter, spotters: [spotter])
    }

    // The SOTA summit a comment names, or nil: an association (1 to 4
    // letters and digits: "W4C", "G", "VK3"), a "/", a region (2 letters),
    // a "-" and 3 digits. Not part of a longer word, so a callsign with a
    // "/" in it isn't taken for one.
    nonisolated static func summit(in comment: String) -> String? {
        let pattern = #"(?<![A-Z0-9/])[A-Z0-9]{1,4}/[A-Z]{2}-[0-9]{3}(?![0-9A-Z])"#
        let text = comment.uppercased()
        return text.range(of: pattern, options: .regularExpression).map { String(text[$0]) }
    }

    // A spotter's own call, without a node's or skimmer's ending:
    // "W3LPL-#" and "DL1ABC-2-#" are W3LPL and DL1ABC.
    nonisolated static func spotterCall(_ spotter: String) -> String {
        String(spotter.split(separator: "-").first ?? Substring(spotter))
    }

    // "1432" as today at 14:32 UTC.
    nonisolated private static func spotTime(_ hhmm: String, now: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let hours = Int(hhmm.prefix(2)), let minutes = Int(hhmm.suffix(2)),
              var date = calendar.date(bySettingHour: hours, minute: minutes, second: 0, of: now) else { return now }
        if date.timeIntervalSince(now) > 3_600 { date = date.addingTimeInterval(-86_400) }
        return date
    }

    // The mode: named in the comment, or from the band plan.
    nonisolated static func mode(hertz: Int, comment: String) -> String {
        let words = Set(comment.uppercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        for named in ["FT8", "FT4", "RTTY", "PSK31", "JS8", "SSB", "USB", "LSB", "CW", "FM", "AM"] where words.contains(named) {
            return ["USB", "LSB"].contains(named) ? "SSB" : named
        }
        let kilohertz = Double(hertz) / 1_000
        // The usual FT8 and FT4 frequencies, give or take 3 kHz.
        let ft8 = [1_840, 3_573, 7_074, 10_136, 14_074, 18_100, 21_074, 24_915, 28_074, 50_313]
        let ft4 = [3_575, 7_047.5, 10_140, 14_080, 18_104, 21_140, 24_919, 28_180, 50_318]
        if ft8.contains(where: { abs(kilohertz - Double($0)) <= 3 }) { return "FT8" }
        if ft4.contains(where: { abs(kilohertz - $0) <= 2 }) { return "FT4" }
        // Where phone starts on each band (CW and data below).
        let phoneFrom: [(low: Double, high: Double, phone: Double)] = [
            (1_800, 2_000, 1_843), (3_500, 4_000, 3_600), (7_000, 7_300, 7_125), (14_000, 14_350, 14_150),
            (18_068, 18_168, 18_110), (21_000, 21_450, 21_200), (24_890, 24_990, 24_930),
            (28_000, 29_700, 28_300), (50_000, 54_000, 50_100),
        ]
        if let band = phoneFrom.first(where: { kilohertz >= $0.low && kilohertz <= $0.high }) {
            return kilohertz >= band.phone ? "SSB" : "CW"
        }
        // 60 meters and 30 meters: channels and CW and data.
        if kilohertz >= 10_100 && kilohertz <= 10_150 { return "CW" }
        return ""
    }
}

// Which countries, and which bands and modes for each, are in the log, for
// "needed": a DX spot is needed if its country has never been worked, or
// not on that band, or not in that kind of mode. Kept up to date as you
// log: contacts added since last time are counted on; anything else (an
// edit, a delete, an import) counts the log again.
@MainActor
final class WorkedCountries {
    private var countries: Set<String> = []
    private var bands: Set<String> = []
    private var modes: Set<String> = []
    private var counted = 0
    private var lastID: UUID?

    // Count the log again (when cty.dat has just arrived, say).
    func reset() { counted = 0 }

    // "new country", "new band", "new mode", or nil if not needed.
    func needed(_ spot: Spot, country: Country?, log: [QSO]) -> String? {
        needed(country: country, band: spot.band, modeGroup: spot.modeGroup, log: log)
    }

    // The same for the call in the logging form (CLAUDE.md item 6), with
    // the band and mode it's on now. Mode groups as Spot.group: CW,
    // Phone, Data.
    func needed(country: Country?, band: String?, modeGroup: String, log: [QSO]) -> String? {
        guard let country else { return nil }
        update(log)
        if !countries.contains(country.name) { return "new country" }
        if let band, !band.isEmpty, !bands.contains(country.name + " " + band.lowercased()) { return "new band" }
        if !modeGroup.isEmpty, !modes.contains(country.name + " " + modeGroup) { return "new mode" }
        return nil
    }

    private func update(_ log: [QSO]) {
        let appended = counted > 0 && log.count >= counted && log[counted - 1].id == lastID
        if !appended {
            countries = []
            bands = []
            modes = []
            counted = 0
        }
        let table = Countries.shared
        for qso in log[counted...] {
            guard let name = table.country(of: qso.call)?.name else { continue }
            countries.insert(name)
            if !qso["band"].isEmpty { bands.insert(name + " " + qso["band"].lowercased()) }
            let group = Spot.group(of: qso["mode"])
            if !group.isEmpty { modes.insert(name + " " + group) }
        }
        counted = log.count
        lastID = log.last?.id
    }
}
