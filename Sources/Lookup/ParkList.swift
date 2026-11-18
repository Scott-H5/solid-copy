// ParkList.swift
//
// Every POTA park, kept on this Mac so a park can be found by reference,
// name or state with no internet (in a park, there often isn't any).
//
// Where it comes from: POTA publishes the whole list as one CSV file,
// https://pota.app/all_parks_ext.csv (about 10 MB, 106,000 parks in
// November 2026), with these columns:
//
//   "reference","name","active","entityId","locationDesc","latitude","longitude","grid"
//   "US-1333","Big Pocono State Park","1","291","US-PA","41.0426","-75.3497","FN21hb"
//
// locationDesc can list several places ("US-DC,US-MD,US-WV") for a park
// that crosses a border.
//
// Where it's kept: its own file, Parks.sqlite, beside the log (not in it:
// the log is backed up each time Solid Copy opens, and this is reference
// data that's easy to fetch again). A fresh copy is built in a new file
// and only then put in place, so a failed download never leaves a broken
// list. It's fetched the first time a park field is used (or from
// Settings > Lookup), and again when it's over 30 days old.
//
// Searching: an FTS5 ("full-text search") table, SQLite's own index of
// words, so "pocono", "big poc" or "pennsylvania state" finds Big Pocono
// State Park among 106,000 at once. Each word typed must match the start
// of a word in the reference, name or place.

import Foundation

struct Park: Equatable {
    var reference: String
    var name: String
    // POTA's place codes: "US-PA", or "US-DC,US-MD,US-WV".
    var location: String
    var grid: String

    // In words: "Pennsylvania"; "District of Columbia, Maryland, West
    // Virginia"; places outside the US and Canada as POTA gives them.
    var place: String {
        location.split(separator: ",").map { code in
            let parts = code.split(separator: "-")
            if parts.count == 2, ["US", "CA"].contains(parts[0]), let name = USStates.name(for: String(parts[1])) {
                return name
            }
            return String(code)
        }.joined(separator: ", ")
    }

    // "US-1333, Big Pocono State Park, Pennsylvania".
    var spoken: String { [reference, name, place].filter { !$0.isEmpty }.joined(separator: ", ") }
}

@MainActor
final class ParkList {
    static let shared = ParkList()

    static let sourceURL = URL(string: "https://pota.app/all_parks_ext.csv")!
    // Fetched again after this long.
    static let staleAfter: TimeInterval = 30 * 24 * 60 * 60

    // The file, normally in Application Support; the checks use their own.
    var fileURL: URL = {
        let folder = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return folder.appendingPathComponent("Solid Copy", isDirectory: true).appendingPathComponent("Parks.sqlite")
    }()

    private var database: Database?
    private(set) var isUpdating = false
    // Told when an update finishes: the number of parks, or what went wrong.
    private var waiting: [(Result<Int, Error>) -> Void] = []

    // The list, opened the first time it's needed. nil if there isn't one yet.
    private var opened: Database? {
        if database == nil, FileManager.default.fileExists(atPath: fileURL.path) {
            database = try? Database(url: fileURL)
        }
        return database
    }

    var isAvailable: Bool { count > 0 }

    var count: Int {
        Int((try? opened?.query("SELECT count(*) AS n FROM park").first?["n"]) ?? "") ?? 0
    }

    // When the list was fetched, or nil.
    var updated: Date? {
        guard let text = try? opened?.query("SELECT value FROM about WHERE key = 'updated'").first?["value"],
              let seconds = Double(text) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    var isStale: Bool { updated.map { Date().timeIntervalSince($0) > Self.staleAfter } ?? true }

    // "106,049 parks, from 15 November 2026", for Settings.
    var summary: String {
        guard isAvailable, let updated else { return "Not downloaded yet." }
        let date = DateFormatter.localizedString(from: updated, dateStyle: .long, timeStyle: .none)
        return "\(count.formatted()) parks, from \(date)."
    }

    // MARK: - Finding parks

    // A park by its exact reference ("us-1333" works too), active or not:
    // old contacts may name a park POTA has since retired.
    func park(_ reference: String) -> Park? {
        let rows = try? opened?.query("SELECT * FROM park WHERE reference = ?",
                                      [reference.trimmingCharacters(in: .whitespaces).uppercased()])
        return rows?.first.map(Self.park)
    }

    // Active parks matching what's typed, best first, at most `limit`.
    // Something like a reference ("US-13", "K-4") matches references that
    // start with it; anything else is words, each the start of a word in
    // the reference, name or place.
    func search(_ text: String, limit: Int = 50) -> [Park] {
        guard let database = opened else { return [] }
        let typed = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard !typed.isEmpty else { return [] }
        if typed.range(of: #"^[A-Z0-9]{1,4}-[0-9]*$"#, options: .regularExpression) != nil {
            let rows = try? database.query(
                "SELECT * FROM park WHERE reference LIKE ? AND active = '1' ORDER BY reference LIMIT \(limit)",
                [typed + "%"])
            return (rows ?? []).map(Self.park)
        }
        // Each word quoted, so nothing typed can be taken as FTS5's own
        // syntax, and as the start of a word ("POCONO"*), except a state or
        // province code ("PA"), which must be the whole word, or it would
        // find every "Park" too.
        let words = typed.split { !$0.isLetter && !$0.isNumber }.map { word in
            word.count == 2 && USStates.name(for: String(word)) != nil ? "\"\(word)\"" : "\"\(word)\"*"
        }
        guard !words.isEmpty else { return [] }
        let rows = try? database.query(
            """
            SELECT park.* FROM park_search JOIN park ON park.rowid = park_search.rowid
            WHERE park_search MATCH ? AND park.active = '1' ORDER BY park_search.rank LIMIT \(limit)
            """, [words.joined(separator: " ")])
        return (rows ?? []).map(Self.park)
    }

    private static func park(_ row: [String: String]) -> Park {
        Park(reference: row["reference"] ?? "", name: row["name"] ?? "",
             location: row["location"] ?? "", grid: row["grid"] ?? "")
    }

    // MARK: - Fetching the list

    // Fetches POTA's list and puts it in place. `done` gets the number of
    // parks, or what went wrong; an update already under way is joined.
    func update(_ done: @escaping (Result<Int, Error>) -> Void) {
        waiting.append(done)
        guard !isUpdating else { return }
        isUpdating = true
        let target = fileURL
        Task {
            let result: Result<Int, Error> = await Activity.shared.track("POTA", "Park list", { _ in
                do {
                    let (data, response) = try await URLSession.shared.data(from: Self.sourceURL)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        throw DatabaseError(message: "POTA's park list couldn't be fetched.")
                    }
                    // Built away from the main thread: 106,000 rows take a
                    // second or two.
                    return .success(try await Task.detached { try Self.build(from: data, into: target) }.value)
                } catch {
                    return .failure(error)
                }
            }, finish: { outcome in
                switch outcome {
                case .success(let count): return (true, "\(count.formatted()) parks.")
                case .failure(let error): return (false, error.localizedDescription)
                }
            })
            self.finished(result)
        }
    }

