// Database.swift
//
// A small, general wrapper around SQLite, the database engine built into
// every Mac. It knows nothing about ham radio; LogDatabase.swift uses it
// to store contacts.
//
// Why SQLite? It keeps the whole log in one file, it's very reliable (a
// contact written is a contact kept, even if the Mac loses power), and it's
// the same kind of file MacLoggerDX uses. Why no add-on library? SQLite's
// own interface is enough for what Solid Copy needs, and it means one less
// thing to keep up to date.
//
// SQLite's interface is written in C, so some of this looks unusual for
// Swift. Every value goes in and comes out as text, which is all the log
// needs (ADIF itself stores everything as text).

import Foundation
import SQLite3

// Tells SQLite to make its own copy of text we hand it. (A C constant that
// Swift can't see directly.)
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct DatabaseError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class Database {
    private var handle: OpaquePointer?

    // Opens the database file, creating it if it doesn't exist.
    init(url: URL) throws {
        try open(url.path, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, what: "the log")
        // WAL ("write-ahead log") mode: safer if the app or Mac stops
        // mid-write, and faster. "synchronous = FULL" waits for each write
        // to reach the disk before carrying on.
        try execute("PRAGMA journal_mode = WAL; PRAGMA synchronous = FULL;")
    }

    // Opens someone else's database (such as a MacLoggerDX log) strictly
    // for reading. "immutable" tells SQLite the file won't change while
    // it's open, so it never writes anything, not even its usual side
    // files (-wal, -journal). The original is never touched.
    init(readOnlyURL url: URL) throws {
        try open(url.absoluteString + "?immutable=1",
                 flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, what: url.lastPathComponent)
    }

    private func open(_ name: String, flags: Int32, what: String) throws {
        guard sqlite3_open_v2(name, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            handle = nil
            throw DatabaseError(message: "Couldn't open \(what): \(message)")
        }
        // If the file is briefly busy (a backup being written, say), wait
        // up to 3 seconds rather than failing at once.
        sqlite3_busy_timeout(handle, 3_000)
    }

    deinit {
        sqlite3_close(handle)
    }

    // Runs one or more SQL commands that take no values and return no rows.
    func execute(_ sql: String) throws {
        var errorText: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorText) == SQLITE_OK else {
            let message = errorText.map { String(cString: $0) } ?? lastError
            sqlite3_free(errorText)
            throw DatabaseError(message: message)
        }
    }

    // Runs one SQL command, filling each "?" in it with the next value.
    // Values are passed separately, never pasted into the SQL text, so a
    // comment containing a quote mark can't break the command.
    func run(_ sql: String, _ values: [String] = []) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw DatabaseError(message: lastError)
        }
    }

    // Runs one SQL command once for each row of values, preparing it only
    // once: much faster for many rows (the park list's 106,000). Use it
    // inside transaction(), so the rows are saved together.
    func runEach(_ sql: String, _ rows: [[String]]) throws {
        let statement = try prepare(sql, [])
        defer { sqlite3_finalize(statement) }
        for values in rows {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            for (index, value) in values.enumerated() {
                sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw DatabaseError(message: lastError) }
        }
    }

    // Runs a query and returns its rows. Each row maps column names to
    // their text (empty text for an empty value).
    func query(_ sql: String, _ values: [String] = []) throws -> [[String: String]] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var rows: [[String: String]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw DatabaseError(message: lastError) }
            var row: [String: String] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                let text = sqlite3_column_text(statement, column).map { String(cString: $0) }
                row[name] = text ?? ""
            }
            rows.append(row)
        }
        return rows
    }

    // Runs a query and hands over each row in turn, without building a
    // list of every row first, so a big log is read with little memory.
    // `body` gets the column names (the same each time) and a way to read
    // a column's text by its position (nil for an empty value).
    func forEachRow(_ sql: String, _ values: [String] = [],
                    _ body: (_ columns: [String], _ text: (Int32) -> String?) throws -> Void) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        let columns = (0..<sqlite3_column_count(statement)).map { String(cString: sqlite3_column_name(statement, $0)) }
        func text(_ column: Int32) -> String? {
            let length = Int(sqlite3_column_bytes(statement, column))
            guard length > 0, let bytes = sqlite3_column_text(statement, column) else { return nil }
            return String(decoding: UnsafeBufferPointer(start: bytes, count: length), as: UTF8.self)
        }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw DatabaseError(message: lastError) }
            try body(columns, text)
        }
    }

    // Runs `work` as one transaction: either every change in it is saved,
    // or (if anything fails) none is.
    func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try work()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    // A number stored inside the database file. LogDatabase uses it to
    // remember which version of the table layout the file has.
    var userVersion: Int {
        get throws {
            Int(try query("PRAGMA user_version").first?["user_version"] ?? "0") ?? 0
        }
    }

    private var lastError: String {
        String(cString: sqlite3_errmsg(handle))
    }

    private func prepare(_ sql: String, _ values: [String]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError(message: lastError)
        }
        for (index, value) in values.enumerated() {
            // SQLite counts the "?" places from 1, not 0.
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT)
        }
        return statement
    }
}
