// AppDelegate.swift
//
// macOS tells the AppDelegate about app-wide events, such as "the app
// has finished launching." When it launches, this opens the log file
// (backing it up first), builds the menu bar, and opens the logging
// window with focus in the Callsign field (accessibility contract, rule 1).

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Not private: ImportExport.swift (more of this class, in its own
    // file) uses them too.
    var logbook: Logbook?
    // Whether the log changed since the last backup (launch, schedule or
    // Back Up Now), and when that was, for the schedule and quitting
    // (Backups.swift).
    var logChangedSinceBackup = false
    var lastBackupAt = Date()
    var backupTimer: Timer?
    var window: NSWindow?
    // The logging window's delegate: gives the form's fields a field
    // editor that won't paste contacts into them (FormTextField.swift).
    private let fieldEditorProvider = FormFieldEditor.Provider()
    var logEntry: LogEntryViewController?
    var settingsWindow: SettingsWindowController?
    var spotsWindow: SpotsWindowController?
    // Window > Activity (Command-2), made the first time (ActivityWindowController.swift).
    var activityWindow: ActivityWindowController?
    // Window > Log (Command-3), made the first time (LogBrowserWindowController.swift).
    var logBrowser: LogBrowserWindowController?

    // The Profile menu: one item per profile (Option-Command-1 to 9), the
    // one in use ticked, and Edit Profiles. Refilled when profiles change.
    let profileMenu = NSMenu(title: "Profile")
    // File > Open Log: your logs (Logs.swift). Refilled when they change.
    let logMenu = NSMenu(title: "Open Log")
    // The CW menu (CW.swift): WinKeyer, messages F1 to F8.
    let cwMenu = NSMenu(title: "CW")

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()

        // The log in use when Solid Copy last quit (LogList.swift). If it
        // won't open, the main log is tried before giving up, so a broken
        // test log can't lock you out of your real one.
        var opened = try? Logbook.open(LogList.current)
        if opened == nil, !LogList.current.isMain {
            LogList.use(.main)
            opened = try? Logbook.open(.main)
        }
        let logbook: Logbook
        do {
            logbook = try opened ?? Logbook.open(.main)
        } catch {
            // Without its log the app can't do anything useful, and
            // carrying on could make things worse, so say why and quit.
            let alert = NSAlert()
            alert.messageText = "Solid Copy couldn't open its log."
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        // SKCC's member list: read the copy, fetch a new one if it's old.
        SKCCRoster.shared.start()
        // cty.dat, for each call's country and "needed" (fetched if it's
        // missing or a month old).
        Countries.shared.fetchIfNeeded()
        install(logbook)
        LogList.setProfile(Settings.currentProfile.id, for: logbook.info.id)
        startBackupSchedule()

        updateTitle()
        // Start connecting to the profile's radio, if it has one.
        // Start connecting to the radio in use, if there is one. (This is
        // also the first read of the radio list, which moves radios saved
        // in profiles by an earlier version into the list.)
        RadioMonitor.shared.use(Settings.currentRadio)
        fillRadioMenu()
        // POTA's park list, if you have one and it's a month old.
        ParkList.shared.updateIfStale()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        logEntry?.focusCallsign()

        // The CW menu's Connect / Disconnect follows the WinKeyer.
        NotificationCenter.default.addObserver(forName: WinKeyer.didChange, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.fillCWMenu() } }
        }

        // Keep the menu and title in step with Settings.
        NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateTitle()
                // The radio in use (nothing happens if it's the same).
                RadioMonitor.shared.use(Settings.currentRadio)
                // The log in use remembers the profile in use (Logs.swift).
                if let log = self?.logbook?.info { LogList.setProfile(Settings.currentProfile.id, for: log.id) }
                // A new CW speed from Settings > CW.
                if WinKeyer.shared.isConnected { WinKeyer.shared.setSpeed(Settings.cwSpeed) }
            }
            // The menu is refilled a moment later, not now: choosing a
            // profile from this very menu lands here, and throwing away a
            // menu item while macOS is still handling it is asking for a
            // crash.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.fillProfileMenu()
                    self?.fillRadioMenu()
                    self?.fillCWMenu()
                }
            }
        }
    }

    // Puts a log in use: at launch, and when you switch logs (Logs.swift).
    // Everything tied to one log is made fresh for it: the form and log
    // table, the menus that point at them, uploads and the backup
    // schedule's "changed" flag. At launch it also makes the window; when
    // switching, the window stays where it is and gets the new contents.
    func install(_ logbook: Logbook) {
        self.logbook = logbook
        LoTWSync.repairFalseUploads(logbook)
        // Copy the backup made on opening to your backup folder, if you
        // chose one; note changes, for a fresh one at quit (Backups.swift).
        logChangedSinceBackup = false
        lastBackupAt = Date()
        logbook.observe { [weak self] in self?.logChangedSinceBackup = true }
        backUpAtLaunch()
        AutoUploader.shared.logbook = logbook

        // Switching logs: the same form and table take the new log, so the
        // window's views (and the menus pointing at them) stay as they are.
        if let logEntry, window != nil {
            logEntry.use(logbook)
            logBrowser?.use(logbook)
            fillLogMenu()
            spotsWindow?.close()
            spotsWindow = nil
            updateTitle()
            return
        }

        // At launch: the logging form and log table.
        let logEntry = LogEntryViewController(logbook: logbook)
        self.logEntry = logEntry
        // Uploads: new contacts to AutoUploader, and the log's shortcut
        // menu to UploadCommands.swift.
        logEntry.onLogged = { AutoUploader.shared.logged($0) }
        logEntry.logTable.onUpload = { [weak self] service, contacts in self?.upload(contacts, to: service) }
        NSApp.mainMenu = MainMenu.build(logEntry: logEntry, appDelegate: self)
        fillProfileMenu()
        fillLogMenu()
        fillCWMenu()
        // The Spots window counts what's needed against the log, so it's
        // made again for the new one when next opened.
        spotsWindow?.close()
        spotsWindow = nil


        // Creating the window with the view controller also builds the
        // form's fields.
        let window = NSWindow(contentViewController: logEntry)
        window.title = "Solid Copy"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 980, height: 820))
        window.center()
        // Remember where you put the window, between launches. The name
        // changes when the window gains a part (the log table, then the
        // details panel), so an old, smaller saved size isn't used.
        window.setFrameAutosaveName("MainWindowWithDetails")
        // The field that gets focus when the window first opens.
        window.initialFirstResponder = logEntry.callsignField
        // Closing the window only hides it, so Window > Logging Window
        // (Command-0) can bring it back as it was, typing and all.
        window.isReleasedWhenClosed = false
        window.delegate = fieldEditorProvider
        fieldEditorProvider.pasteContacts = { [weak self] in self?.logEntry?.logTable.pasteContacts() }
        self.window = window
    }

    // MARK: - Profiles

    // "Solid Copy, Main log, Portable": VoiceOver reads the title when you
    // come to the window, so the profile in use is always findable.
    // With the log in use too ("Solid Copy, Contest practice (test log),
    // Home"), so which log you're in is always findable (CLAUDE.md #12).
    func updateTitle() {
        window?.title = "Solid Copy, \(logbook?.info.title ?? "Main log"), \(Settings.currentProfile.name)"
    }

    private func fillProfileMenu() {
        profileMenu.removeAllItems()
        let current = Settings.currentProfile.id
        for (index, profile) in Settings.profiles.enumerated() {
            let item = profileMenu.addItem(withTitle: profile.name, action: #selector(chooseProfile(_:)),
                                           keyEquivalent: index < 9 ? "\(index + 1)" : "")
            item.keyEquivalentModifierMask = [.command, .option]
            item.target = self
            item.tag = index
            item.state = profile.id == current ? .on : .off
        }
        profileMenu.addItem(.separator())
        let edit = profileMenu.addItem(withTitle: "Edit Profiles…", action: #selector(editProfiles(_:)),
                                       keyEquivalent: "")
        edit.target = self
    }

    // Profile > (a profile): switches to it. The form changes at once,
    // keeping anything already typed in fields both profiles share.
    @objc func chooseProfile(_ sender: NSMenuItem) {
        let profiles = Settings.profiles
        guard profiles.indices.contains(sender.tag) else { return }
        let chosen = profiles[sender.tag]
        if chosen.id == Settings.currentProfile.id {
            Speaker.announce("Already using \(chosen.name).")
            return
        }
        Settings.useProfile(chosen.id)
        // Ready for the next call: focus goes to Callsign (unless you
        // switched from Settings, which keeps focus where it is).
        if window?.isKeyWindow == true { logEntry?.focusCallsign() }
        Speaker.announce("\(chosen.name) profile.")
    }

    // MARK: - Radio

    // The Radio menu: your radios (Control-Command-1 to 9, the one in use
    // ticked) and No Radio; then Tune, mode, filter and keyer commands;
    // then the receive settings; then RIT, XIT, split and VFOs; then
    // Radio Status, Reconnect and Radio Settings. Refilled when
    // Settings change.
    let radioMenu = NSMenu(title: "Radio")

    private func fillRadioMenu() {
        radioMenu.removeAllItems()
        for item in RadioMenu.choices(withShortcuts: true) { radioMenu.addItem(item) }
        radioMenu.addItem(.separator())
        // Tune goes to the form, which has the tuning control.
        let tune = radioMenu.addItem(withTitle: "Tune", action: #selector(LogEntryViewController.focusTuning(_:)),
                                     keyEquivalent: "t")
        tune.target = logEntry
        let controls: [(String, Selector, String)] = [
            ("Next Mode", #selector(nextMode(_:)), "m"),
            ("Wider Filter", #selector(widerFilter(_:)), "]"),
            ("Narrower Filter", #selector(narrowerFilter(_:)), "["),
            ("Keyer Faster", #selector(keyerFaster(_:)), "="),
            ("Keyer Slower", #selector(keyerSlower(_:)), "-"),
        ]
        // Band Up and Down: Control-Command-Up and Down Arrow. (Arrow keys
        // are written as AppKit's "function key" characters.)
        let arrows = [("Band Up", #selector(bandUp(_:)), NSUpArrowFunctionKey),
                      ("Band Down", #selector(bandDown(_:)), NSDownArrowFunctionKey)]
        let bands = arrows.map { ($0.0, $0.1, String(Character(UnicodeScalar($0.2)!))) }
        for (title, action, key) in bands + controls {
            let item = radioMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = [.control, .command]
            item.target = self
        }
        // Control-Command-+ too: on most keyboards + is Shift-=, and a
        // keyboard with its own + key (such as a ZSA Voyager) sends
        // Shift-=; a number pad sends a plain +. A menu item has one
        // shortcut, so these are extra, hidden items (hidden items are
        // skipped by VoiceOver and not shown, but their shortcuts work).
        for (key, modifiers) in [("=", NSEvent.ModifierFlags([.control, .command, .shift])),
                                 ("+", NSEvent.ModifierFlags([.control, .command]))] {
            let plus = radioMenu.addItem(withTitle: "Keyer Faster", action: #selector(keyerFaster(_:)), keyEquivalent: key)
            plus.keyEquivalentModifierMask = modifiers
            plus.target = self
            plus.isHidden = true
            plus.allowsKeyEquivalentWhenHidden = true
        }
        // Receive settings, then RIT, XIT, split and VFOs: each on and off
        // (AGC steps through its speeds). The letters match the names.
        let groups: [[(String, Selector, String)]] = [
            [("Preamp", #selector(togglePreamp(_:)), "p"),
             ("Attenuator", #selector(toggleAttenuator(_:)), "a"),
             ("AGC", #selector(nextAGC(_:)), "g"),
             ("Noise Blanker", #selector(toggleNoiseBlanker(_:)), "b"),
             ("Noise Reduction", #selector(toggleNoiseReduction(_:)), "n"),
             ("Audio Peak Filter", #selector(togglePeakFilter(_:)), "k"),
             ("Dual Watch", #selector(toggleDualWatch(_:)), "w")],
            [("RIT", #selector(toggleRIT(_:)), "r"),
             ("XIT", #selector(toggleXIT(_:)), "x"),
             ("Split", #selector(toggleSplit(_:)), "s"),
             ("Swap VFOs", #selector(swapVFOs(_:)), "v")],
        ]
        for group in groups {
            radioMenu.addItem(.separator())
            for (title, action, key) in group {
                let item = radioMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
                item.keyEquivalentModifierMask = [.control, .command]
                item.target = self
            }
        }
        radioMenu.addItem(.separator())
        let status = radioMenu.addItem(withTitle: "Radio Status", action: #selector(speakRadioStatus(_:)),
                                       keyEquivalent: "r")
        let settingsStatus = radioMenu.addItem(withTitle: "Radio Details",
                                               action: #selector(speakRadioSettings(_:)), keyEquivalent: "r")
        settingsStatus.keyEquivalentModifierMask = [.option, .command]
        settingsStatus.target = self
        let strength = radioMenu.addItem(withTitle: "Signal Strength", action: #selector(speakStrength(_:)),
                                         keyEquivalent: "s")
        strength.keyEquivalentModifierMask = [.option, .command]
        strength.target = self
        let reconnect = radioMenu.addItem(withTitle: "Reconnect Radio", action: #selector(reconnectRadio(_:)),
                                          keyEquivalent: "")
        let record = radioMenu.addItem(withTitle: "Record Radio Log", action: #selector(recordRadioLog(_:)),
                                       keyEquivalent: "")
        record.state = RadioMonitor.shared.recordsLog ? .on : .off
        record.target = self
        let saveLog = radioMenu.addItem(withTitle: "Save Radio Log…", action: #selector(saveRadioLog(_:)),
                                        keyEquivalent: "")
        saveLog.target = self
        radioMenu.addItem(.separator())
        let settings = radioMenu.addItem(withTitle: "Radio Settings…", action: #selector(editRadio(_:)),
                                         keyEquivalent: "")
        for item in [status, reconnect, settings] { item.target = self }
    }

    // Radio > (a radio), or the radio pop-up: switches to it, in the
    // middle of a session if you like. Focus stays where it is.
    @objc func chooseRadio(_ sender: NSMenuItem) {
        let id = sender.representedObject as? UUID
        if id == Settings.currentRadio?.id {
            Speaker.announce("Already using \(Settings.currentRadio?.name ?? "no radio").")
            return
        }
        Settings.useRadio(id)
        Speaker.announce(Settings.currentRadio.map { "\($0.name)." } ?? "No radio.")
    }

    // Radio > Radio Status (Command-R): says what the radio is doing.
    @objc func speakRadioStatus(_ sender: Any?) {
        let monitor = RadioMonitor.shared
        if let reading = monitor.reading {
            let extras = [reading.filterSpoken, reading.band.map(LogEntryViewController.spokenBand),
                          reading.wattsText.map { $0 == "1" ? "1 watt" : "\($0) watts" }].compactMap { $0 }
            Speaker.announce(([reading.spoken] + extras).joined(separator: ", ") + ".")
        } else if monitor.state == .none {
            Speaker.announce(Settings.radios.isEmpty ? "No radio set up. Add one in Settings, Radio." : "No radio in use.")
        } else {
            Speaker.announce("\(monitor.radioName): \(monitor.stateText)")
        }
    }

    // Radio > Next Mode (Control-Command-M), Wider and Narrower Filter
    // (Control-Command-] and [), Keyer Faster and Slower (Control-Command-=
    // and -). See RadioControl.swift.
    @objc func nextMode(_ sender: Any?) { RadioMonitor.shared.nextMode() }
    @objc func widerFilter(_ sender: Any?) { RadioMonitor.shared.changeFilter(wider: true) }
    @objc func narrowerFilter(_ sender: Any?) { RadioMonitor.shared.changeFilter(wider: false) }
    @objc func keyerFaster(_ sender: Any?) {
        if !changeCWSpeed(by: 1) { RadioMonitor.shared.changeKeyerSpeed(by: 1) }
    }
    @objc func keyerSlower(_ sender: Any?) {
        if !changeCWSpeed(by: -1) { RadioMonitor.shared.changeKeyerSpeed(by: -1) }
    }

    // Radio > Preamp (Control-Command-P), Attenuator (A), AGC (G), Noise
    // Blanker (B), Noise Reduction (N), Audio Peak Filter (K), RIT (R),
    // XIT (X), Split (S), Swap VFOs (V). See RadioControl.swift.
    @objc func togglePreamp(_ sender: Any?) { RadioMonitor.shared.togglePreamp() }
    @objc func toggleAttenuator(_ sender: Any?) { RadioMonitor.shared.toggleAttenuator() }
    @objc func nextAGC(_ sender: Any?) { RadioMonitor.shared.nextAGC() }
    @objc func toggleNoiseBlanker(_ sender: Any?) { RadioMonitor.shared.toggleNoiseBlanker() }
    @objc func toggleNoiseReduction(_ sender: Any?) { RadioMonitor.shared.toggleNoiseReduction() }
    @objc func togglePeakFilter(_ sender: Any?) { RadioMonitor.shared.togglePeakFilter() }
    @objc func toggleRIT(_ sender: Any?) { RadioMonitor.shared.toggleRIT() }
    @objc func toggleXIT(_ sender: Any?) { RadioMonitor.shared.toggleXIT() }
    @objc func toggleSplit(_ sender: Any?) { RadioMonitor.shared.toggleSplit() }
    @objc func swapVFOs(_ sender: Any?) { RadioMonitor.shared.swapVFOs() }
    @objc func toggleDualWatch(_ sender: Any?) { RadioMonitor.shared.toggleDualWatch() }
    @objc func bandUp(_ sender: Any?) { RadioMonitor.shared.changeBand(up: true) }
    @objc func bandDown(_ sender: Any?) { RadioMonitor.shared.changeBand(up: false) }
    // Radio > Signal Strength (Option-Command-S): the S-meter, said.
    @objc func speakStrength(_ sender: Any?) { RadioMonitor.shared.sayStrength() }

    // Radio > Radio Details (Option-Command-R): says the status line at
    // the bottom of the window, "Keyer 18 words per minute, RIT off, AGC fast, ...".
    @objc func speakRadioSettings(_ sender: Any?) {
        let monitor = RadioMonitor.shared
        guard monitor.reading != nil, let status = monitor.status?.shown, !status.isEmpty else {
            return Speaker.announce(monitor.reading == nil ? monitor.notConnectedText : "No settings read yet.")
        }
        Speaker.announce(status.replacingOccurrences(of: "WPM", with: "words per minute") + ".")
    }

    // Radio > Record Radio Log: on and off (see RadioMonitor.recordsLog).
    // Ticked while on.
    @objc func recordRadioLog(_ sender: NSMenuItem) {
        let monitor = RadioMonitor.shared
        monitor.recordsLog.toggle()
        sender.state = monitor.recordsLog ? .on : .off
        Speaker.announce(monitor.recordsLog ? "Recording the radio log." : "Radio log stopped.")
    }

    // Radio > Save Radio Log…: copies the log out of Solid Copy's private
    // folder, which macOS keeps other programs (Terminal included) out
    // of, to where you choose: the Desktop, to begin with.
    @objc func saveRadioLog(_ sender: Any?) {
        let log = RadioMonitor.logURL
        guard FileManager.default.fileExists(atPath: log.path) else {
            return showMessage("There's no radio log yet.", details: "Choose Radio > Record Radio Log first.")
        }
        guard let window, window.attachedSheet == nil else { return }
        let panel = NSSavePanel()
        panel.title = "Save Radio Log"
        panel.prompt = "Save"
        panel.nameFieldStringValue = "rigctld.log"
        panel.directoryURL = realDocumentsFolder?.deletingLastPathComponent().appendingPathComponent("Desktop")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                // The panel has already asked whether to replace one there.
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                try FileManager.default.copyItem(at: log, to: url)
                Speaker.announce("Radio log saved.")
            } catch {
                self?.showMessage("The radio log wasn't saved.", details: error.localizedDescription)
            }
        }
    }

    // Radio > Reconnect Radio: starts the connection again from scratch.
    @objc func reconnectRadio(_ sender: Any?) {
        RadioMonitor.shared.reconnect()
        Speaker.announce("Reconnecting.")
    }

    // Radio > Radio Settings…: Settings, on the Radio tab.
    @objc func editRadio(_ sender: Any?) {
        showSettings(nil)
        settingsWindow?.showTab(number: 5)
    }

    // Speech > Speech Settings…: Settings, at Speech.
    @objc func editSpeech(_ sender: Any?) {
        showSettings(nil)
        settingsWindow?.showTab(number: 6)
    }

    // QSL > Upload Settings…: Settings > Uploads (section 8), focus on its
    // first control (the LoTW username).
    @objc func editUploads(_ sender: Any?) {
        showSettings(nil)
        settingsWindow?.showTab(number: 8)
    }

    // QSL > QRZ Logbook API Key…, Club Log Token… and eQSL Login… are in
    // UploadCommands.swift.

    // Speech > Quiet Mode (Option-Command-period): lookups, logging and
    // radio changes down to their sounds, or back. Errors still speak.
    @objc func toggleQuietMode(_ sender: NSMenuItem) {
        Speaker.quiet.toggle()
        sender.state = Speaker.quiet ? .on : .off
        // Said whatever the settings, so you know which way it went.
        Speaker.announce(Speaker.quiet ? "Quiet mode on. Sounds only." : "Quiet mode off.")
    }

    // Stops Solid Copy's rigctld, so it doesn't keep the radio's port.
    func applicationWillTerminate(_ notification: Notification) {
        RadioMonitor.shared.stop()
        // Host close: the WinKeyer goes back to its own settings, free for
        // Keyer Sidetone.
        WinKeyer.shared.disconnect()
        backUpAtQuit()
    }

    // Profile > Edit Profiles…: Settings, on the Profiles tab.
    @objc func editProfiles(_ sender: Any?) {
        showSettings(nil)
        settingsWindow?.showTab(number: 2)
    }

    // Solid Copy > Settings… (Command-comma).
    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController()
            // Settings > Backups' Back Up Now is File > Back Up Now.
            settingsWindow?.backups.onBackUpNow = { [weak self] in self?.backUpNow(nil) }
        }
        settingsWindow?.show()
    }

    // File > Show Log in Finder: opens the folder with the log file and its
    // Backups folder, with the log file selected.
    @objc func showLogInFinder(_ sender: Any?) {
        guard let logbook else { return }
        NSWorkspace.shared.activateFileViewerSelecting([logbook.fileURL])
    }

    // A message in a sheet on the main window. VoiceOver reads it when it
    // appears; Return closes it and focus goes back to Callsign.
    // Copy (Tab to it, then Space) puts the message on the clipboard and
    // closes it: an alert's text can be heard but not selected, and an
    // error is often worth pasting into an email or a note.
    func showMessage(_ title: String, details: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = details
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Copy")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertSecondButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(details.isEmpty ? title : "\(title)\n\n\(details)", forType: .string)
                Speaker.announce("Copied.")
            }
            self?.logEntry?.focusCallsign()
        }
    }

    // Closing the logging window doesn't quit: it's easy to close by
    // mistake (Command-W in the wrong window), and quitting would drop
    // what's in the form. Command-0, or clicking Solid Copy in the Dock,
    // brings it back. Command-Q quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Clicking Solid Copy in the Dock with no window open.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showLoggingWindow(nil) }
        return true
    }

    // Window > Log (Command-3): the open log, for browsing only.
    @objc func showLogBrowser(_ sender: Any?) {
        guard let logbook else { return }
        if logBrowser == nil { logBrowser = LogBrowserWindowController(logbook: logbook) }
        logBrowser?.show()
    }

    // Window > Activity (Command-2): the logging services' uploads and syncs.
    @objc func showActivity(_ sender: Any?) {
        if activityWindow == nil { activityWindow = ActivityWindowController() }
        activityWindow?.show()
    }

    // Quitting while an upload or sync runs would stop it half way, so ask
    // first. Nothing is lost by quitting when nothing is running: waiting
    // automatic uploads are saved and sent at the next launch.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = Activity.shared.runningCount
        guard running > 0 else { return .terminateNow }
        let names = Activity.shared.items.filter { $0.state == .running }.map(\.service)
        let which = Array(Set(names)).sorted().joined(separator: ", ")
        let alert = NSAlert()
        alert.messageText = "Quit while \(which) \(running == 1 ? "is" : "are") still running?"
        alert.informativeText = "Quitting stops the upload or sync. Contacts it hasn't sent yet go with the next sync or upload. Window > Activity shows what is running."
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit Anyway")
        Speaker.Cue.warning.play()
        // Keep Running is the default, so Return doesn't quit by accident.
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    // Window > Spots (Command-1): the Spots window, made the first time.
    // Return on a spot fills in the logging form; Escape goes back to it.
    @objc func showSpots(_ sender: Any?) {
        guard let logbook else { return }
        if spotsWindow == nil {
            let spots = SpotsWindowController(logbook: logbook)
            spots.onUse = { [weak self] spot in self?.logEntry?.useSpot(spot) }
            spots.onEscape = { [weak self] in self?.showLoggingWindow(nil) }
            spotsWindow = spots
        }
        spotsWindow?.show()
    }

    // Window > Logging Window (Command-0): the main window, in front,
    // with focus in Callsign.
    @objc func showLoggingWindow(_ sender: Any?) {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        logEntry?.focusCallsign()
    }

    // Window > Next Window (Command-backtick) and Previous Window
    // (Shift-Command-backtick): around Solid Copy's open windows, in the
    // order they were opened, so the order never changes under you.
    // macOS usually does this itself; doing it here makes it certain,
    // and puts it in the menu where VoiceOver can find it.
    @objc func nextWindow(_ sender: Any?) { cycleWindows(by: 1) }
    @objc func previousWindow(_ sender: Any?) { cycleWindows(by: -1) }

    private func cycleWindows(by step: Int) {
        // Only windows you could work in: on screen, able to take
        // keystrokes, and not a sheet (a sheet goes with its window).
        let windows = NSApp.windows.filter {
            $0.isVisible && $0.canBecomeKey && $0.sheetParent == nil && !$0.isMiniaturized
        }
        guard windows.count > 1 else { return NSSound.beep() }
        let here = windows.firstIndex { $0.isKeyWindow || $0.attachedSheet?.isKeyWindow == true } ?? 0
        let next = windows[(here + step + windows.count) % windows.count]
        // A window with a sheet open (Edit Contact) gives focus to the sheet.
        (next.attachedSheet ?? next).makeKeyAndOrderFront(nil)
    }
}
