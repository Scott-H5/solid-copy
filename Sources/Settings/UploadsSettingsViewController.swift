// UploadsSettingsViewController.swift
//
// Settings > Uploads: what LoTW, QRZ Logbook, Club Log and eQSL uploads
// need.
//
// Logbook of the World (LoTWSync.swift):
//   - LoTW username and password: your LoTW website login, for getting
//     confirmations. The password goes in the Keychain ("Solid Copy:
//     LoTW"), never in a file. Typed by you.
//   - TQSL station location: the name of the station location in TQSL to
//     sign uploads with ("Anytown, N0CALL").
//   - Upload contacts from: a UTC day ("2020-01-01"), or empty for all.
//   - Upload automatically: by hand, soon after each contact, or five
//     minutes after the last (AutoUploader.swift).
//   - Folder for TQSL: where Solid Copy and TQSL swap files (the App
//     Sandbox needs a folder you chose; see LoTWSync.swift).
//   - Install TQSL Script…: puts the small script Solid Copy runs TQSL
//     through where macOS allows it (a Save dialog you confirm; see
//     LoTWSync.swift for why).
// QRZ Logbook (QRZLogbookUpload.swift):
//   - API key: your logbook's key, from the logbook's Settings on qrz.com.
//     Kept in the Keychain ("Solid Copy: QRZ Logbook"). Typed by you.
//   - Upload contacts from, and Upload automatically, as for LoTW.
// Club Log (ClubLogUpload.swift):
//   - Token: made on clublog.org (Settings, then API). Kept in the
//     Keychain ("Solid Copy: Club Log"). Pasted by you.
//   - Upload contacts from, and Upload automatically.
// eQSL (EQSLUpload.swift):
//   - Username (usually your callsign) and password, the password in the
//     Keychain ("Solid Copy: eQSL"). Typed by you.
//   - QTH Nickname: only if you have more than one eQSL account for your
//     callsign; it says which one gets the contacts.
//   - Upload contacts from, and Upload automatically.
// Instructions are in each section's note, never only in a field's
// VoiceOver label or grey placeholder: those are spoken once and can't be
// read again word by word or copied (Scott, 17 November 2026, on the eQSL
// QTH Nickname). Each field is linked to its note (VO-Command-J jumps
// there), and the notes are selectable, so they can be copied.
// A line at the top says whether TQSL is installed. Everything is saved on
// leaving its field, or on choosing from a menu. Escape closes Settings.

import AppKit

@MainActor
final class UploadsSettingsViewController: NSViewController, NSTextFieldDelegate {
    var onEscape: (() -> Void)?

    private let usernameField = NSTextField(string: "")
    private let passwordField = NSSecureTextField(string: "")
    private let locationField = NSTextField(string: "")
    private let fromField = NSTextField(string: "")
    private let folderLabel = NSTextField(wrappingLabelWithString: "")
    private let folderButton = NSButton(title: "Choose Folder for TQSL…", target: nil, action: nil)
    private let tqslLabel = NSTextField(wrappingLabelWithString: "")
    private let scriptButton = NSButton(title: "Install TQSL Script…", target: nil, action: nil)
    private let qrzKeyField = NSSecureTextField(string: "")
    private let qrzFromField = NSTextField(string: "")
    private let clubLogTokenField = NSSecureTextField(string: "")
    private let clubLogFromField = NSTextField(string: "")
    private let eqslUserField = NSTextField(string: "")
    private let eqslPasswordField = NSSecureTextField(string: "")
    private let eqslNicknameField = NSTextField(string: "")
    private let eqslFromField = NSTextField(string: "")
    // Upload automatically, one menu for each service.
    private var autoMenus: [UploadService: NSPopUpButton] = [:]

    var firstControl: NSView { usernameField }
    // QSL > QRZ Logbook API Key…, Club Log Token… and eQSL Login… land
    // in these, past the LoTW controls.
    func loginControl(for service: UploadService) -> NSView {
        switch service {
        case .lotw: usernameField
        case .qrzLogbook: qrzKeyField
        case .clubLog: clubLogTokenField
        case .eqsl: eqslUserField
        }
    }
    // The "Upload contacts from" field for each service.
    private var fromFields: [(NSTextField, UploadService)] {
        [(fromField, .lotw), (qrzFromField, .qrzLogbook), (clubLogFromField, .clubLog), (eqslFromField, .eqsl)]
    }

