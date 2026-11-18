// Logs.swift
//
// Your logs:
//   File > New Contest Log…  a log for one contest (Contest.swift), with
//                          that contest's profile (made from its
//                          template if you have none), which comes back
//                          whenever the log is opened.
//   File > New Log…        a named log, for a special event, a contest
//                          kept apart from rag chews, and so on.
//   File > New Test Log…   a log for trying things: layouts, a pretend
//                          contest. Nothing in it is ever uploaded, and
//                          its backups stay on this Mac.
//   File > Open Log ▸      every log, the one open ticked; choose one to
//                          switch to it.
//   File > Delete This Log…  moves the open log's folder to the Trash
//                          (after asking, with its count) and goes back to
//                          the main log. Any log but the main one; the
//                          Trash means even this can be undone. (Finder
//                          alone isn't enough: the log would stay on the
//                          list, and opening it would make it again, empty.)
// Switching says which log is now open and how many contacts it has, and
// the window title always names it. Each log remembers the profile last
// used with it (LogInfo.profileID); opening the log brings that profile
// back, with its form and CW messages, and says so.
//
// Before switching: the form must be empty (rule 20, a contact is never
// lost silently), no sheet open, contacts waiting for an automatic upload
// are sent, and the log being left is backed up if it changed. Then
// AppDelegate.install builds the form and table afresh for the new log.
//
// More of the AppDelegate class, like ImportExport.swift.

import AppKit

extension AppDelegate {

