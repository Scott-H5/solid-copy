// ClubLists.swift
//
// A member list from a file you have, for one of your own club fields
// (Settings > Clubs): a CSV of call and number, such as a club roster
// saved as CSV. Solid Copy keeps its own copy in Application Support (as
// it does SKCC's list), so the list survives the file being moved or
// deleted. ClubNumbers.swift uses it to fill in the field when you leave
// Callsign: the list is the authority, so its number wins over the one
// in your log, as SKCC's does.
//
// The file: one member per line, call first, then a comma and the number.
// A header line ("call,number") is skipped, because its first word isn't
// a call. Extra columns and quote marks are ignored. Up to 2 MB.

import Foundation

@MainActor
enum ClubLists {
    static let maximumBytes = 2 * 1024 * 1024
    // Each slot's members, read from disk once and then kept.
    private static var cache: [Int: [String: String]] = [:]

    // The members in a CSV text: call (as lookups match it) -> number.
    static func parse(_ text: String) -> [String: String] {
        var members: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let columns = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"")) }
            guard columns.count >= 2, !columns[0].isEmpty, !columns[1].isEmpty else { continue }
            let call = Callsign.normalized(columns[0])
            // A header such as "call" isn't a callsign, so it's skipped.
            guard Callsign.looksValid(call) else { continue }
            members[CallsignLookup.lookupCall(for: call)] = columns[1]
        }
        return members
    }

    // Copies a chosen file in as the list for a club field, and returns how
    // many members it has. A file that isn't a member list is refused, and
    // the old copy (if any) is kept.
    static func use(slot: Int, from source: URL) throws -> Int {
        guard let target = fileURL(slot) else {
            throw DatabaseError(message: "Solid Copy couldn't find a place to keep the list.")
        }
        let data = try Data(contentsOf: source)
        guard data.count <= maximumBytes, let text = String(data: data, encoding: .utf8) else {
            throw DatabaseError(message: "The file is too big, or isn't plain text.")
        }
        let members = parse(text)
        guard !members.isEmpty else {
            throw DatabaseError(message: "No members found. Each line needs a call, a comma, then the number.")
        }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
        cache[slot] = members
        return members.count
    }

    // Forgets the list for a club field.
    static func remove(slot: Int) {
        if let url = fileURL(slot) { try? FileManager.default.removeItem(at: url) }
        cache[slot] = nil
    }

    // How many members the list for a slot has, or nil if there's none.
    static func count(slot: Int) -> Int? { members(slot)?.count }

    // The number for a call (already matched as lookups do), if the list has it.
    static func number(slot: Int, for key: String) -> String? { members(slot)?[key] }

    // Every member on the list for a slot (call -> number), or nil if
    // there's no list: the club awards' Still needed (ClubAwards.swift).
    static func members(_ slot: Int) -> [String: String]? {
        if let cached = cache[slot] { return cached }
        guard let url = fileURL(slot), let data = try? Data(contentsOf: url), data.count <= maximumBytes,
              let text = String(data: data, encoding: .utf8) else { return nil }
        let loaded = parse(text)
        cache[slot] = loaded
        return loaded
    }

    private static func fileURL(_ slot: Int) -> URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Solid Copy", isDirectory: true)
            .appendingPathComponent("Club lists", isDirectory: true)
            .appendingPathComponent("club\(slot).csv")
    }
}
