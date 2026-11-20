// MainMenu.swift
//
// Builds the menu bar in code. Every command is in a menu with its
// shortcut shown, so VoiceOver users can find commands by browsing the
// menus (accessibility contract, rule 17).
//
// Why in code instead of a storyboard file? A storyboard is edited in
// Xcode's visual editor, which is hard to use with VoiceOver. Code can
// be read and changed in any text editor.

import AppKit

@MainActor
enum MainMenu {
    static func build(logEntry: LogEntryViewController, appDelegate: AppDelegate) -> NSMenu {
        let menuBar = NSMenu()
        menuBar.addItem(submenu: appMenu(appDelegate: appDelegate))
        menuBar.addItem(submenu: fileMenu(appDelegate: appDelegate))
        menuBar.addItem(submenu: editMenu())
        menuBar.addItem(submenu: contactMenu(logEntry: logEntry))
        menuBar.addItem(submenu: qslMenu(logTable: logEntry.logTable, appDelegate: appDelegate))
        menuBar.addItem(submenu: appDelegate.profileMenu)
        menuBar.addItem(submenu: appDelegate.radioMenu)
        menuBar.addItem(submenu: appDelegate.cwMenu)
        menuBar.addItem(submenu: speechMenu(logEntry: logEntry, appDelegate: appDelegate))
        menuBar.addItem(submenu: windowMenu(appDelegate: appDelegate))
        menuBar.addItem(submenu: helpMenu(appDelegate: appDelegate))
        return menuBar
    }