    override func loadView() {
        let heading = Self.heading("Logbook of the World")
        let note = NSTextField(wrappingLabelWithString:
            "QSL > Sync with LoTW (Shift-Command-L) uploads new contacts through TQSL, the ARRL's program, "
            + "then gets your confirmations. Your LoTW username and password are your login on the LoTW website. "
            + "TQSL station location is the name of your station location exactly as TQSL lists it, such as "
            + "Anytown, N0CALL. Only your LoTW login and your contacts are sent, and only to LoTW.")
        let qrzHeading = Self.heading("QRZ Logbook")
        let qrzNote = NSTextField(wrappingLabelWithString:
            "QSL > Sync with QRZ Logbook (Shift-Command-U) sends the contacts your QRZ logbook doesn't have yet, "
            + "then marks the ones QRZ says are confirmed. "
            + "It needs a QRZ subscription, and your logbook's API key: on qrz.com, open your logbook, then its "
            + "Settings. Only the key and your contacts are sent, and only to QRZ. Notes and card scans stay here.")
        let clubLogHeading = Self.heading("Club Log")
        let clubLogNote = NSTextField(wrappingLabelWithString:
            "QSL > Upload to Club Log sends the contacts Club Log doesn't have yet, about one a second (Club Log's "
            + "limit). It needs a token: on clublog.org, open Settings, then the API tab, give the token a label "
            + "such as Solid Copy, and choose Create token. Copy it straight away (Club Log shows it only once) "
            + "and paste it here. Leave Test mode unticked. Only the token and your contacts are sent, and only "
            + "to Club Log.")
        let eqslHeading = Self.heading("eQSL")
        let eqslNote = NSTextField(wrappingLabelWithString:
            "QSL > Upload to eQSL sends the contacts eQSL doesn't have yet, with your QSL message (the QSL message "
            + "field) for the card. Your eQSL username is usually your callsign. QTH Nickname is only for more "
            + "than one eQSL account under the same callsign: type the nickname of the one to use, as it's named "
            + "in your eQSL profile. Only your login and your contacts are sent, and only to eQSL.")
        let autoNote = NSTextField(wrappingLabelWithString:
            "Upload automatically sends each contact you log, by itself: half a minute after it (time for the "
            + "lookup and a quick correction), or five minutes after the last one (a run of contacts goes "
            + "together; best for LoTW, which can't change a contact once it has it). Only contacts logged "
            + "while Solid Copy is open go this way. A problem is said once; when it works you hear nothing. "
            + "The log's shortcut menu also uploads just the contacts you choose. Upload contacts from, in each "
            + "section, is the first day to send, as year-month-day (2020-01-01); leave it empty to send every "
            + "contact.")
        for label in [note, folderLabel, tqslLabel, qrzNote, clubLogNote, eqslNote, autoNote] {
            label.preferredMaxLayoutWidth = 520
            // Selectable, so its words can be copied as well as read.
            label.isSelectable = true
        }
        // Marked as a login (what the fields are, for macOS and password
        // managers). Tried 16 November 2026: macOS offers nothing from the
        // Passwords app here, as it only offers a site's password to an
        // app the site names (an "associated domain"), and qrz.com and
        // arrl.org don't name Solid Copy. Copy and paste from Passwords.
        usernameField.contentType = .username
        passwordField.contentType = .password
        usernameField.setAccessibilityLabel("LoTW username")
        passwordField.setAccessibilityLabel("LoTW password")
        locationField.setAccessibilityLabel("TQSL station location")
        for (field, service) in fromFields {
            field.setAccessibilityLabel("\(service.name): upload contacts from")
            field.placeholderString = "2020-01-01"
        }
        qrzKeyField.setAccessibilityLabel("QRZ Logbook API key")
        clubLogTokenField.setAccessibilityLabel("Club Log token")
        eqslUserField.contentType = .username
        eqslPasswordField.contentType = .password
        eqslUserField.setAccessibilityLabel("eQSL username")
        eqslPasswordField.setAccessibilityLabel("eQSL password")
        eqslNicknameField.setAccessibilityLabel("eQSL QTH Nickname")
        // Each field to the note that explains it (VO-Command-J).
        let notes: [(fields: [NSView], note: NSTextField)] = [
            ([usernameField, passwordField, locationField], note),
            ([qrzKeyField], qrzNote),
            ([clubLogTokenField], clubLogNote),
            ([eqslUserField, eqslPasswordField, eqslNicknameField], eqslNote),
            (fromFields.map(\.0), autoNote),
        ]
        for (fields, note) in notes { for field in fields { field.setAccessibilityLinkedUIElements([note]) } }
        for field in [usernameField, passwordField, locationField, fromField, qrzKeyField, qrzFromField,
                      clubLogTokenField, clubLogFromField, eqslUserField, eqslPasswordField, eqslNicknameField,
                      eqslFromField] {
            field.delegate = self
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        }
        for service in UploadService.allCases {
            let menu = NSPopUpButton()
            menu.addItems(withTitles: AutoUpload.allCases.map(\.title))
            menu.setAccessibilityLabel("\(service.name): upload automatically")
            menu.target = self
            menu.action = #selector(autoUploadChanged(_:))
            autoMenus[service] = menu
        }
        folderButton.target = self
        folderButton.action = #selector(chooseFolder(_:))
        scriptButton.target = self
        scriptButton.action = #selector(installScript(_:))

        let lotwMenu = autoMenus[.lotw]!, qrzMenu = autoMenus[.qrzLogbook]!
        let clubLogMenu = autoMenus[.clubLog]!, eqslMenu = autoMenus[.eqsl]!
        let grid = Self.grid([
            [FieldLabel("LoTW username"), usernameField], [FieldLabel("LoTW password"), passwordField],
            [FieldLabel("TQSL station location"), locationField], [FieldLabel("Upload contacts from"), fromField],
            [FieldLabel("Upload automatically"), lotwMenu],
        ])
        let qrzGrid = Self.grid([
            [FieldLabel("API key"), qrzKeyField], [FieldLabel("Upload contacts from"), qrzFromField],
            [FieldLabel("Upload automatically"), qrzMenu],
        ])
        let clubLogGrid = Self.grid([
            [FieldLabel("Token"), clubLogTokenField], [FieldLabel("Upload contacts from"), clubLogFromField],
            [FieldLabel("Upload automatically"), clubLogMenu],
        ])
        let eqslGrid = Self.grid([
            [FieldLabel("Username"), eqslUserField], [FieldLabel("Password"), eqslPasswordField],
            [FieldLabel("QTH Nickname"), eqslNicknameField], [FieldLabel("Upload contacts from"), eqslFromField],
            [FieldLabel("Upload automatically"), eqslMenu],
        ])
        let order: [NSView] = [usernameField, passwordField, locationField, fromField, lotwMenu,
                               folderButton, scriptButton, qrzKeyField, qrzFromField, qrzMenu,
                               clubLogTokenField, clubLogFromField, clubLogMenu,
                               eqslUserField, eqslPasswordField, eqslNicknameField, eqslFromField, eqslMenu]
        for (index, view) in order.enumerated() { view.nextKeyView = order[(index + 1) % order.count] }

        let stack = NSStackView(views: [heading, tqslLabel, note, grid, folderButton, folderLabel, scriptButton,
                                        qrzHeading, qrzNote, qrzGrid, clubLogHeading, clubLogNote, clubLogGrid,
                                        eqslHeading, eqslNote, eqslGrid, autoNote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(24, after: scriptButton)
        for grid in [qrzGrid, clubLogGrid, eqslGrid] { stack.setCustomSpacing(24, after: grid) }
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        view = stack
        refresh()
    }

    private static func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        return label
    }

    private static func grid(_ rows: [[NSView]]) -> NSGridView {
        let grid = NSGridView(views: rows)
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.rowAlignment = .firstBaseline
        return grid
    }

    // Shows what's saved (when Settings opens).
    func refresh() {
        guard isViewLoaded else { return }
        usernameField.stringValue = Settings.lotwUsername
        passwordField.stringValue = Settings.lotwPassword
        locationField.stringValue = Settings.tqslLocation
        for (field, service) in fromFields { field.stringValue = Settings.uploadFrom(service) }
        qrzKeyField.stringValue = Settings.qrzLogbookKey
        clubLogTokenField.stringValue = Settings.clubLogToken
        eqslUserField.stringValue = Settings.eqslUsername
        eqslPasswordField.stringValue = Settings.eqslPassword
        eqslNicknameField.stringValue = Settings.eqslQTHNickname
        for (service, menu) in autoMenus {
            menu.selectItem(at: AutoUpload.allCases.firstIndex(of: Settings.autoUpload(service)) ?? 0)
        }
        tqslLabel.stringValue = (LoTWSync.tqslInstalled
            ? "TQSL is installed." : "TQSL isn't installed (it goes in Applications, in a TrustedQSL folder).")
            + (LoTWSync.scriptInstalled ? " The TQSL script is installed."
               : " The TQSL script isn't installed yet: Install TQSL Script…, below, then Save.")
        showFolder()
    }

    private func showFolder() {
        if let folder = LoTWSync.folder() {
            folderLabel.stringValue = "Folder for TQSL: \(folder.path)."
            folder.stopAccessingSecurityScopedResource()
        } else {
            folderLabel.stringValue = "No folder chosen for TQSL yet. Uploads need one; a new folder in "
                + "Documents is a good choice."
        }
    }

    @objc private func autoUploadChanged(_ sender: NSPopUpButton) {
        guard let service = autoMenus.first(where: { $0.value === sender })?.key,
              AutoUpload.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        Settings.setAutoUpload(AutoUpload.allCases[sender.indexOfSelectedItem], for: service)
    }

    @objc private func chooseFolder(_ sender: Any?) {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.title = "Folder for TQSL"
        panel.message = "Choose a folder where Solid Copy and TQSL can swap files. New Folder makes one."
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try LoTWSync.setFolder(url)
                Speaker.announce("Folder for TQSL: \(url.lastPathComponent).")
            } catch {
                Speaker.announce("Couldn't keep that folder. \(error.localizedDescription)")
            }
            self?.showFolder()
        }
    }

    // A Save dialog in the scripts folder, named tqsl.sh: Save puts it
    // there (Solid Copy can't on its own, by Apple's design).
    @objc private func installScript(_ sender: Any?) {
        guard let window = view.window, let folder = LoTWSync.scriptsFolder else { return }
        let panel = NSSavePanel()
        panel.title = "Install TQSL Script"
        panel.message = "Press Save to let Solid Copy run TQSL. Keep the name and the folder as they are."
        panel.prompt = "Save"
        panel.directoryURL = folder
        panel.nameFieldStringValue = LoTWSync.scriptName
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try LoTWSync.installScript(at: url)
                Speaker.announce("TQSL script installed.")
            } catch {
                NSSound.beep()
                Speaker.announce("The TQSL script wasn't installed. \(error.localizedDescription)")
            }
            self?.refresh()
        }
    }

    // MARK: - Saving

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        switch field {
        case usernameField, passwordField: saveLogin()
        case locationField: Settings.tqslLocation = locationField.stringValue
        case qrzKeyField: saveKey(qrzKeyField, account: Keychain.qrzLogbookAccount, service: Keychain.qrzLogbookService)
        case clubLogTokenField: saveKey(clubLogTokenField, account: Keychain.tokenAccount, service: Keychain.clubLogService)
        case eqslUserField, eqslPasswordField: saveEQSLLogin()
        case eqslNicknameField: Settings.eqslQTHNickname = eqslNicknameField.stringValue
        default:
            if let service = fromFields.first(where: { $0.0 === field })?.1 { saveFrom(field, for: service) }
        }
    }

    // The username, and the password in the Keychain (moved with the
    // username if that changed).
    private func saveLogin() {
        let username = usernameField.stringValue.trimmingCharacters(in: .whitespaces)
        let password = passwordField.stringValue
        guard username != Settings.lotwUsername || password != Settings.lotwPassword else { return }
        if username != Settings.lotwUsername {
            Keychain.deletePassword(for: Settings.lotwUsername, service: Keychain.lotwService)
            // Another account: its confirmations start from the beginning.
            Settings.lotwLastQSL = ""
        }
        Settings.lotwUsername = username
        do {
            try Keychain.setPassword(password, for: username, service: Keychain.lotwService)
        } catch {
            Speaker.announce(error.localizedDescription)
        }
    }

    // The QRZ Logbook key or Club Log token, in the Keychain (empty
    // removes it). Spaces from a copy and paste are dropped.
    private func saveKey(_ field: NSTextField, account: String, service: String) {
        let key = field.stringValue.filter { !$0.isWhitespace }
        field.stringValue = key
        guard key != (Keychain.password(for: account, service: service) ?? "") else { return }
        do {
            try Keychain.setPassword(key, for: account, service: service)
        } catch {
            Speaker.announce(error.localizedDescription)
        }
    }

    // The eQSL username, and its password in the Keychain (moved with the
    // username if that changed), as for LoTW.
    private func saveEQSLLogin() {
        let username = eqslUserField.stringValue.trimmingCharacters(in: .whitespaces)
        let password = eqslPasswordField.stringValue
        guard username != Settings.eqslUsername || password != Settings.eqslPassword else { return }
        if username != Settings.eqslUsername {
            Keychain.deletePassword(for: Settings.eqslUsername, service: Keychain.eqslService)
        }
        Settings.eqslUsername = username
        do {
            try Keychain.setPassword(password, for: username, service: Keychain.eqslService)
        } catch {
            Speaker.announce(error.localizedDescription)
        }
    }

    // A day as year-month-day, or empty; anything else is refused.
    private func saveFrom(_ field: NSTextField, for service: UploadService) {
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        let digits = text.filter(\.isNumber)
        guard text.isEmpty || (digits.count == 8 && QSO.date(adifDate: digits, adifTime: "000000") != nil) else {
            NSSound.beep()
            Speaker.announce("Upload contacts from needs a day like 2020-01-01, or nothing for all contacts.")
            field.stringValue = Settings.uploadFrom(service)
            return
        }
        let day = text.isEmpty ? "" : "\(digits.prefix(4))-\(digits.dropFirst(4).prefix(2))-\(digits.suffix(2))"
        field.stringValue = day
        Settings.setUploadFrom(day, for: service)
    }

    // Escape in a field closes Settings, as elsewhere in it.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        // Finish editing first, so what was typed or pasted (the API key,
        // say) is saved by controlTextDidEndEditing before the window goes.
        view.window?.makeFirstResponder(nil)
        onEscape?()
        return true
    }
}
