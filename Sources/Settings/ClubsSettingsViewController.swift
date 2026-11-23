// ClubsSettingsViewController.swift
//
// Settings > Clubs (Command-9 in Settings): club membership numbers.
//
// SKCC (SKCCRoster.swift):
//   - Use SKCC's member list (on/off, on to start): fills in SKCC number
//     when you leave Callsign, and checks a number you type against the
//     call. Turning it on fetches the list (about 2 MB) if there's no
//     copy; it's fetched again weekly.
//   - A line saying how many members the copy has and when it was
//     fetched, and Fetch SKCC List Now.
// Your club fields (LogField.clubSlots of them): a name for each, such
//   as "NAQCC number" or "QCWA". A named field can go on the logging form
//   and in the log's columns (Settings > Logging Form, Log Columns), and
//   is in Edit Contact and exports. Like SKCC, FISTS, LICW and CWops, it's
//   filled in from your last contact with the same call
//   (ClubNumbers.swift). Clearing a name hides the field again; any
//   numbers already logged in it are kept.
// Saved on leaving a field (Escape saves too, then closes Settings).

import AppKit

@MainActor
final class ClubsSettingsViewController: NSViewController, NSTextFieldDelegate {
    var onEscape: (() -> Void)?
    // A club field named, renamed or cleared (Settings rebuilds its lists).
    var onNamesChanged: (() -> Void)?

    private let skccBox = NSButton(checkboxWithTitle: "Use SKCC's member list to fill in and check SKCC numbers",
                                   target: nil, action: nil)
    private let skccStatus = NSTextField(wrappingLabelWithString: "")
    private let fetchButton = NSButton(title: "Fetch SKCC List Now", target: nil, action: nil)
    private let nameFields: [NSTextField] = (1...LogField.clubSlots).map { _ in NSTextField(string: "") }
    // Each club field's member list from a file (ClubLists.swift).
    private let chooseListButtons: [NSButton] = (1...LogField.clubSlots).map { _ in
        NSButton(title: "Choose List…", target: nil, action: nil) }
    private let removeListButtons: [NSButton] = (1...LogField.clubSlots).map { _ in
        NSButton(title: "Remove List", target: nil, action: nil) }
    private let listStatus: [NSTextField] = (1...LogField.clubSlots).map { _ in
        NSTextField(wrappingLabelWithString: "") }

    var firstControl: NSView { skccBox }

    override func loadView() {
        let heading = Self.heading("SKCC")
        let note = NSTextField(wrappingLabelWithString:
            "SKCC publishes its member list. Solid Copy keeps a copy (about 2 MB, fetched again each week) "
            + "and looks calls up in it when you leave Callsign: the number goes in SKCC number and is said "
            + "with the lookup. An SKCC number you type is checked against the call; if it belongs to someone "
            + "else, you hear whose, since one of the two was probably miscopied. Only the list is fetched; "
            + "nothing is sent.")
        note.preferredMaxLayoutWidth = 520
        skccBox.target = self
        skccBox.action = #selector(skccChanged(_:))
        fetchButton.target = self
        fetchButton.action = #selector(fetchNow(_:))
        skccStatus.preferredMaxLayoutWidth = 520

        let clubHeading = Self.heading("Your club fields")
        let clubNote = NSTextField(wrappingLabelWithString:
            "Club fields hold the other station's number in a club Solid Copy doesn't already have: up to "
            + "\(LogField.clubSlots) of them, such as NAQCC number or QCWA. SKCC, FISTS, LICW and CWops are built "
            + "in, so they aren't needed here. Name the field for the club, not for your own membership: your own "
            + "numbers go in Exchange sent (Settings > Logging Form) or on your QSL card (Settings > QSL Card). A "
            + "named field can go on the logging form and in the log's columns, and it's filled in from your last "
            + "contact with the same call. Clearing a name hides the field; numbers already logged in it are kept.")
        clubNote.preferredMaxLayoutWidth = 520
        var rows: [[NSView]] = []
        for (index, field) in nameFields.enumerated() {
            let title = "Club field \(index + 1) name"
            field.setAccessibilityLabel(title)
            field.placeholderString = "not used"
            field.delegate = self
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
            rows.append([FieldLabel(title), field])
        }
        let grid = NSGridView(views: rows)
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.rowAlignment = .firstBaseline

        let listHeading = Self.heading("Member lists from files")
        let listNote = NSTextField(wrappingLabelWithString:
            "For a club field of your own, you can choose its member list, saved as CSV: one member per line, "
            + "the call, then a comma and the number. When you leave Callsign with a call on the list, its number "
            + "fills in that field, as SKCC's does. Solid Copy keeps its own copy of the file. Name the field first.")
        listNote.preferredMaxLayoutWidth = 520
        var listRows: [[NSView]] = []
        for slot in 1...LogField.clubSlots {
            let index = slot - 1
            let choose = chooseListButtons[index]
            choose.target = self
            choose.action = #selector(chooseList(_:))
            choose.setAccessibilityLabel("Choose member list for club field \(slot)")
            let remove = removeListButtons[index]
            remove.target = self
            remove.action = #selector(removeList(_:))
            remove.setAccessibilityLabel("Remove member list for club field \(slot)")
            listStatus[index].setAccessibilityLabel("Member list status for club field \(slot)")
            listStatus[index].preferredMaxLayoutWidth = 360
            let buttons = NSStackView(views: [choose, remove])
            buttons.spacing = 8
            let cell = NSStackView(views: [buttons, listStatus[index]])
            cell.orientation = .vertical
            cell.alignment = .leading
            listRows.append([FieldLabel("Club field \(slot) list"), cell])
        }
        let listGrid = NSGridView(views: listRows)
        listGrid.column(at: 0).xPlacement = .trailing
        listGrid.rowSpacing = 8
        listGrid.rowAlignment = .firstBaseline

        // Tab order: SKCC, the club names, then each field's list buttons.
        let listButtons = (0..<LogField.clubSlots).flatMap { [chooseListButtons[$0], removeListButtons[$0]] }
        let order: [NSView] = [skccBox, fetchButton] + nameFields + listButtons
        for (index, view) in order.enumerated() { view.nextKeyView = order[(index + 1) % order.count] }

        let stack = NSStackView(views: [heading, note, skccBox, skccStatus, fetchButton, clubHeading, clubNote, grid,
                                        listHeading, listNote, listGrid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(24, after: fetchButton)
        stack.setCustomSpacing(24, after: grid)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        view = stack
        SKCCRoster.shared.onChange = { [weak self] in self?.showStatus() }
        refresh()
    }

    private static func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        return label
    }

    // Shows what's saved (when Settings opens).
    func refresh() {
        guard isViewLoaded else { return }
        skccBox.state = Settings.skccLookup ? .on : .off
        for (index, field) in nameFields.enumerated() { field.stringValue = ClubNames.name(index + 1) }
        showStatus()
        showLists()
    }

    private func showStatus() {
        skccStatus.stringValue = Settings.skccLookup ? SKCCRoster.shared.status : "SKCC's list isn't used."
        fetchButton.isEnabled = Settings.skccLookup && !SKCCRoster.shared.downloading
    }

    @objc private func skccChanged(_ sender: Any?) {
        Settings.skccLookup = skccBox.state == .on
        Speaker.announce(Settings.skccLookup ? "SKCC's member list on." : "SKCC's member list off.")
        SKCCRoster.shared.start()
        showStatus()
    }

    @objc private func fetchNow(_ sender: Any?) {
        Speaker.announce("Fetching SKCC's list.")
        Task { [weak self] in
            let result = await SKCCRoster.shared.update()
            self?.showStatus()
            Speaker.announce(result)
        }
        showStatus()
    }

    // Settings > Clubs: a club field's member list, from a CSV file the
    // user chooses (the copy is kept by ClubLists.swift).
    @objc private func chooseList(_ sender: NSButton) {
        guard let index = chooseListButtons.firstIndex(of: sender), let window = view.window else { return }
        let slot = index + 1
        let panel = NSOpenPanel()
        panel.title = "Member list for club field \(slot)"
        panel.message = "Choose a CSV file: the call, a comma, then the number, on each line."
        panel.prompt = "Use List"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadList(slot: slot, from: url)
        }
    }