    // Fetches the list if it's over 30 days old (it's only fetched the
    // first time when a park field is used). Quietly: a failure waits for
    // next time.
    func updateIfStale() {
        guard isAvailable, isStale else { return }
        update { _ in }
    }

    // Opens the file afresh the next time it's used: after a new list
    // has been put in its place.
    func reopen() { database = nil }

    private func finished(_ result: Result<Int, Error>) {
        isUpdating = false
        // The new file is in place: open it afresh.
        reopen()
        let callbacks = waiting
        waiting = []
        callbacks.forEach { $0(result) }
    }

    // Reads the CSV and builds the list in a new file next to `target`,
    // then puts it in place. Returns the number of parks.
    nonisolated static func build(from data: Data, into target: URL) throws -> Int {
        let rows = CSV.rows(data)
        guard let header = rows.first else { throw DatabaseError(message: "POTA's park list was empty.") }
        // Columns by name, so a new column or a new order doesn't matter.
        func column(_ name: String) throws -> Int {
            guard let index = header.firstIndex(of: name) else {
                throw DatabaseError(message: "POTA's park list has no \(name) column.")
            }
            return index
        }
        let reference = try column("reference"), name = try column("name"), active = try column("active")
        let location = try column("locationDesc"), grid = try column("grid")

        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let building = target.deletingLastPathComponent().appendingPathComponent("Parks-new.sqlite")
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: building.path + suffix) }
        var count = 0
        do {
            let database = try Database(url: building)
            try database.execute("""
                CREATE TABLE park (reference TEXT PRIMARY KEY, name TEXT, location TEXT, place TEXT,
                                   grid TEXT, active TEXT);
                CREATE VIRTUAL TABLE park_search USING fts5(reference, name, place,
                                                            content = 'park', content_rowid = 'rowid');
                CREATE TABLE about (key TEXT PRIMARY KEY, value TEXT);
                """)
            try database.transaction {
                var values: [[String]] = []
                for row in rows.dropFirst() where row.count == header.count && !row[reference].isEmpty {
                    let park = Park(reference: row[reference].uppercased(), name: row[name],
                                    location: row[location], grid: row[grid])
                    // The place in words and as codes, so "Pennsylvania" and
                    // "PA" both find it.
                    values.append([park.reference, park.name, park.location,
                                   park.place + " " + park.location, park.grid, row[active]])
                }
                try database.runEach(
                    "INSERT OR REPLACE INTO park (reference, name, location, place, grid, active) VALUES (?, ?, ?, ?, ?, ?)",
                    values)
                try database.execute("INSERT INTO park_search(park_search) VALUES ('rebuild')")
                try database.run("INSERT INTO about (key, value) VALUES ('updated', ?)",
                                 [String(Date().timeIntervalSince1970)])
                count = values.count
            }
            guard count > 0 else { throw DatabaseError(message: "POTA's park list had no parks in it.") }
            // One file, without its write-ahead log beside it, to move.
            try database.execute("PRAGMA journal_mode = DELETE")
        }
        _ = try FileManager.default.replaceItemAt(target, withItemAt: building)
        for suffix in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: target.path + suffix) }
        return count
    }
}

// Reads CSV: fields separated by commas, rows by line breaks, and a field
// in double quotes may hold commas, line breaks and doubled quotes ("" for
// one "), as POTA's list does ("Il ""Quarto"" di Barbarano Romano").
enum CSV {
    static func rows(_ data: Data) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field: [UInt8] = []
        var quoted = false
        let bytes = [UInt8](data)
        var index = 0
        func endField() {
            row.append(String(decoding: field, as: UTF8.self))
            field.removeAll(keepingCapacity: true)
        }
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if quoted {
                if byte == UInt8(ascii: "\"") {
                    if index < bytes.count, bytes[index] == UInt8(ascii: "\"") {
                        field.append(byte)
                        index += 1
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(byte)
                }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""): quoted = true
            case UInt8(ascii: ","): endField()
            case UInt8(ascii: "\n"):
                endField()
                rows.append(row)
                row = []
            case UInt8(ascii: "\r"): break
            default: field.append(byte)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            endField()
            rows.append(row)
        }
        return rows
    }
}
