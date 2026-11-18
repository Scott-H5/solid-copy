// BackupFolder.swift
//
// The second folder backups are copied to (Settings > Backups), kept as a
// security-scoped bookmark because the App Sandbox only lets Solid Copy
// write to a folder you chose, and the copying (BackupCopy.swift) run off
// the main thread. When copies are made is in Sources/App/Backups.swift.
// Here, not in Sources/App, so the check tools that build Settings can
// build this too.

import AppKit

@MainActor
enum Backups {
    // The chosen folder, opened for use, or nil if none (or it's gone).
    static func folder() -> URL? {
        guard let bookmark = Settings.backupFolderBookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope) { Settings.backupFolderBookmark = fresh }
        return url
    }

    static func setFolder(_ url: URL?) throws {
        Settings.backupFolderBookmark = try url?.bookmarkData(options: .withSecurityScope)
    }

    // The folder's name for Settings, without opening it.
    static var folderName: String? {
        guard let bookmark = Settings.backupFolderBookmark else { return nil }
        var stale = false
        return (try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                         relativeTo: nil, bookmarkDataIsStale: &stale))?.path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    // Copies `backup` and the cards to the folder. Returns words saying
    // how it went, and whether it worked. With no folder chosen, nil.
    // `inBackground` keeps a big copy off the main thread (launch, Back
    // Up Now); at quit it runs straight through, since the app is ending.
    @discardableResult
    static func copy(_ backup: URL, logbook: Logbook, inBackground: Bool = true,
                     done: ((String, Bool) -> Void)? = nil) -> Bool {
        // Test logs stay on this Mac: their backups aren't copied out.
        guard Settings.backupFolderBookmark != nil, !logbook.isTest else { return false }
        guard let folder = folder() else {
            report("The backup folder couldn't be opened. Choose it again in Settings > Backups.", ok: false,
                   done: done)
            return true
        }
        let cards = QSLCards(logFile: logbook.fileURL).folder
        let work = { () -> (String, Bool) in
            defer { folder.stopAccessingSecurityScopedResource() }
            do {
                // The main log's copies go in the folder itself, as they
                // always have; another log's in a folder of its own, named
                // after it, so each keeps its own newest 20.
                let name = logbook.info.name.replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ":", with: "-")
                let target = logbook.info.isMain ? folder : folder.appendingPathComponent(name, isDirectory: true)
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                let result = try BackupCopy.copy(backup, cards: cards, to: target)
                let extra = result.cardsCopied == 0 ? "" : " and \(result.cardsCopied) new card"
                    + (result.cardsCopied == 1 ? "" : "s")
                return ("Backed up to \(folder.lastPathComponent)\(extra).", true)
            } catch {
                return ("The backup copy didn't work. \(error.localizedDescription)", false)
            }
        }
        if inBackground {
            Task {
                let (words, ok) = await Task.detached(operation: work).value
                report(words, ok: ok, done: done)
            }
        } else {
            let (words, ok) = work()
            report(words, ok: ok, done: done)
        }
        return true
    }

    // Remembers how it went; a problem is said (or kept for next launch
    // by the caller at quit).
    private static func report(_ words: String, ok: Bool, done: ((String, Bool) -> Void)?) {
        if ok {
            Settings.backupLast = Date()
            Settings.backupProblem = ""
        }
        if let done { return done(words, ok) }
        if !ok {
            Speaker.Cue.warning.play()
            Speaker.announce(words)
        }
    }
}