    // The Open Log submenu: every log, the open one ticked.
    func fillLogMenu() {
        logMenu.removeAllItems()
        let open = logbook?.info.id
        for (index, log) in LogList.all.enumerated() {
            let item = logMenu.addItem(withTitle: log.title, action: #selector(chooseLog(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = log.id == open ? .on : .off
        }
    }

    @objc func newLog(_ sender: Any?) {
        askForName(title: "New Log",
                   explanation: "A log of its own, for a special event, a contest kept apart from everyday "
                       + "contacts, and so on. It uploads like your main log.",
                   suggestion: "", isTest: false)
    }

    // A log for one contest (Contest.swift): its name and which contest.
    // It comes with the contest's profile (made from its template if you
    // haven't one), which opens with it.
    @objc func newContestLog(_ sender: Any?) {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "New Contest Log"
        alert.informativeText = "A log for one contest, with that contest's profile: its form and CW messages. "
            + "Contests come from the files in File > Contests > Show Contest Files; for one without a file, use a profile "
            + "you've built for it."
        let field = NSTextField(string: "")
        field.placeholderString = "Name, such as Field Day 2027"
        field.setAccessibilityLabel("Name")
        // The contest files, then "use a profile" for a contest with no
        // file: any profile you've built for it.
        let loaded = ContestList.load()
        let profiles = Settings.profiles
        let menu = NSPopUpButton()
        menu.addItems(withTitles: loaded.contests.map(\.name))
        menu.addItems(withTitles: profiles.map { "Other: use the \($0.name) profile" })
        menu.setAccessibilityLabel("Contest")
        if !loaded.problems.isEmpty {
            alert.informativeText += " Some contest files couldn't be used: " + loaded.problems.joined(separator: " ")
        }
        let stack = NSStackView(views: [field, menu])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: 56)
        field.widthAnchor.constraint(equalToConstant: 280).isActive = true
        field.nextKeyView = menu
        menu.nextKeyView = field
        alert.accessoryView = stack
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let index = menu.indexOfSelectedItem
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            let log: LogInfo
            if loaded.contests.indices.contains(index) {
                let contest = loaded.contests[index]
                log = LogList.add(name: name.isEmpty ? contest.name : name, isTest: false, contest: contest.id)
                LogList.setProfile(Settings.profile(for: contest), for: log.id)
            } else if profiles.indices.contains(index - loaded.contests.count) {
                // A contest with no file: the profile's Contest field says
                // which (if it has one); dupes are once per band and mode.
                let profile = profiles[index - loaded.contests.count]
                let id = profile.formFields.first { $0.adif == "contest_id" }?.startingValue
                    .trimmingCharacters(in: .whitespaces).uppercased() ?? ""
                log = LogList.add(name: name.isEmpty ? profile.name : name, isTest: false,
                                  contest: id.isEmpty ? "CONTEST" : id)
                LogList.setProfile(profile.id, for: log.id)
            } else { return }
            self?.fillLogMenu()
            // After the sheet has gone (see askForName).
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.switchTo(log) } }
        }
    }

    // File > Contests > Show Contest Files: the Contests folder in the Finder, to
    // edit a contest or add one (Contest.swift).
    @objc func showContestFiles(_ sender: Any?) {
        guard let base = try? LogList.baseFolder() else { return }
        let folder = ContestList.folder(in: base)
        _ = ContestList.load()   // makes it, with Field Day's file, if new
        NSWorkspace.shared.activateFileViewerSelecting([folder.appendingPathComponent("README.txt")])
    }

    // File > Save Profile as Contest…: the profile in use written as a
    // contest file in the Contests folder, so a contest set up by hand can
    // be kept, shared, or used for File > New Contest Log….
    @objc func saveProfileAsContest(_ sender: Any?) {
        let profile = Settings.currentProfile
        let given = profile.formFields.first { $0.adif == "contest_id" }?.startingValue
            .trimmingCharacters(in: .whitespaces).uppercased() ?? ""
        let id = given.isEmpty
            ? String(profile.name.uppercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }.prefix(32)) : given
        let skip: Set<String> = ["contest_id", "stx", "srx", "stx_string", "rst_sent"]
        let exchange = profile.formFields.filter { $0.tabStop && !skip.contains($0.adif) }.map(\.adif)
        let contest = Contest(id: id, name: profile.name, exchange: exchange.isEmpty ? ["srx_string"] : exchange,
                              serial: profile.formFields.contains { $0.adif == "stx" }, dupes: .bandAndMode,
                              messages: Settings.cwMessages, submit: .none)
        guard let base = try? LogList.baseFolder() else { return }
        let folder = ContestList.folder(in: base)
        _ = ContestList.load()
        let safeName = profile.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let file = folder.appendingPathComponent("\(safeName).txt")
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.trashItem(at: file, resultingItemURL: nil)
            }
            try Data(contest.fileText.utf8).write(to: file, options: .atomic)
            Speaker.announce("Saved as a contest: \(safeName).txt, in the Contests folder. It's offered in "
                             + "New Contest Log now.")
        } catch {
            Speaker.Cue.warning.play()
            Speaker.announce("Couldn't save the contest file. \(error.localizedDescription)")
        }
    }

    @objc func newTestLog(_ sender: Any?) {
        askForName(title: "New Test Log",
                   explanation: "For trying layouts, simulating a contest and so on. Nothing in a test log is "
                       + "ever uploaded, and its backups stay on this Mac.",
                   suggestion: "Test log", isTest: true)
    }

    // A small window asking for the name, with Create and Cancel. Focus
    // starts in the name; Return creates, Escape cancels.
    private func askForName(title: String, explanation: String, suggestion: String, isTest: Bool) {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = explanation
        let field = NSTextField(string: suggestion)
        field.placeholderString = "Name"
        field.setAccessibilityLabel("Name")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let log = LogList.add(name: field.stringValue, isTest: isTest)
            self?.fillLogMenu()
            // The sheet is still attached while this runs, and switching
            // refuses while a sheet is open; so switch a moment later,
            // once it's gone. (Found by the author, 17 November 2026: new logs
            // were made but never opened.)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.switchTo(log) } }
        }
    }

    @objc func chooseLog(_ sender: NSMenuItem) {
        let logs = LogList.all
        guard logs.indices.contains(sender.tag) else { return }
        switchTo(logs[sender.tag])
    }

    // Switches to a log (made on disk if it's new). Says why not if it
    // can't yet. `then` runs only once the new log is open.
    func switchTo(_ log: LogInfo, then: (() -> Void)? = nil) {
        guard log.id != logbook?.info.id else { return Speaker.announce("\(log.title) is already open.") }
        // A sheet still on screen (Edit Contact, say). One just dismissed
        // can still be attached for a moment but is no longer visible.
        guard window?.attachedSheet?.isVisible != true else {
            return Speaker.announce("Close the sheet that's open first.")
        }
        if let call = logEntry?.callsignField.stringValue, !call.trimmingCharacters(in: .whitespaces).isEmpty {
            NSSound.beep()
            return Speaker.announce("The form has a contact. Log it, or clear it with Escape, then switch logs.")
        }
        Task { [weak self] in
            await AutoUploader.shared.sendWaitingNow()
            guard let self else { return }
            self.backUpAtQuit()
            let opened: Logbook
            do {
                opened = try Logbook.open(log)
            } catch {
                Speaker.Cue.warning.play()
                return Speaker.announce("\(log.title) couldn't be opened, so this log stays open. "
                                        + error.localizedDescription)
            }
            LogList.use(log)
            self.install(opened)
            // The profile last used with this log comes back with it. After
            // install, so the log that remembers it is the new one.
            var profileWords = ""
            if let id = LogList.all.first(where: { $0.id == log.id })?.profileID, id != Settings.currentProfile.id,
               let profile = Settings.profiles.first(where: { $0.id == id }) {
                Settings.useProfile(id)
                profileWords = " \(profile.name) profile."
            }
            // A new log takes the profile in use as its own.
            LogList.setProfile(Settings.currentProfile.id, for: log.id)
            self.window?.makeKeyAndOrderFront(nil)
            self.logEntry?.focusCallsign()
            let count = opened.contacts.count
            let contacts = count == 1 ? "1 contact" : "\(count.formatted()) contacts"
            Speaker.announce("\(log.title) open, \(contacts)." + profileWords
                             + (log.isTest ? " Nothing in it is uploaded." : ""))
            then?()
        }
    }

    // Deletes the open log (any but the main one): asks, goes back to the
    // main log, then moves the log's folder to the Trash (so even this can
    // be undone from the Finder).
    @objc func deleteLog(_ sender: Any?) {
        guard let window, window.attachedSheet == nil, let logbook else { return }
        let info = logbook.info
        guard !info.isMain else {
            NSSound.beep()
            return Speaker.announce("The main log can't be deleted.")
        }
        let count = logbook.contacts.count
        let contacts = count == 1 ? "its 1 contact" : "its \(count.formatted()) contacts"
        let alert = NSAlert()
        alert.messageText = "Delete \(info.title)?"
        alert.informativeText = "The log, \(contacts), its backups and its cards go to the Trash, and the main log "
            + "opens." + (info.isTest ? "" : " Anything already uploaded stays on LoTW and QRZ, and copies in "
            + "your backup folder are kept.")
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            guard let base = try? LogList.baseFolder() else { return }
            // Worked out from the log list, not the open file, and only
            // ever a folder under Logs: never the main log's folder.
            let folder = LogList.fileURL(for: info, in: base).deletingLastPathComponent()
            guard folder.deletingLastPathComponent().lastPathComponent == "Logs" else { return }
            // Only once the main log is open (a refused switch, say with a
            // contact in the form, deletes nothing). A moment later, once
            // this sheet has gone (see askForName).
            DispatchQueue.main.async { MainActor.assumeIsolated { self.switchTo(.main) {
                LogList.remove(info)
                do {
                    try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
                    Speaker.announce("\(info.name) moved to the Trash.")
                } catch {
                    Speaker.announce("\(info.name) is off the list, but its folder couldn't be moved to the Trash. "
                                     + error.localizedDescription)
                }
                self.fillLogMenu()
            } } }
        }
    }

}

// Delete This Log is on offer for any log but the main one; every other
// item of the app delegate's is always on.
extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        item.action == #selector(deleteLog(_:)) ? logbook?.info.isMain == false : true
    }
}