    private func loadList(slot: Int, from url: URL) {
        do {
            let count = try ClubLists.use(slot: slot, from: url)
            Speaker.announce("Club field \(slot): \(count.formatted()) members.")
        } catch {
            Speaker.Cue.warning.play()
            Speaker.announce("That list wasn't used. \(error.localizedDescription)")
        }
        showLists()
    }

    @objc private func removeList(_ sender: NSButton) {
        guard let index = removeListButtons.firstIndex(of: sender) else { return }
        ClubLists.remove(slot: index + 1)
        Speaker.announce("Club field \(index + 1) list removed.")
        showLists()
    }

    // What's saved for each club field's list.
    private func showLists() {
        for (index, label) in listStatus.enumerated() {
            let slot = index + 1
            if let count = ClubLists.count(slot: slot) {
                label.stringValue = ClubNames.name(slot).isEmpty
                    ? "\(count.formatted()) members, but this field has no name, so it isn't used."
                    : "\(count.formatted()) members."
                removeListButtons[index].isEnabled = true
            } else {
                label.stringValue = "No list."
                removeListButtons[index].isEnabled = false
            }
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let index = nameFields.firstIndex(of: field) else {
            return
        }
        let slot = index + 1
        guard field.stringValue.trimmingCharacters(in: .whitespaces) != ClubNames.name(slot) else { return }
        // A club Solid Copy has built in isn't made twice (the author named
        // two fields "LICW #696" and "FISTS #5030", 23 November 2026, and
        // the log offered both clubs twice).
        if let builtIn = ClubNames.builtInField(for: field.stringValue) {
            field.stringValue = ClubNames.name(slot)
            Speaker.Cue.warning.play()
            return Speaker.announce("Not used: that club is built in, as \(builtIn). A club field is for another "
                                    + "club's numbers, such as NAQCC.")
        }
        ClubNames.setName(field.stringValue, for: slot)
        field.stringValue = ClubNames.name(slot)
        // The form, the log's columns and Edit Contact use the new name.
        NotificationCenter.default.post(name: Settings.didChange, object: nil)
        onNamesChanged?()
        showLists()
        Speaker.announce(ClubNames.name(slot).isEmpty ? "Club field \(slot) not used."
                         : "Club field \(slot) is \(ClubNames.name(slot)).")
    }

    // Escape saves the field you're in, then closes Settings.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        view.window?.makeFirstResponder(nil)
        onEscape?()
        return true
    }
}
