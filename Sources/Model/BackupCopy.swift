// BackupCopy.swift
//
// Copies a backup of the log, and the scanned QSL cards, to a second
// folder you choose (Settings > Backups), such as one in iCloud Drive, so
// a copy survives losing this Mac. Solid Copy's own backups (LogDatabase,
// the newest 20 beside the log) stay where they are; this is the copy
// somewhere else.
//
// In the folder:
//   Solid Copy log 2026-11-16 143205Z.sqlite   the newest 20 are kept
//   QSL Cards/                                 every scanned card
// A log backup is a complete SQLite file: File > Import… in Solid Copy
// can't read it yet, but copying it over Logbook.sqlite (with Solid Copy
// quit) restores the log, and any SQLite tool can read it.
//
// Cards are copied only when new (same name, same size already there is
// skipped), so a big card collection costs time once. Cards are never
// deleted from the backup folder, even if deleted from the log: a backup
// should keep things.
//
// File work only (no settings, no windows), so tools/check-backups.sh can
// check it in a temporary folder.

import Foundation

enum BackupCopy {
    static let prefix = "Solid Copy log "
    static let keep = 20

    struct Result: Equatable {
        var logFile: String   // the name written in the folder
        var cardsCopied: Int
    }

    // Copies `backup` (one of LogDatabase's backups, named "Logbook
    // <date>.sqlite") into `folder` as "Solid Copy log <date>.sqlite",
    // drops all but the newest `keep` there, and copies new cards from
    // `cards` (if it exists) into folder/QSL Cards.
    static func copy(_ backup: URL, cards: URL?, to folder: URL, keep: Int = keep) throws -> Result {
        let files = FileManager.default
        let date = backup.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "Logbook ", with: "")
        let name = prefix + date + ".sqlite"
        let target = folder.appendingPathComponent(name)
        // Written beside the target first, then moved into place, so a
        // copy cut short (a full disk, iCloud busy) never looks complete.
        let partial = folder.appendingPathComponent(".\(name).partial")
        try? files.removeItem(at: partial)
        try files.copyItem(at: backup, to: partial)
        if files.fileExists(atPath: target.path) { try files.removeItem(at: target) }
        try files.moveItem(at: partial, to: target)
        try prune(folder, keep: keep)
        return Result(logFile: name, cardsCopied: try copyCards(from: cards, to: folder))
    }

    // The names start with the date, so sorting by name sorts by age.
    private static func prune(_ folder: URL, keep: Int) throws {
        let logs = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in logs.dropFirst(keep) { try FileManager.default.removeItem(at: old) }
    }

    private static func copyCards(from cards: URL?, to folder: URL) throws -> Int {
        let files = FileManager.default
        guard let cards, files.fileExists(atPath: cards.path) else { return 0 }
        let target = folder.appendingPathComponent("QSL Cards", isDirectory: true)
        try files.createDirectory(at: target, withIntermediateDirectories: true)
        var copied = 0
        for card in try files.contentsOfDirectory(at: cards, includingPropertiesForKeys: [.fileSizeKey])
        where !card.lastPathComponent.hasPrefix(".") {
            let destination = target.appendingPathComponent(card.lastPathComponent)
            let size = { (url: URL) in (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize }
            if files.fileExists(atPath: destination.path), size(destination) == size(card) { continue }
            try? files.removeItem(at: destination)
            try files.copyItem(at: card, to: destination)
            copied += 1
        }
        return copied
    }
}
