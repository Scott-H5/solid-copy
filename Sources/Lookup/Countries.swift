// Countries.swift
//
// Which DXCC country (entity) a callsign is in, from cty.dat: the country
// list nearly every logger uses, kept up to date by AD1C at
// https://www.country-files.com/cty/cty.dat (about 110 KB, some 340
// countries). Used for DX spots: their country, and whether you need it.
//
// The file is fetched the first time it's needed and again each month,
// and kept as Application Support/Solid Copy/cty.dat.
//
// Its format: a line for each country, then its prefixes up to a ";":
//
//   Falkland Islands:   13:  16:  SA:  -51.63:   58.72:   4.0:  VP8:
//       VP8;
//   United States:      05:  08:  NA:   37.60:   91.87:   5.0:  K:
//       AA,AB,...,K,N,W,=4U1WB(5)[8],...;
//
// The fields: name, CQ zone, ITU zone, continent, latitude, longitude,
// time offset, main prefix. Each prefix may carry its own zones and so on
// in brackets, which are ignored here; one starting with "=" is a whole
// callsign, not a prefix (an exception, such as a US call in another
// country). A main prefix starting with "*" is a country only for the
// DARC's WAE award, not DXCC, so it's skipped: its calls count for the
// DXCC country they're in.

import Foundation

struct Country: Equatable, Hashable {
    var name: String
    var prefix: String
    var continent: String
}

@MainActor
final class Countries {
    static let shared = Countries()
    static let sourceURL = URL(string: "https://www.country-files.com/cty/cty.dat")!
    static let staleAfter: TimeInterval = 30 * 24 * 60 * 60

    var fileURL: URL = {
        let folder = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return folder.appendingPathComponent("Solid Copy", isDirectory: true).appendingPathComponent("cty.dat")
    }()

    private var table: CountryTable?
    private var fetching = false
    private var waiting: [() -> Void] = []

    // Read from the file the first time it's asked for.
    var isAvailable: Bool { loaded != nil }

    private var loaded: CountryTable? {
        if table == nil, let text = try? String(contentsOf: fileURL, encoding: .utf8) {
            table = CountryTable(text)
        }
        return table
    }

    func country(of call: String) -> Country? { loaded?.country(of: call) }

    // Fetches cty.dat if there isn't one or it's over a month old, then
    // calls `done` (also when it couldn't: the old file, if any, is kept).
    func fetchIfNeeded(_ done: @escaping () -> Void = {}) {
        let modified = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let stale = modified.map { Date().timeIntervalSince($0) > Self.staleAfter } ?? true
        guard stale else { return done() }
        waiting.append(done)
        guard !fetching else { return }
        fetching = true
        let target = fileURL
        Task {
            let id = Activity.shared.start("Country data", "Download cty.dat")
            var updated = false
            if let (data, response) = try? await URLSession.shared.data(from: Self.sourceURL),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let text = String(data: data, encoding: .utf8), CountryTable(text).count > 100 {
                try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                try? data.write(to: target, options: .atomic)
                self.table = nil
                updated = true
            }
            Activity.shared.finish(id, ok: updated,
                                   latest: updated ? "Country data updated." : "Couldn't get country data. The old copy is kept.")
            self.fetching = false
            let callbacks = self.waiting
            self.waiting = []
            callbacks.forEach { $0() }
        }
    }
}

// cty.dat, read: prefixes and whole calls to countries.
struct CountryTable {
    private var prefixes: [String: Country] = [:]
    private var calls: [String: Country] = [:]
    private var longest = 0
    private(set) var count = 0

    init(_ text: String) {
        var current: Country?
        var skipping = false
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            // A country's own line has 8 fields ending in ":"; prefix lines
            // are indented and end in "," or ";".
            if !rawLine.hasPrefix(" "), !rawLine.hasPrefix("\t") {
                let fields = line.split(separator: ":", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard fields.count >= 8 else { current = nil; continue }
                skipping = fields[7].hasPrefix("*")
                current = Country(name: fields[0], prefix: fields[7], continent: fields[3])
                if !skipping { count += 1 }
                continue
            }
            guard let country = current, !skipping else { continue }
            for item in line.split(whereSeparator: { $0 == "," || $0 == ";" }) {
                // Drop the brackets: (CQ zone) [ITU zone] <lat/lon> {continent} ~offset~.
                let entry = String(item.prefix { !"([<{~".contains($0) }).trimmingCharacters(in: .whitespaces)
                guard !entry.isEmpty else { continue }
                if entry.hasPrefix("=") {
                    calls[String(entry.dropFirst()).uppercased()] = country
                } else {
                    prefixes[entry.uppercased()] = country
                    longest = max(longest, entry.count)
                }
            }
        }
    }

    // The country of a call: an exact call first, then the longest prefix
    // that fits. A call with a "/" uses the part that names where it is:
    // "VP2E/W1AW" and "W1AW/VP2E" are in Anguilla, "W1AW/P" and "W1AW/4"
    // where W1AW is. "/MM" (at sea) is in no country.
    func country(of rawCall: String) -> Country? {
        let call = rawCall.uppercased().trimmingCharacters(in: .whitespaces)
        guard !call.isEmpty else { return nil }
        if let exact = calls[call] { return exact }
        var parts = call.split(separator: "/").map(String.init)
        if parts.last == "MM" || parts.last == "AM" { return nil }
        // Portable, mobile, QRP and the like say nothing about the country.
        let modifiers: Set<String> = ["P", "M", "QRP", "QRPP", "A", "R", "LH", "B", "BCN", "J"]
        while parts.count > 1, let last = parts.last, modifiers.contains(last) || (last.count == 1 && last.first!.isNumber) {
            parts.removeLast()
        }
        guard let base = parts.first else { return nil }
        if parts.count == 1 { return calls[base] ?? longestPrefix(base) }
        // Two parts: the one that's a prefix itself ("VP2E") is where it's
        // operated from; otherwise the shorter.
        let place = parts.first { prefixes[$0] != nil } ?? parts.min { $0.count < $1.count } ?? base
        return longestPrefix(place) ?? longestPrefix(base)
    }

    private func longestPrefix(_ text: String) -> Country? {
        var length = min(text.count, longest)
        while length > 0 {
            if let country = prefixes[String(text.prefix(length))] { return country }
            length -= 1
        }
        return nil
    }
}
