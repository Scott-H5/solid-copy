// Logbook.swift
//
// The list of logged contacts, and the one place that changes it.
//
// Every change is written to the log file (LogDatabase) first, and only
// then made to the list on screen. If saving fails, an error is thrown and
// nothing changes, so the screen never shows a contact that isn't saved.
//
// The form adds contacts and the log table deletes them. Both need to
// know when anything changes (to redraw the table and update the count),
// so they "observe" the logbook: they hand it a function to call after
// every change.

import Foundation

@MainActor
final class Logbook {
    // Oldest first, in the order they were logged.
    private(set) var contacts: [QSO]

    private let database: LogDatabase
    private var observers: [() -> Void] = []

    // Where the log file is, for File > Show Log in Finder.
    var fileURL: URL { database.fileURL }

    // Which log this is (LogList.swift). A test log never uploads: every
    // upload path checks isTest before sending anything.
    private(set) var info = LogInfo.main
    var isTest: Bool { info.isTest }

    // `info` says which log it is; the checks pass a test log's here, to
    // check uploads refuse it without touching any real folder.
    init(database: LogDatabase, info: LogInfo = .main) throws {
        self.database = database
        self.info = info
        contacts = try database.loadAll()
    }

    // Opens one of your logs (made if it's new), and backs it up first.
    static func open(_ log: LogInfo) throws -> Logbook {
        let file = LogList.fileURL(for: log, in: try LogList.baseFolder())
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let database = try LogDatabase(fileURL: file)
        // A backup each time the app opens, before anything can change.
        // Skipped while the log is empty: there's nothing to protect.
        if try database.count() > 0 {
            try database.backUp()
        }
        return try Logbook(database: database, info: log)
    }

    // Calls `onChange` after every change to the logbook.
    func observe(_ onChange: @escaping () -> Void) {
        observers.append(onChange)
    }

    func add(_ qso: QSO) throws {
        try database.insert(qso)
        contacts.append(qso)
        changed([qso.id])
    }

    // Removes a contact and returns it, so it can be put back by Undo.
    @discardableResult
    func remove(at index: Int) throws -> QSO {
        let qso = contacts[index]
        try database.delete(id: qso.id)
        contacts.remove(at: index)
        changed([qso.id])
        return qso
    }

    // Puts a contact back where it was (used by Undo).
    func insert(_ qso: QSO, at index: Int) throws {
        try database.insert(qso)
        contacts.insert(qso, at: min(index, contacts.count))
        changed([qso.id])
    }

    // Saves changes to a contact and returns the old version, so the
    // change can be undone. If the time changed, the contact moves to its
    // new place in time order.
    @discardableResult
    func update(_ qso: QSO) throws -> QSO {
        guard let index = index(of: qso.id) else {
            throw DatabaseError(message: "That contact is no longer in the log.")
        }
        let old = contacts[index]
        try database.update(qso)
        contacts[index] = qso
        if qso.timeOn != old.timeOn {
            sortByTime()
        }
        changed([qso.id])
        return old
    }

    // Saves changes to many contacts in one go (all or none), and returns
    // the old versions, for Undo. Their times don't change, so nothing
    // moves.
    @discardableResult
    func updateAll(_ updated: [QSO]) throws -> [QSO] {
        // One pass over the log finds them all (a big log, a big selection).
        let wanted = Set(updated.map(\.id))
        var places: [UUID: Int] = [:]
        for (index, qso) in contacts.enumerated() where wanted.contains(qso.id) { places[qso.id] = index }
        let indexes = updated.compactMap { places[$0.id] }
        guard indexes.count == updated.count else {
            throw DatabaseError(message: "A contact is no longer in the log.")
        }
        let old = indexes.map { contacts[$0] }
        try database.updateAll(updated)
        for (index, qso) in zip(indexes, updated) { contacts[index] = qso }
        changed(Set(updated.map(\.id)))
        return old
    }

    // Changes the latest version of each of these contacts, in one step
    // (all or none); ones no longer in the log are left out. For uploads,
    // which take a while: marking the copies they started with would undo
    // an edit made while they ran.
    func change(_ ids: Set<UUID>, _ edit: (inout QSO) -> Void) throws {
        guard !ids.isEmpty else { return }
        let updated = contacts.filter { ids.contains($0.id) }.map { qso -> QSO in
            var qso = qso
            edit(&qso)
            return qso
        }
        if !updated.isEmpty { try updateAll(updated) }
    }

    // Adds imported contacts, skipping any already in the log (the same
    // call at the same moment, to the second). Returns the contacts that
    // were added, so the import can be undone, and how many were skipped.
    //
    // Only contacts that were in the log *before* this import count as
    // "already in the log". So repeats within the imported file itself are
    // all kept, matching the original log, while importing the same file
    // twice adds nothing the second time.
    func importContacts(_ incoming: [QSO]) throws -> (added: [QSO], skipped: Int) {
        let existing = Set(contacts.map(Self.matchKey))
        let added = incoming.filter { !existing.contains(Self.matchKey($0)) }
        try database.insertAll(added)
        contacts += added
        sortByTime()
        changed(Set(added.map(\.id)))
        return (added, incoming.count - added.count)
    }

    // Puts back contacts that were deleted together (Undo), all of them,
    // even exact repeats, each in its place by time.
    func restoreAll(_ restored: [QSO]) throws {
        try database.insertAll(restored)
        contacts += restored
        sortByTime()
        changed(Set(restored.map(\.id)))
    }

    // Removes many contacts at once (deleting several, or undoing an import).
    func removeAll(ids: [UUID]) throws {
        try database.deleteAll(ids: ids)
        let removing = Set(ids)
        contacts.removeAll { removing.contains($0.id) }
        changed(removing)
    }

    // Makes a backup now (before an import, for example), if there's
    // anything to back up. Returns the new file, or nil for an empty log.
    @discardableResult
    func backUp() throws -> URL? {
        contacts.isEmpty ? nil : try database.backUp()
    }

    // The newest backup beside the log (the one made at launch), or nil.
    var newestBackup: URL? { database.newestBackup }

    private static func matchKey(_ qso: QSO) -> String {
        "\(qso.call)|\(Int(qso.timeOn.timeIntervalSince1970))"
    }

    // Sorts by time; contacts at the same moment keep their order.
    private func sortByTime() {
        contacts = contacts.enumerated()
            .sorted { ($0.element.timeOn, $0.offset) < ($1.element.timeOn, $1.offset) }
            .map(\.element)
    }

    func index(of id: UUID) -> Int? {
        contacts.firstIndex { $0.id == id }
    }

    // "1 contact" or "3 contacts".
    var countText: String {
        contacts.count == 1 ? "1 contact" : "\(contacts.count) contacts"
    }

    // The contacts touched by the latest change (added, edited or
    // removed), so observers can refresh just those (the log's search text,
    // for example) instead of everything.
    private(set) var lastChanged: Set<UUID> = []

    private func changed(_ ids: Set<UUID>) {
        lastChanged = ids
        observers.forEach { $0() }
    }
}
