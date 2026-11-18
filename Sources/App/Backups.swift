// Backups.swift
//
// Copies of the log in a second folder you choose (Settings > Backups),
// such as one in iCloud Drive (BackupCopy.swift does the copying):
//   - when Solid Copy opens: the backup it has just made beside the log;
//   - when it quits, if the log changed: a fresh backup, so the day's
//     contacts are safe even if the Mac isn't opened again;
//   - File > Back Up Now (no shortcut), whenever you like.
// Silent when it works. A problem is said with the warning sound; one at
// quit (when nobody's listening) is said at the next launch.
//
// The folder and the copying are in Sources/Settings/BackupFolder.swift.
//
// More of the AppDelegate class, like ImportExport.swift.

import AppKit

extension AppDelegate {
    // At launch: say a problem kept from the last quit, then copy the
    // backup made on opening.
    func backUpAtLaunch() {
        guard let logbook else { return }
        let problem = Settings.backupProblem
        if !problem.isEmpty {
            Speaker.Cue.warning.play()
            Speaker.announce("When Solid Copy last quit: " + problem)
            Settings.backupProblem = ""
        }
        if let backup = logbook.newestBackup { Backups.copy(backup, logbook: logbook) }
    }

    // At quit, if the log changed since opening: a fresh backup, copied
    // straight away. A problem (a failed check included) is kept to say next time.
    func backUpAtQuit() {
        guard let logbook, logChangedSinceBackup else { return }
        let backup: URL
        do {
            guard let made = try logbook.backUp() else { return }
            backup = made
        } catch {
            Settings.backupProblem = error.localizedDescription
            return
        }
        markBackedUp()
        Backups.copy(backup, logbook: logbook, inBackground: false) { words, ok in
            if !ok { Settings.backupProblem = words }
        }
    }

    // The schedule: checked every ten minutes (cheap: a date and a flag),
    // so a new choice in Settings takes effect without restarting it.
    // Silent, like the launch copy; a problem is said.
    func startBackupSchedule() {
        backupTimer?.invalidate()
        let timer = Timer(timeInterval: 600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.backUpIfDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        backupTimer = timer
    }

    func backUpIfDue(now: Date = Date()) {
        let hours = Settings.backupEveryHours
        guard hours > 0, logChangedSinceBackup, let logbook,
              now.timeIntervalSince(lastBackupAt) >= Double(hours) * 3600 else { return }
        do {
            guard let backup = try logbook.backUp() else { return }
            markBackedUp(now)
            Backups.copy(backup, logbook: logbook)
        } catch {
            Speaker.Cue.warning.play()
            Speaker.announce("The scheduled backup didn't work. \(error.localizedDescription)")
        }
    }

    // A backup was made: the schedule counts from now.
    private func markBackedUp(_ when: Date = Date()) {
        logChangedSinceBackup = false
        lastBackupAt = when
    }

    // File > Back Up Now: a fresh backup beside the log, copied to the
    // folder if there is one; how it went is said either way.
    @objc func backUpNow(_ sender: Any?) {
        guard let logbook else { return }
        do {
            guard let backup = try logbook.backUp() else { return Speaker.announce("The log is empty: nothing to back up.") }
            markBackedUp()
            let copying = Backups.copy(backup, logbook: logbook) { words, ok in
                if !ok { Speaker.Cue.warning.play() }
                Speaker.announce(words)
            }
            if !copying {
                Speaker.announce("Backed up beside the log. To keep a copy somewhere else too, "
                                 + "choose a folder in Settings > Backups.")
            }
        } catch {
            Speaker.Cue.warning.play()
            Speaker.announce("The backup didn't work. \(error.localizedDescription)")
        }
    }
}
