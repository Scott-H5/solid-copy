// LogList.swift
//
// Your logs: the main log, and any others you
// make with File > New Log… or New Test Log…, for a special event, a
// contest kept apart from rag chews, or trying things out.
//
// Where each one lives, inside Solid Copy's Application Support folder:
//   the main log:  Solid Copy/Logbook.sqlite       (where it always was)
//   other logs:    Solid Copy/Logs/<id>/Logbook.sqlite
// Each log's backups and scanned cards sit beside its file (Backups,
// QSL Cards), so every log has its own. The main log isn't moved: its
// file, backups and cards stay exactly where they were before there was
// more than one log. Other logs' folders are named by a fixed ID, not the
// name you give, so a name can be anything and renaming moves nothing.
//
// A test log is marked when it's made and stays a test log. Nothing in
// one is ever uploaded (every upload path checks Logbook.isTest), and its
// backups aren't copied to your backup folder.
//
// The list itself is kept with the other settings (user defaults, key
// "logs"), with the log in use (key "currentLog"). Foundation only, so
// tools/check-logs.sh can check it.

import Foundation

struct LogInfo: Codable, Equatable {
    var id: UUID
    var name: String
    var isTest: Bool
    var created: Date
    // The profile last used with this log, so opening it brings that
    // profile back (a Field Day log, its Field Day profile and messages).
    // Nil until a profile has been used with it.
    var profileID: UUID?
    // For a contest log (File > New Contest Log…): the contest's ADIF ID
    // ("ARRL-FIELD-DAY"; Contest.swift). Nil for any other log.
    var contest: String?

    // The main log's ID never changes, so it can always be found.
    static let mainID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let main = LogInfo(id: mainID, name: "Main log", isTest: false, created: .distantPast)
    var isMain: Bool { id == Self.mainID }

    // "Main log", or "Contest practice (test log)", for menus and speech.
    var title: String { isTest ? "\(name) (test log)" : name }
}

enum LogList {
    private static let listKey = "logs"
    private static let currentKey = "currentLog"
    // The checks use a settings domain of their own.
    static var defaults = UserDefaults.standard

    // Every log, the main one first, then the others in the order made.
    static var all: [LogInfo] {
        let saved = defaults.data(forKey: listKey).flatMap { try? JSONDecoder().decode([LogInfo].self, from: $0) } ?? []
        return [saved.first(where: \.isMain) ?? .main] + saved.filter { !$0.isMain }
    }

    private static func save(_ logs: [LogInfo]) {
        defaults.set(try? JSONEncoder().encode(logs), forKey: listKey)
    }

    // The log in use: the one chosen last, or the main log.
    static var current: LogInfo {
        let id = defaults.string(forKey: currentKey).flatMap(UUID.init(uuidString:))
        return all.first { $0.id == id } ?? .main
    }

    static func use(_ log: LogInfo) {
        defaults.set(log.id.uuidString, forKey: currentKey)
    }

    // Adds a log to the list (its file is made when it's first opened).
    // An empty name gets one; a name already used gets " 2", " 3" ...
    @discardableResult
    static func add(name: String, isTest: Bool, contest: String? = nil, now: Date = Date()) -> LogInfo {
        var base = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        if base.isEmpty { base = isTest ? "Test log" : "New log" }
        let taken = Set(all.map { $0.name.lowercased() })
        var unique = base, number = 2
        while taken.contains(unique.lowercased()) {
            unique = "\(base) \(number)"
            number += 1
        }
        let log = LogInfo(id: UUID(), name: unique, isTest: isTest, created: now, contest: contest)
        save(all + [log])
        return log
    }

    // Remembers the profile used with a log.
    static func setProfile(_ profileID: UUID, for logID: UUID) {
        var logs = all
        guard let index = logs.firstIndex(where: { $0.id == logID }), logs[index].profileID != profileID else { return }
        logs[index].profileID = profileID
        save(logs)
    }

    // Takes a log off the list (its folder is dealt with by the caller).
    // The main log can't be removed.
    static func remove(_ log: LogInfo) {
        guard !log.isMain else { return }
        save(all.filter { $0.id != log.id })
        if current.id == log.id { use(.main) }
    }

    // Where a log's file is, given Solid Copy's Application Support folder.
    static func fileURL(for log: LogInfo, in base: URL) -> URL {
        let folder = log.isMain ? base : base.appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(log.id.uuidString, isDirectory: true)
        return folder.appendingPathComponent("Logbook.sqlite")
    }

    // Solid Copy's own folder: Application Support/Solid Copy.
    static func baseFolder() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Solid Copy", isDirectory: true)
    }
}