    // The menu named after the app: About, Hide, Quit.
    private static func appMenu(appDelegate: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "Solid Copy")
        menu.addItem(withTitle: "About Solid Copy",
                     action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: "Settings…",
                                    action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        settings.target = appDelegate
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Solid Copy",
                     action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(withTitle: "Quit Solid Copy",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    // The File menu, in groups (Scott, 17 November 2026), most used first:
    //   New Log ▸ (New Log…, New Contest Log…, New Test Log…), Open Log ▸,
    //     Delete This Log…, Show Log in Finder: your logs (Logs.swift);
    //   Import…, Export…, Back Up Now: what goes in and out;
    //   Contests ▸ (Show Contest Files, Save Profile as Contest…): rarely
    //     used, so tucked into a submenu;
    //   Save Contact, Close Window.
    // A submenu's shortcuts work from anywhere, as the top level's do:
    // Command-N, Shift-Command-N. (Option-Command-N is Say Name and
    // Place, and Control-Command-N the radio's noise reduction.)
    private static func fileMenu(appDelegate: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "File")
        let new = NSMenu(title: "New Log")
        for (title, action, key) in [("New Log…", #selector(AppDelegate.newLog(_:)), "n"),
                                     ("New Contest Log…", #selector(AppDelegate.newContestLog(_:)), ""),
                                     ("New Test Log…", #selector(AppDelegate.newTestLog(_:)), "N")] {
            new.addItem(withTitle: title, action: action, keyEquivalent: key).target = appDelegate
        }
        menu.addItem(withTitle: "New Log", action: nil, keyEquivalent: "").submenu = new
        // Every log, the open one ticked.
        menu.addItem(withTitle: "Open Log", action: nil, keyEquivalent: "").submenu = appDelegate.logMenu
        menu.addItem(withTitle: "Delete This Log…", action: #selector(AppDelegate.deleteLog(_:)),
                     keyEquivalent: "").target = appDelegate
        menu.addItem(withTitle: "Show Log in Finder", action: #selector(AppDelegate.showLogInFinder(_:)),
                     keyEquivalent: "").target = appDelegate
        menu.addItem(.separator())
        // Import… reads ADIF and ADX files and SQL log files (it works
        // out which). Shift-Command-I, to pair with Export's Shift-Command-E
        // (Scott, 17 November 2026); Command-I is Show Last Contact and
        // Option-Command-I Show Details.
        let importItem = menu.addItem(withTitle: "Import…",
                                      action: #selector(AppDelegate.importLog(_:)),
                                      keyEquivalent: "I")
        importItem.target = appDelegate
        // Export… writes ADIF, ADX or CSV (Shift-Command-E).
        let exportItem = menu.addItem(withTitle: "Export…",
                                      action: #selector(AppDelegate.exportLog(_:)),
                                      keyEquivalent: "E")
        exportItem.target = appDelegate
        // A backup now, copied to your backup folder too (Backups.swift).
        // No shortcut: backups happen by themselves (launch, schedule,
        // quit), so this is for the odd time you want one right now.
        let backUp = menu.addItem(withTitle: "Back Up Now", action: #selector(AppDelegate.backUpNow(_:)),
                                  keyEquivalent: "")
        backUp.target = appDelegate
        menu.addItem(.separator())
        // Contest files (Contest.swift): open their folder, or save the
        // profile in use as one.
        let contests = NSMenu(title: "Contests")
        for (title, action) in [("Show Contest Files", #selector(AppDelegate.showContestFiles(_:))),
                                ("Save Profile as Contest…", #selector(AppDelegate.saveProfileAsContest(_:)))] {
            contests.addItem(withTitle: title, action: action, keyEquivalent: "").target = appDelegate
        }
        menu.addItem(withTitle: "Contests", action: nil, keyEquivalent: "").submenu = contests
        menu.addItem(.separator())
        // Command-S saves the Edit Contact sheet, as in any Mac app. No
        // target: it goes to whatever's in front, and only the sheet
        // answers to it, so it's dimmed the rest of the time.
        menu.addItem(withTitle: "Save Contact", action: #selector(EditContactViewController.saveContact(_:)),
                     keyEquivalent: "s")
        menu.addItem(withTitle: "Close Window",
                     action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return menu
    }

    // The standard Edit menu. Text fields need it: without these items,
    // Command-C, Command-V and the rest don't work in the fields.
    // The actions have no target, so they go to whichever field has focus.
    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }

    // Commands for the contact being logged.
    private static func contactMenu(logEntry: LogEntryViewController) -> NSMenu {
        let menu = NSMenu(title: "Contact")

        // Return in any field also logs (handled in the form itself).
        // Command-Return is here so the command can be found in the menu.
        let log = menu.addItem(withTitle: "Log Contact",
                               action: #selector(LogEntryViewController.logContact(_:)),
                               keyEquivalent: "\r")
        log.target = logEntry

        // Escape in any field also clears.
        let clear = menu.addItem(withTitle: "Clear Form",
                                 action: #selector(LogEntryViewController.clearForm(_:)),
                                 keyEquivalent: "k")
        clear.target = logEntry

        menu.addItem(.separator())

        let goToCall = menu.addItem(withTitle: "Go to Callsign",
                                    action: #selector(LogEntryViewController.goToCallsign(_:)),
                                    keyEquivalent: "l")
        goToCall.target = logEntry

        // Moves focus to the newest contact in the log. Escape comes back.
        let showLast = menu.addItem(withTitle: "Show Last Contact",
                                    action: #selector(LogEntryViewController.showLastContact(_:)),
                                    keyEquivalent: "i")
        showLast.target = logEntry

        // Command-F: the search field above the log.
        let search = menu.addItem(withTitle: "Search the Log",
                                  action: #selector(LogEntryViewController.searchLog(_:)),
                                  keyEquivalent: "f")
        search.target = logEntry

        // Option-Command-F: narrows the log to the call in the form (or the
        // selected contact's call). Escape in the log shows everything.
        let find = menu.addItem(withTitle: "Find This Call in the Log",
                                action: #selector(LogEntryViewController.findCallInLog(_:)),
                                keyEquivalent: "f")
        find.keyEquivalentModifierMask = [.command, .option]
        find.target = logEntry

        // Option-Command-I, as Finder uses for its Inspector. Tab in the
        // log does the same.
        let details = menu.addItem(withTitle: "Show Details",
                                   action: #selector(LogEntryViewController.showDetails(_:)),
                                   keyEquivalent: "i")
        details.keyEquivalentModifierMask = [.command, .option]
        details.target = logEntry

        // Command-E, while the log has focus. Return in the log does the same.
        let edit = menu.addItem(withTitle: "Edit Contact",
                                action: #selector(LogTableViewController.editContact(_:)),
                                keyEquivalent: "e")
        edit.target = logEntry.logTable

        // Command-Delete, while the log has focus. Plain Delete works there
        // too. The table turns this item off when the log doesn't have focus.
        let delete = menu.addItem(withTitle: "Delete Contact",
                                  action: #selector(LogTableViewController.deleteContact(_:)),
                                  keyEquivalent: "\u{8}")
        delete.target = logEntry.logTable
        return menu
    }

    // QSL cards and confirmations (QSL.swift). The marks work on the
    // contacts selected in the log, while it has focus; on contacts that
    // all have the mark already, they take it off. Shift-Command-S and
    // Shift-Command-R: S for sent, R for received (Command-R alone is
    // Radio Status). Card Requested is rarer, so it has no shortcut.
    private static func qslMenu(logTable: LogTableViewController, appDelegate: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "QSL")
        // nil is a separator.
        let items: [(title: String, action: Selector, key: String)?] = [
            ("Card Requested", #selector(LogTableViewController.markCardRequested(_:)), ""),
            ("Card Sent", #selector(LogTableViewController.markCardSent(_:)), "S"),
            ("Card Received", #selector(LogTableViewController.markCardReceived(_:)), "R"),
            nil,
            ("Show Confirmed", #selector(LogTableViewController.showConfirmed(_:)), ""),
            ("Show Not Confirmed", #selector(LogTableViewController.showNotConfirmed(_:)), ""),
            ("Show Card Requests", #selector(LogTableViewController.showCardRequests(_:)), ""),
            nil,
            // Scanned cards (QSLCards.swift). Shift-Command-O: O for open.
            ("Open Card", #selector(LogTableViewController.openCard(_:)), "O"),
            ("Attach Card…", #selector(LogTableViewController.attachCard(_:)), ""),
            ("Remove Card", #selector(LogTableViewController.removeCard(_:)), ""),
            nil,
            // Your electronic card, into a Mail message (ElectronicCard.swift).
            // Shift-Command-K: K for card (C, S and Q were taken; Command-K
            // alone is Clear Form, Control-Command-K the radio's APF).
            ("Send QSL Card", #selector(LogTableViewController.sendCard(_:)), "K"),
        ]
        for item in items {
            guard let item else { menu.addItem(.separator()); continue }
            // A capital letter means Shift-Command.
            menu.addItem(withTitle: item.title, action: item.action, keyEquivalent: item.key).target = logTable
        }
        // Straight to Settings > QSL Card: what your card says and shows.
        menu.addItem(withTitle: "QSL Card Settings…", action: #selector(AppDelegate.editCardSettings(_:)),
                     keyEquivalent: "").target = appDelegate
        // A whole folder at once, matched by file name.
        menu.addItem(withTitle: "Attach Cards from a Folder…", action: #selector(AppDelegate.attachCardFolder(_:)),
                     keyEquivalent: "").target = appDelegate
        menu.addItem(.separator())
        // Upload to LoTW and get its confirmations (LoTWSync.swift).
        // Shift-Command-L: L for LoTW (Command-L alone is Go to Callsign).
        menu.addItem(withTitle: "Sync with LoTW", action: #selector(AppDelegate.syncWithLoTW(_:)),
                     keyEquivalent: "L").target = appDelegate
        // Every contact QRZ Logbook doesn't have yet, then its
        // confirmations (QRZLogbookSync.swift). Shift-Command-U: U for
        // upload, kept from when it only uploaded.
        menu.addItem(withTitle: "Sync with QRZ Logbook", action: #selector(AppDelegate.syncWithQRZLogbook(_:)),
                     keyEquivalent: "U").target = appDelegate
        // Club Log and eQSL (ClubLogUpload.swift, EQSLUpload.swift). No
        // shortcuts yet: ask for one if you use them by hand often.
        menu.addItem(withTitle: "Upload to Club Log", action: #selector(AppDelegate.uploadAllToClubLog(_:)),
                     keyEquivalent: "").target = appDelegate
        menu.addItem(withTitle: "Upload to eQSL", action: #selector(AppDelegate.uploadAllToEQSL(_:)),
                     keyEquivalent: "").target = appDelegate
        // The last upload or sync message, to read again or copy: an
        // automatic upload's is only spoken. No shortcut yet.
        menu.addItem(withTitle: "Show Last Upload Message", action: #selector(AppDelegate.showLastUploadMessage(_:)),
                     keyEquivalent: "").target = appDelegate
        menu.addItem(.separator())
        // Straight to Settings > Uploads, as Speech > Speech Settings… is
        // to Settings > Speech; the others land in that service's login field.
        menu.addItem(withTitle: "Upload Settings…", action: #selector(AppDelegate.editUploads(_:)),
                     keyEquivalent: "").target = appDelegate
        menu.addItem(withTitle: "QRZ Logbook API Key…", action: #selector(AppDelegate.editQRZLogbookKey(_:)),
                     keyEquivalent: "").target = appDelegate
        menu.addItem(withTitle: "Club Log Token…", action: #selector(AppDelegate.editClubLogToken(_:)),
                     keyEquivalent: "").target = appDelegate
        menu.addItem(withTitle: "eQSL Login…", action: #selector(AppDelegate.editEQSLLogin(_:)),
                     keyEquivalent: "").target = appDelegate
        return menu
    }

    // Speech: Quiet Mode, the "say it again" commands, and Settings >
    // Speech (see Speaker.swift).
    private static func speechMenu(logEntry: LogEntryViewController, appDelegate: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "Speech")

        // Option-Command-period: period, as Command-period means "stop".
        let quiet = menu.addItem(withTitle: "Quiet Mode", action: #selector(AppDelegate.toggleQuietMode(_:)),
                                 keyEquivalent: ".")
        quiet.keyEquivalentModifierMask = [.command, .option]
        quiet.target = appDelegate
        menu.addItem(.separator())

        let name = menu.addItem(withTitle: "Say Name and Place",
                                action: #selector(LogEntryViewController.sayNameAndPlace(_:)), keyEquivalent: "n")
        name.keyEquivalentModifierMask = [.command, .option]
        name.target = logEntry
        let last = menu.addItem(withTitle: "Say Last Contact",
                                action: #selector(LogEntryViewController.sayLastContact(_:)), keyEquivalent: "l")
        last.keyEquivalentModifierMask = [.command, .option]
        last.target = logEntry
        // Radio Status (Command-R) is in the Radio menu, beside the radio.
        menu.addItem(.separator())

        let settings = menu.addItem(withTitle: "Speech Settings…", action: #selector(AppDelegate.editSpeech(_:)),
                                    keyEquivalent: "")
        settings.target = appDelegate
        return menu
    }

    private static func windowMenu(appDelegate: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize",
                     action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(.separator())
        // Command-0 brings the logging window back if it was closed.
        let logging = menu.addItem(withTitle: "Logging Window",
                                   action: #selector(AppDelegate.showLoggingWindow(_:)), keyEquivalent: "0")
        // "~" with Command is Shift-Command-backtick: the menu matches the
        // character the keys type, as Help's "Command-?" does.
        let spots = menu.addItem(withTitle: "Spots", action: #selector(AppDelegate.showSpots(_:)), keyEquivalent: "1")
        spots.target = appDelegate
        // Command-2: what the logging services are uploading or syncing.
        let activity = menu.addItem(withTitle: "Activity", action: #selector(AppDelegate.showActivity(_:)), keyEquivalent: "2")
        activity.target = appDelegate
        // Command-3: the open log, to look things up (LogBrowserWindowController.swift).
        let browse = menu.addItem(withTitle: "Log", action: #selector(AppDelegate.showLogBrowser(_:)), keyEquivalent: "3")
        browse.target = appDelegate
        let next = menu.addItem(withTitle: "Next Window",
                                action: #selector(AppDelegate.nextWindow(_:)), keyEquivalent: "`")
        let previous = menu.addItem(withTitle: "Previous Window",
                                    action: #selector(AppDelegate.previousWindow(_:)), keyEquivalent: "~")
        for item in [logging, next, previous] { item.target = appDelegate }
        // macOS lists the open windows (Solid Copy, Settings) after these.
        menu.addItem(.separator())
        NSApp.windowsMenu = menu
        return menu
    }

    // Help: the Read Me, which is inside the app, so it opens with no
    // internet (in the field, say), and the project's page on GitHub
    // for the latest version and downloads. Being NSApp.helpMenu, macOS
    // adds its Search field at the top, which finds menu items too.
    private static func helpMenu(appDelegate: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "Help")
        // Command-? (Shift-Command-slash), the Mac's usual Help shortcut.
        menu.addItem(withTitle: "Solid Copy Help", action: #selector(AppDelegate.showHelp(_:)),
                     keyEquivalent: "?").target = appDelegate
        menu.addItem(withTitle: "Solid Copy on GitHub", action: #selector(AppDelegate.showWebsite(_:)),
                     keyEquivalent: "").target = appDelegate
        NSApp.helpMenu = menu
        return menu
    }
}

private extension NSMenu {
    // Adds a top-level menu (such as "Edit") to the menu bar.
    func addItem(submenu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
