// LogTableViewController.swift
//
// The log: a table under the form showing every contact, newest first.
//
// It's an AppKit table (NSTableView) because, as Crystal Set found, it's
// the most predictable table with VoiceOver and gives full control over
// keys and actions.
//
// Keys when the table has focus (accessibility contract, rules 6, 18, 21):
//   - Up and Down arrows move between contacts. Shift-Up and Shift-Down
//     (or Command-click) select several.
//   - Return (or Command-E) opens the selected contact in the Edit Contact
//     sheet. Double-clicking a row does too.
//   - Delete removes the selected contacts, however many. Command-Z puts
//     them all back.
//     There's no "Are you sure?" dialog: Undo is faster and just as safe.
//   - Escape goes back to the Callsign field.
// Edit Contact and Delete Contact are also in the Contact menu, in the
// table's shortcut menu, and in VoiceOver's Actions rotor
// (VO-Command-Space).
//
// QSL cards (the QSL menu, and the shortcut menu): Card Requested, Card
// Sent (Shift-Command-S) and Card Received (Shift-Command-R) mark the
// selected contacts, dated today; on contacts that all have it already,
// the same command takes it off. Show Confirmed, Show Not Confirmed and
// Show Card Requests narrow the log; Escape shows everything again.
// Scanned cards (QSLCards.swift): Attach Card… adds one to the selected
// contact, Open Card (Shift-Command-O) opens it in Preview, where
// VoiceOver reads its text, and Remove Card takes it off.

import AppKit
import UniformTypeIdentifiers

@MainActor
final class LogTableViewController: NSViewController,
    NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation, NSMenuDelegate {

    // Called when you leave the table: Escape, or deleting the last contact.
    var onLeave: (() -> Void)?
    // Called when Tab is pressed in the table (goes to the details panel).
    var onTab: (() -> Void)?
    // Called when Shift-Tab is pressed in the table (goes back to the
    // last field of the logging form).
    var onBackTab: (() -> Void)?
    // Called whenever the selected contact changes, or changes itself
    // (after an edit), with the contact or nil.
    var onSelectionChange: ((QSO?) -> Void)?
    // Called when what's shown changes (the log narrowed to one call, or
    // back to everything), so the heading can say so.
    var onShownChange: (() -> Void)?
    // Browsing only (the Log window, LogBrowserWindowController.swift):
    // nothing here edits, deletes, marks cards, uploads or pastes. The
    // logging window's table never has this set.
    var browseOnly = false
    // Upload to LoTW or QRZ Logbook, from the shortcut menu: the service
    // and the chosen contacts (the app does the uploading).
    var onUpload: ((UploadService, [QSO]) -> Void)?

    // What the log is narrowed to, if anything: one call (Option-Command-F,
    // "Find This Call in the Log"), or a search (Command-F). Escape shows
    // everything again.
    enum Filter: Equatable {
        case call(String)
        case search(String)
        case qsl(QSL.Filter)
    }
    private(set) var filter: Filter?

    // The call the log is narrowed to, if it's narrowed to one call.
    var callFilter: String? {
        if case .call(let call) = filter { return call }
        return nil
    }

    // The search the log is narrowed to, if any.
    var searchFilter: String? {
        if case .search(let text) = filter { return text }
        return nil
    }
    // The QSL filter the log is narrowed to, if any.
    var qslFilter: QSL.Filter? {
        if case .qsl(let which) = filter { return which }
        return nil
    }
    // The contacts on show, newest first: row 0 is the newest.
    private var rows: [QSO] = []

    // Each contact's searchable text, lower case, as raw bytes: made the
    // first time a search needs it, and redone only for contacts that
    // change. Searching then compares bytes, which is many times faster
    // than comparing text (safe here, because both sides are lower case).
    private var searchText: [UUID: [UInt8]] = [:]

    // The log shown; `use` swaps in another (File > Open Log).
    private var logbook: Logbook
    private let tableView = LogTableView()

    // The row the shortcut menu is for, decided as it opens (see
    // menuNeedsUpdate below).
    private var shortcutMenuRow = -1

    // The table's columns: the ID macOS uses for each, its heading, its
    // starting width, and how to get its text from a contact.
    private struct Column {
        let id: String
        let title: String
        let width: CGFloat
        let text: (QSO) -> String
    }

    // The columns on show, from Settings > Log Columns (Call is always
    // first, so it's the first thing VoiceOver reads on each row). Columns
    // for fields use the field's ADIF name as their ID.
    private var columns: [Column] = []

    // A column's heading: "Call", "Date (UTC)", "Time (UTC)", or the
    // field's label ("Grid square").
    nonisolated static func columnTitle(for id: String) -> String {
        switch id {
        case "call": return "Call"
        case "date": return "Date (UTC)"
        case "time": return "Time (UTC)"
        default: return LogField.named(id)?.label ?? id
        }
    }

    // Starting widths, for columns you haven't resized.
    private static let startingWidths: [String: CGFloat] = [
        "call": 100, "name": 130, "date": 95, "time": 75, "band": 55, "mode": 60,
        "rst_sent": 70, "rst_rcvd": 90, "country": 120, "comment": 200, "notes": 220, "address": 220,
    ]

    private static func column(for id: String) -> Column {
        let width = Settings.columnWidths[id].map { CGFloat($0) } ?? startingWidths[id] ?? 100
        let text: (QSO) -> String
        switch id {
        case "call": text = { $0.call }
        case "date": text = { $0.utcDateText }
        case "time": text = { $0.utcTimeText }
        // The end date and QSL dates as the Date column has them
        // ("2026-11-22"), the end time as the Time column ("1949"): not
        // ADIF's raw 20261122 and 194945, which VoiceOver reads as numbers.
        case "time_off": text = { QSL.shortTime($0["time_off"]) }
        case _ where QSL.isDateField(id): text = { QSL.readableDate($0[id]) }
        // Line breaks (Notes, Address) shown as " / " to fit on one line.
        default: text = { $0[id].replacingOccurrences(of: "\n", with: " / ") }
        }
        return Column(id: id, title: columnTitle(for: id), width: width, text: text)
    }

    // True while this table is changing its own columns, so it doesn't
    // react to its own changes.
    private var arrangingColumns = false

    // Builds the table's columns from Settings, keeping the selection.
    private func rebuildColumns() {
        var ids = Settings.logColumns.filter {
            $0 == "call" || $0 == "date" || $0 == "time" || LogField.named($0).map { !$0.isUnnamedClubField } == true
        }
        ids.removeAll { $0 == "call" }
        ids.insert("call", at: 0)
        guard ids != columns.map(\.id) else {
            // Same columns; a club field may have been renamed.
            for tableColumn in tableView.tableColumns {
                tableColumn.title = Self.columnTitle(for: tableColumn.identifier.rawValue)
            }
            return
        }
        arrangingColumns = true
        defer { arrangingColumns = false }
        let selected = selectedContact?.id
        for column in tableView.tableColumns { tableView.removeTableColumn(column) }
        columns = ids.map(Self.column(for:))
        for column in columns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.id))
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableView.addTableColumn(tableColumn)
        }
        tableView.reloadData()
        if let selected { select(id: selected) }
    }

    // MARK: Moving columns from the keyboard
    //
    // The app can't tell which column the VoiceOver cursor is on, so the
    // log keeps its own "chosen" column: Left and Right Arrow choose one
    // and say it with the selected contact's value ("Date (UTC),
    // 2026-11-16"), which also reads a row across without VoiceOver's
    // keys. Option-Command-Left and Right move the chosen column and say
    // where it went ("Date (UTC), now column 2 of 8"). Call always stays
    // first. The new order is saved, as when a heading is dragged.
    // (the author's idea, 14 November 2026.)
    private var chosenColumn = 0

    private func stepColumn(_ step: Int) {
        let count = tableView.tableColumns.count
        guard count > 0 else { return }
        let next = min(max(chosenColumn + step, 0), count - 1)
        if next == chosenColumn, chosenColumn + step != next { NSSound.beep() }
        chosenColumn = next
        tableView.scrollColumnToVisible(next)
        let id = tableView.tableColumns[next].identifier.rawValue
        let title = Self.columnTitle(for: id)
        guard let qso = selectedContact, let column = columns.first(where: { $0.id == id }) else {
            return Speaker.announce("\(title) column.")
        }
        let value = column.text(qso)
        Speaker.announce("\(title), \(value.isEmpty ? "blank" : value).")
    }

    private func moveChosenColumn(_ step: Int) {
        let count = tableView.tableColumns.count
        guard tableView.tableColumns.indices.contains(chosenColumn) else { return }
        let title = Self.columnTitle(for: tableView.tableColumns[chosenColumn].identifier.rawValue)
        let target = chosenColumn + step
        guard chosenColumn > 0 else {
            NSSound.beep()
            return Speaker.announce("Call always stays first. Choose another column with Left or Right Arrow.")
        }
        guard target >= 1, target < count else {
            NSSound.beep()
            return Speaker.announce(target < 1 ? "\(title) is already next to Call." : "\(title) is already last.")
        }
        // moveColumn tells tableViewColumnDidMove, which saves the order.
        tableView.moveColumn(chosenColumn, toColumn: target)
        chosenColumn = target
        tableView.scrollColumnToVisible(target)
        Speaker.announce("\(title), now column \(target + 1) of \(count).")
    }

    // Remember a column's new width after you drag its edge.
    func tableViewColumnDidResize(_ notification: Notification) {
        guard !arrangingColumns, let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn else { return }
        Settings.columnWidths[column.identifier.rawValue] = Double(column.width)
    }

    // Remember the new order after you drag a column heading.
    func tableViewColumnDidMove(_ notification: Notification) {
        guard !arrangingColumns else { return }
        let ids = tableView.tableColumns.map(\.identifier.rawValue)
        columns = ids.compactMap { id in columns.first { $0.id == id } }
        arrangingColumns = true
        Settings.logColumns = ids
        arrangingColumns = false
    }

    init(logbook: Logbook) {
        self.logbook = logbook
        super.init(nibName: nil, bundle: nil)
    }

    // Required by AppKit for windows loaded from files, which this app
    // doesn't use.
    required init?(coder: NSCoder) { fatalError("Not used") }

    // MARK: - Building the table

    override func loadView() {
        // Columns come from Settings > Log Columns, which has Move Up and
        // Move Down for keyboard and VoiceOver users. Dragging a heading or
        // a column's edge also works, and is saved to the same settings.
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        // The contacts first, then the columns (which redraws the table).
        // The other way round, the table drew itself with no contacts and
        // stayed empty until the log changed (found 2026-11-14: the author's 160
        // contacts didn't show at launch).
        rebuildRows()
        rebuildColumns()
        NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.arrangingColumns else { return }
                self.rebuildColumns()
            }
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        // Several contacts can be selected (Shift-arrows), to delete together.
        tableView.allowsMultipleSelection = true
        tableView.setAccessibilityLabel("Log")
        tableView.onDelete = { [weak self] in self?.deleteContact(nil) }
        tableView.onEdit = { [weak self] in self?.editContact(nil) }
        // Double-clicking a row edits it.
        tableView.target = self
        tableView.doubleAction = #selector(editContact(_:))
        // Escape shows the whole log again (if it was narrowed to one call)
        // and goes back to Callsign.
        tableView.onEscape = { [weak self] in
            self?.showAllContacts()
            self?.onLeave?()
        }
        tableView.onTab = { [weak self] in self?.onTab?() }
        tableView.onBackTab = { [weak self] in self?.onBackTab?() }
        tableView.onColumnStep = { [weak self] in self?.stepColumn($0) }
        tableView.onColumnMove = { [weak self] in self?.moveChosenColumn($0) }

        // The shortcut menu (Control-click, or VO-Shift-M in VoiceOver).
        let menu = NSMenu()
        let edit = menu.addItem(withTitle: "Edit Contact",
                                action: #selector(editContact(_:)), keyEquivalent: "")
        edit.target = self
        let delete = menu.addItem(withTitle: "Delete Contact",
                                  action: #selector(deleteContact(_:)), keyEquivalent: "")
        delete.target = self
        menu.addItem(.separator())
        for (title, action) in [("Card Requested", #selector(markCardRequested(_:))),
                                ("Card Sent", #selector(markCardSent(_:))),
                                ("Card Received", #selector(markCardReceived(_:))),
                                ("Open Card", #selector(openCard(_:))),
                                ("Send QSL Card", #selector(sendCard(_:)))] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        // Just these contacts, now, whatever's set for automatic uploads.
        for (title, action) in [("Upload to LoTW", #selector(uploadToLoTW(_:))),
                                ("Upload to QRZ Logbook", #selector(uploadToQRZLogbook(_:))),
                                ("Upload to Club Log", #selector(uploadToClubLog(_:))),
                                ("Upload to eQSL", #selector(uploadToEQSL(_:)))] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        // Stop macOS adding its own items to this menu. It was adding a
        // hidden, unnamed, disabled item after Delete Contact (a place
        // holder for things like Writing Tools and Services). Arrow keys
        // skip it, but VoiceOver tripped over it: VO-Down stuck on the
        // first item. Found 2026-11-14 by reading the open menu's
        // accessibility tree.
        menu.allowsContextMenuPlugIns = false
        if #available(macOS 15.2, *) {
            menu.automaticallyInsertsWritingToolsItems = false
        }
        menu.delegate = self
        tableView.menu = menu

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        view = scrollView

        observeLogbook()
    }

    // Redraw whenever the logbook changes.
    // Redrawing keeps the selection, but doesn't announce it, so the
    // details panel is told here too (it may be showing a contact that
    // was just edited). The log is checked, so a log switched away from
    // can't redraw this table.
    private func observeLogbook() {
        let observed = logbook
        logbook.observe { [weak self] in
            guard let self, self.logbook === observed else { return }
            for id in self.logbook.lastChanged { self.searchText.removeValue(forKey: id) }
            self.rebuildRows()
            self.tableView.reloadData()
            self.selectionChanged()
        }
    }

    // Shows another log (File > Open Log). The table itself stays, so
    // nothing on screen is torn down: rebuilding the window's views while
    // a field had focus crashed inside macOS's text-input indicator with
    // VoiceOver on (the author, 17 November 2026).
    func use(_ newLogbook: Logbook) {
        logbook = newLogbook
        searchText = [:]
        filter = nil
        observeLogbook()
        rebuildRows()
        tableView.reloadData()
        tableView.deselectAll(nil)
        selectionChanged()
    }

    // MARK: - Narrowing to one call

    // Shows only contacts with this call, newest first, and moves focus to
    // the newest. Returns how many there are (0 changes nothing).
    @discardableResult
    func showContacts(with call: String) -> Int {
        let matching = logbook.contacts.filter { $0.call == call }.count
        guard matching > 0 else { return 0 }
        filter = .call(call)
        rebuildRows()
        tableView.reloadData()
        select(row: 0)
        selectionChanged()
        onShownChange?()
        view.window?.makeFirstResponder(tableView)
        return matching
    }

    // Narrows the log to contacts matching a search, as you type. Every
    // word must appear somewhere in the contact (see `matches`). Focus stays
    // in the search field. Returns how many match. An empty search shows
    // everything.
    @discardableResult
    func search(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            showAllContacts()
            return rows.count
        }
        filter = .search(trimmed)
        rebuildRows()
        tableView.reloadData()
        if !rows.isEmpty { select(row: 0) }
        selectionChanged()
        onShownChange?()
        return rows.count
    }

    // Narrows the log to contacts confirmed, not confirmed, or asking for
    // a card, and moves focus to the newest. Returns how many (0 changes
    // nothing).
    @discardableResult
    func showContacts(_ which: QSL.Filter) -> Int {
        let matching = logbook.contacts.filter(which.matches).count
        guard matching > 0 else { return 0 }
        filter = .qsl(which)
        rebuildRows()
        tableView.reloadData()
        select(row: 0)
        selectionChanged()
        onShownChange?()
        view.window?.makeFirstResponder(tableView)
        return matching
    }

    // Moves focus to the first contact on show (from the search field).
    func focusFirstContact() {
        guard !rows.isEmpty else { return }
        if tableView.selectedRow < 0 { select(row: 0) }
        view.window?.makeFirstResponder(tableView)
    }

    // Whether a contact matches every word of a search, in any field:
    // the call, the date, every field's value, and US states and Canadian
    // provinces spelled out (so "maryland" finds "MD"). Not case-sensitive.
    nonisolated static func matches(_ qso: QSO, words: [String]) -> Bool {
        words.allSatisfy(searchableText(for: qso).contains)
    }

    // Everything a search looks at in one contact, lower case.
    nonisolated static func searchableText(for qso: QSO) -> String {
        var text = [qso.call, qso.utcDateText] + qso.fields.values
        if let stateName = USStates.name(for: qso["state"]) { text.append(stateName) }
        return text.joined(separator: " ").lowercased()
    }

    // The cached version of searchableText, as bytes.
    private func cachedSearchText(for qso: QSO) -> [UInt8] {
        if let text = searchText[qso.id] { return text }
        let text = Array(Self.searchableText(for: qso).utf8)
        searchText[qso.id] = text
        return text
    }

    // Whether `word` appears anywhere in `text`, comparing bytes.
    private static func contains(_ text: [UInt8], _ word: [UInt8]) -> Bool {
        guard !word.isEmpty else { return true }
        return text.withUnsafeBytes { haystack in
            word.withUnsafeBytes { needle in
                memmem(haystack.baseAddress, haystack.count, needle.baseAddress, needle.count) != nil
            }
        }
    }

    // Shows the whole log again, keeping the selected contact selected.
    func showAllContacts() {
        guard filter != nil else { return }
        let selected = selectedContact?.id
        filter = nil
        rebuildRows()
        tableView.reloadData()
        if let selected { select(id: selected) }
        onShownChange?()
    }

    private func rebuildRows() {
        let shown: [QSO]
        switch filter {
        case .call(let call):
            shown = logbook.contacts.filter { $0.call == call }
        case .qsl(let which):
            // Marking contacts can take them out of the list (a card sent
            // isn't a request any more): done, so they go.
            shown = logbook.contacts.filter(which.matches)
        case .search(let text):
            let words = text.lowercased().split(whereSeparator: \.isWhitespace).map { Array($0.utf8) }
            shown = logbook.contacts.filter { qso in
                let text = cachedSearchText(for: qso)
                return words.allSatisfy { Self.contains(text, $0) }
            }
        case nil:
            shown = logbook.contacts
        }
        rows = shown.reversed()
        // If the last contact with the call was deleted, or the last one a
        // QSL filter showed was marked, show everything. (A search with no
        // matches stays, so you can change it.)
        if callFilter != nil || qslFilter != nil, rows.isEmpty {
            filter = nil
            rows = logbook.contacts.reversed()
            onShownChange?()
        }
    }

    // MARK: - Selection

    // The selected contact, if exactly one is selected.
    var selectedContact: QSO? {
        tableView.selectedRowIndexes.count == 1 ? contact(atRow: tableView.selectedRow) : nil
    }

    // How many contacts are selected.
    var selectionCount: Int { tableView.selectedRowIndexes.count }

    // Puts focus in the table, keeping the selection.
    func focusTable() {
        view.window?.makeFirstResponder(tableView)
    }

    // Selects the newest contact if nothing is selected. Returns false if
    // the log is empty.
    @discardableResult
    func selectNewestIfNone() -> Bool {
        guard !rows.isEmpty else { return false }
        if tableView.selectedRow < 0 { select(row: 0) }
        return true
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectionChanged()
    }

    private func selectionChanged() {
        onSelectionChange?(selectedContact)
    }

    // MARK: - Commands

    // Moves focus to the newest contact, so VoiceOver reads it and it's
    // highlighted on screen. Escape goes back to Callsign.
    func showLastContact() {
        guard !logbook.contacts.isEmpty else {
            Speaker.announce("No contacts logged yet.")
            return
        }
        showAllContacts()
        select(row: 0)
        view.window?.makeFirstResponder(tableView)
    }

    // Deletes the selected contacts (or, from the shortcut menu, the one
    // under the pointer or VoiceOver cursor, or the whole selection if
    // it's part of it).
    @objc func deleteContact(_ sender: Any?) {
        var targets = tableView.selectedRowIndexes
        if isFromShortcutMenu(sender), !targets.contains(shortcutMenuRow) {
            targets = IndexSet(integer: shortcutMenuRow)
        }
        delete(ids: targets.compactMap { contact(atRow: $0)?.id })
    }

    // Opens the selected contact (or the one clicked) in the Edit Contact
    // sheet.
    @objc func editContact(_ sender: Any?) {
        if !isFromShortcutMenu(sender), (sender as AnyObject?) !== tableView, selectionCount > 1 {
            Speaker.announce("\(selectionCount) contacts are selected. Select one to edit it.")
            return
        }
        guard let qso = contact(atRow: targetRow(sender)) else { return }
        openEditor(id: qso.id)
    }

    private func openEditor(id: UUID) {
        guard !browseOnly, let window = view.window, window.attachedSheet == nil,
              let index = logbook.index(of: id) else { return }
        let editor = EditContactViewController(qso: logbook.contacts[index])
        let sheet = NSWindow(contentViewController: editor)
        sheet.initialFirstResponder = editor.callsignField

        editor.onFinish = { [weak self, weak window, weak sheet] updated in
            guard let self, let window, let sheet else { return }
            window.endSheet(sheet)
            // Back to the log, on the same contact.
            window.makeFirstResponder(self.tableView)
            if let updated {
                self.save(updated)
            } else {
                Speaker.announce("Cancelled. Nothing changed.")
            }
        }
        window.beginSheet(sheet)
    }

    // Saves an edited contact, and teaches Undo how to put the old version
    // back. Undoing registers the reverse, which is how Redo works.
    private func save(_ updated: QSO) {
        guard let index = logbook.index(of: updated.id) else { return }
        let old = logbook.contacts[index]
        if updated == old {
            select(id: updated.id)
            Speaker.announce("No changes.")
            return
        }
        do {
            try logbook.update(updated)
        } catch {
            Speaker.announce("Not saved. \(error.localizedDescription)")
            NSSound.beep()
            return
        }
        undoManager?.registerUndo(withTarget: self) { controller in
            controller.save(old)
        }
        undoManager?.setActionName("Edit Contact")
        select(id: updated.id)
        view.window?.makeFirstResponder(tableView)
        // Say what happened: a save, an Undo of it, or a Redo.
        let what = undoManager?.isUndoing == true ? "Edit undone for"
            : undoManager?.isRedoing == true ? "Edit redone for" : "Saved"
        Speaker.announce("\(what) \(Callsign.spoken(updated.call)).")
    }

    // Deletes contacts (one or many) in one step, and teaches Edit > Undo
    // to put them all back.
    private func delete(ids: [UUID]) {
        guard !browseOnly else { return }
        let removed = ids.compactMap { id in logbook.contacts.first { $0.id == id } }
        guard !removed.isEmpty else { return }
        let firstRow = removed.compactMap { row(for: $0.id) }.min() ?? 0
        do {
            try logbook.removeAll(ids: removed.map(\.id))
        } catch {
            Speaker.announce("Not deleted. \(error.localizedDescription)")
            NSSound.beep()
            return
        }
        undoManager?.registerUndo(withTarget: self) { controller in
            controller.restore(removed)
        }
        undoManager?.setActionName(removed.count == 1 ? "Delete Contact" : "Delete Contacts")

        if rows.isEmpty {
            onLeave?()
        } else {
            // Select the contact that moved into the first one's place.
            select(row: min(firstRow, rows.count - 1))
        }
        let what = removed.count == 1 ? Callsign.spoken(removed[0].call) : "\(removed.count) contacts"
        Speaker.announce("Deleted \(what). Command-Z to undo.")
    }

    private func delete(id: UUID) { delete(ids: [id]) }

    // Undo of a delete: puts the contacts back and selects them.
    private func restore(_ restored: [QSO]) {
        do {
            try logbook.restoreAll(restored)
        } catch {
            Speaker.announce("Not restored. \(error.localizedDescription)")
            NSSound.beep()
            return
        }
        // And teach Redo how to delete them again.
        undoManager?.registerUndo(withTarget: self) { controller in
            controller.delete(ids: restored.map(\.id))
        }
        undoManager?.setActionName(restored.count == 1 ? "Delete Contact" : "Delete Contacts")
        let restoredRows = IndexSet(restored.compactMap { row(for: $0.id) })
        tableView.selectRowIndexes(restoredRows, byExtendingSelection: false)
        if let first = restoredRows.first { tableView.scrollRowToVisible(first) }
        view.window?.makeFirstResponder(tableView)
        let what = restored.count == 1 ? Callsign.spoken(restored[0].call) : "\(restored.count) contacts"
        Speaker.announce("Restored \(what).")
    }

    // MARK: - QSL cards

    @objc func markCardRequested(_ sender: Any?) { mark(.requested, sender) }
    @objc func markCardSent(_ sender: Any?) { mark(.sent, sender) }
    @objc func markCardReceived(_ sender: Any?) { mark(.received, sender) }

    @objc func showConfirmed(_ sender: Any?) { show(.confirmed) }
    @objc func showNotConfirmed(_ sender: Any?) { show(.notConfirmed) }
    @objc func showCardRequests(_ sender: Any?) { show(.cardRequested) }

    // MARK: - Scanned cards

    private var cards: QSLCards { QSLCards(logFile: logbook.fileURL) }
    // Kept while Mail takes a card (sendCard), so its answer comes back.
    private var cardMail: CardMail?

    // The one contact a card command is for, or nil (with why, said).
    private func cardContact(_ sender: Any?) -> QSO? {
        if !isFromShortcutMenu(sender), selectionCount > 1 {
            Speaker.announce("\(selectionCount) contacts are selected. Select one for its card.")
            return nil
        }
        return contact(atRow: targetRow(sender))
    }

    @objc func attachCard(_ sender: Any?) {
        guard !browseOnly, let qso = cardContact(sender), let window = view.window, window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Attach Card"
        panel.message = "Choose the scanned card for \(qso.call): a PDF or a picture."
        panel.prompt = "Attach"
        panel.allowedContentTypes = QSLCards.kinds.compactMap { UTType(filenameExtension: $0) }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                let updated = try self.cards.attach(url, to: qso)
                self.replace([updated], action: "Attach Card",
                             said: "Card attached for \(Callsign.spoken(qso.call)).")
            } catch {
                Speaker.announce("Not attached. \(error.localizedDescription)")
                NSSound.beep()
            }
        }
    }

    @objc func openCard(_ sender: Any?) {
        guard let qso = cardContact(sender) else { return }
        guard let url = cards.file(for: qso) else {
            NSSound.beep()
            return Speaker.announce(qso["app_solidcopy_qsl_card"].isEmpty
                ? "No card for \(Callsign.spoken(qso.call)). QSL, Attach Card adds one."
                : "The card's file is missing from the QSL Cards folder. Attach it again.")
        }
        NSWorkspace.shared.open(url)
    }

    // QSL > Send QSL Card (Shift-Command-K): your electronic card for the
    // contact (ElectronicCard.swift, set up in Settings > QSL Card), saved
    // in a Sent Cards folder beside the log and attached to a new Mail
    // message, addressed to them if the log has their email. The message
    // holds the card's text too, for anyone whose mail can't show the
    // PDF. Once Mail has it, the contact is marked Card sent, by
    // electronic means, dated today (Undo takes that back); you send the
    // message, and can still throw it away. Without Mail, the card is
    // shown in Finder instead and nothing is marked.
    @objc func sendCard(_ sender: Any?) {
        guard let qso = cardContact(sender) else { return }
        let station = Settings.currentProfile.station
        let myCall = [qso["station_callsign"], station["station_callsign"] ?? ""].first { !$0.isEmpty } ?? ""
        guard !myCall.isEmpty else {
            NSSound.beep()
            return Speaker.announce("Your card needs your callsign. Add it to your profile in Settings, Profiles.")
        }
        let lines = ElectronicCard.lines(for: qso, design: Settings.cardDesign, myCall: myCall)
        let pdf = ElectronicCard.pdf(lines, picture: Settings.cardPictureFile.flatMap(ElectronicCard.picture(at:)),
                                     pictureDescription: Settings.cardPictureDescription,
                                     title: "QSL card from \(myCall) to \(qso.call)", author: myCall)
        let url: URL
        do {
            let folder = logbook.fileURL.deletingLastPathComponent()
                .appendingPathComponent("Sent Cards", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            url = folder.appendingPathComponent(ElectronicCard.fileName(for: qso))
            try pdf.write(to: url, options: .atomic)
        } catch {
            NSSound.beep()
            return Speaker.announce("The card couldn't be made. \(error.localizedDescription)")
        }

        guard let mail = NSSharingService(named: .composeEmail), mail.canPerform(withItems: [url]) else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return Speaker.announce("Card made, but Mail isn't set up, so it's selected in Finder. Attach it to a "
                                    + "message yourself, then mark the contact with Card Sent.")
        }
        let email = qso["email"].trimmingCharacters(in: .whitespacesAndNewlines)
        if !email.isEmpty { mail.recipients = [email] }
        mail.subject = "QSL card: \(myCall) and \(qso.call), \(QSL.spokenDate(qso.adifDate))"
        let body = "Here's my QSL card for our contact, attached as a PDF. What it says:\n\n"
            + ElectronicCard.text(lines) + "\n"
        let id = qso.id
        cardMail = CardMail { [weak self] handed in
            guard let self else { return }
            self.cardMail = nil
            guard handed else { return Speaker.announce("The card wasn't put in a message. It's in Sent Cards.") }
            let latest = self.logbook.contacts.first { $0.id == id } ?? qso
            let marked = ElectronicCard.markedSent(latest, today: QSL.today())
            if marked != latest {
                self.replace([marked], action: "Send QSL Card",
                             said: "Card sent marked for \(Callsign.spoken(qso.call)), by email, dated today.")
            }
        }
        mail.delegate = cardMail
        Speaker.announce(email.isEmpty ? "Card made. In the new message, add their address, then send it."
                         : "Card made, in a new message to \(email). Check it, then send it.")
        mail.perform(withItems: [body, url])
    }

    // Takes the card off (its file stays, so Undo can put it back). The
    // card still counts as received: you did get it.
    @objc func removeCard(_ sender: Any?) {
        guard !browseOnly, let qso = cardContact(sender) else { return }
        guard !qso["app_solidcopy_qsl_card"].isEmpty else {
            NSSound.beep()
            return Speaker.announce("No card for \(Callsign.spoken(qso.call)).")
        }
        var updated = qso
        updated["app_solidcopy_qsl_card"] = ""
        updated["app_solidcopy_card_text"] = ""
        replace([updated], action: "Remove Card", said: "Card removed from \(Callsign.spoken(qso.call)).")
    }

    private func show(_ which: QSL.Filter) {
        if showContacts(which) == 0 { Speaker.announce("No contacts \(which.heading).") }
    }

    // Marks the selected contacts (or the shortcut menu's), or takes the
    // mark off if they all have it (QSL.apply).
    private func mark(_ mark: QSL.CardMark, _ sender: Any?) {
        guard !browseOnly else { return }
        var targets = tableView.selectedRowIndexes
        if isFromShortcutMenu(sender), !targets.contains(shortcutMenuRow) {
            targets = IndexSet(integer: shortcutMenuRow)
        }
        let contacts = targets.compactMap(contact(atRow:))
        guard !contacts.isEmpty else { return NSSound.beep() }
        let result = QSL.apply(mark, to: contacts, today: QSL.today())
        let what = contacts.count == 1 ? Callsign.spoken(contacts[0].call) : "\(contacts.count) contacts"
        let dated = mark.dateField == nil ? "" : ", dated today"
        replace(result.changed, action: mark.name,
                said: result.on ? "\(mark.name) for \(what)\(dated)." : "\(mark.name) taken off \(what).")
    }

    @objc func uploadToLoTW(_ sender: Any?) { upload(.lotw, sender) }
    @objc func uploadToQRZLogbook(_ sender: Any?) { upload(.qrzLogbook, sender) }
    @objc func uploadToClubLog(_ sender: Any?) { upload(.clubLog, sender) }
    @objc func uploadToEQSL(_ sender: Any?) { upload(.eqsl, sender) }

    // The selected contacts (or the shortcut menu's), to a service, even
    // ones already sent: you chose them.
    private func upload(_ service: UploadService, _ sender: Any?) {
        guard !browseOnly else { return }
        var targets = tableView.selectedRowIndexes
        if isFromShortcutMenu(sender), !targets.contains(shortcutMenuRow) {
            targets = IndexSet(integer: shortcutMenuRow)
        }
        let contacts = targets.compactMap(contact(atRow:))
        guard !contacts.isEmpty, let onUpload else { return NSSound.beep() }
        onUpload(service, contacts)
    }

    // Saves changed contacts in one step, and teaches Undo to put the old
    // versions back (and Redo, the new ones again). The same contacts
    // stay selected.
    private func replace(_ updated: [QSO], action: String, said: String) {
        let firstRow = updated.compactMap { row(for: $0.id) }.min() ?? 0
        let old: [QSO]
        do {
            old = try logbook.updateAll(updated)
        } catch {
            Speaker.announce("Not saved. \(error.localizedDescription)")
            NSSound.beep()
            return
        }
        undoManager?.registerUndo(withTarget: self) { controller in
            controller.replace(old, action: action, said: said)
        }
        undoManager?.setActionName(action)
        // The same contacts stay selected; if a QSL filter took them out,
        // the one now in the first one's place is.
        let shown = IndexSet(updated.compactMap { row(for: $0.id) })
        if !shown.isEmpty {
            tableView.selectRowIndexes(shown, byExtendingSelection: false)
        } else if !rows.isEmpty {
            select(row: min(firstRow, rows.count - 1))
        }
        let prefix = undoManager?.isUndoing == true ? "Undone: " : undoManager?.isRedoing == true ? "Redone: " : ""
        Speaker.announce(prefix + said)
    }

    // MARK: - Copy and paste between logs
    //
    // Edit > Copy (Command-C) in the log copies the selected contacts as
    // ADIF text, every field, Notes too (it's your own clipboard). Edit >
    // Paste (Command-V) in a log adds the ADIF on the clipboard to it, so
    // contacts can be brought into a test log or a new log (the author, 17
    // November 2026), and ADIF copied from anywhere else works too.
    // Pasting skips contacts already in the log (same call and time),
    // backs the log up first, and Command-Z takes the paste back out.
    // A scanned card's file belongs to the log it was attached in, so a
    // pasted contact doesn't point at it; the card's text comes along.

    @objc func copy(_ sender: Any?) {
        let contacts = tableView.selectedRowIndexes.compactMap { contact(atRow: $0) }
            .sorted { $0.timeOn < $1.timeOn }
        guard !contacts.isEmpty else { return NSSound.beep() }
        let text = String(decoding: LogExport.adif(contacts, includeNotes: true), as: UTF8.self)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Speaker.announce(contacts.count == 1 ? "Copied 1 contact." : "Copied \(contacts.count) contacts.")
    }

    @objc func paste(_ sender: Any?) {
        pasteContacts()
    }

    // Also from the form: Command-V in a field with contacts on the
    // clipboard comes here (FormTextField.swift), so focus never has to
    // move into the log, which may be empty.
    func pasteContacts() {
        guard !browseOnly else { return }
        let data = Data((NSPasteboard.general.string(forType: .string) ?? "").utf8)
        guard ADIFImport.looksLikeADIF(data) else {
            NSSound.beep()
            return Speaker.announce("Nothing to paste. Copy contacts in a log first, with Command-C.")
        }
        let incoming = ADIFImport.read(data).contacts.map { qso -> QSO in
            var qso = qso
            qso["app_solidcopy_qsl_card"] = ""
            return qso
        }
        guard !incoming.isEmpty else {
            NSSound.beep()
            return Speaker.announce("The clipboard's ADIF has no contacts Solid Copy can read.")
        }
        let added: [QSO], skipped: Int
        do {
            try logbook.backUp()
            (added, skipped) = try logbook.importContacts(incoming)
        } catch {
            Speaker.Cue.warning.play()
            return Speaker.announce("Not pasted. \(error.localizedDescription)")
        }
        if !added.isEmpty { registerPasteUndo(added.map(\.id)) }
        var words = added.count == 1 ? "Pasted 1 contact" : "Pasted \(added.count) contacts"
        words += " into \(logbook.info.title)."
        if skipped > 0 { words += skipped == 1 ? " 1 was already there." : " \(skipped) were already there." }
        // Into a real log, contacts not marked uploaded go up with the next
        // sync or upload, which may be news.
        if !logbook.isTest, added.contains(where: { !UploadService.lotw.isUploaded($0) }) {
            words += " Ones not marked uploaded will go with the next LoTW sync."
        }
        Speaker.announce(words)
    }

    private func registerPasteUndo(_ ids: [UUID]) {
        let pasted = logbook
        undoManager?.registerUndo(withTarget: self) { table in
            // Only on the log they were pasted into.
            guard table.logbook === pasted else { return }
            do {
                try table.logbook.removeAll(ids: ids)
                Speaker.announce(ids.count == 1 ? "Paste undone: 1 contact taken out." : "Paste undone: \(ids.count) contacts taken out.")
            } catch {
                Speaker.announce("Couldn't undo the paste. \(error.localizedDescription)")
            }
        }
        undoManager?.setActionName("Paste Contacts")
    }

    // Turns menu items on only when they'd do something.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // The menus' log commands are the logging window's: off while the
        // Log window (browsing only) is in front, so they can't reach it.
        if LogBrowserWindowController.isFrontmost { return false }
        // Copy and Paste here only while the log has focus (in a text
        // field they're the field's own).
        if menuItem.action == #selector(copy(_:)) || menuItem.action == #selector(paste(_:)) {
            guard view.window?.attachedSheet == nil, view.window?.firstResponder === tableView else { return false }
            return menuItem.action == #selector(paste(_:)) || selectionCount > 0
        }
        let marks: [Selector] = [#selector(markCardRequested(_:)), #selector(markCardSent(_:)),
                                 #selector(markCardReceived(_:)), #selector(attachCard(_:)),
                                 #selector(openCard(_:)), #selector(removeCard(_:)), #selector(sendCard(_:)),
                                 #selector(uploadToLoTW(_:)), #selector(uploadToQRZLogbook(_:)),
                                 #selector(uploadToClubLog(_:)), #selector(uploadToEQSL(_:))]
        if let action = menuItem.action, marks.contains(action) {
            guard view.window?.attachedSheet == nil else { return false }
            if isFromShortcutMenu(menuItem) { return shortcutMenuRow >= 0 }
            return view.window?.firstResponder === tableView && selectionCount > 0
        }
        guard menuItem.action == #selector(deleteContact(_:))
                || menuItem.action == #selector(editContact(_:)) else { return true }
        // Nothing while the Edit Contact sheet is open, so its keys (such
        // as Command-Delete in a field) never reach the log behind it.
        guard view.window?.attachedSheet == nil else { return false }
        if isFromShortcutMenu(menuItem) {
            return shortcutMenuRow >= 0
        }
        // The Contact menu's Edit and Delete work only while the log has
        // focus. When they're off, Command-E and Command-Delete in a text
        // field do their usual jobs.
        guard view.window?.firstResponder === tableView, selectionCount > 0 else { return false }
        // Edit needs exactly one; Delete works on any number.
        return menuItem.action == #selector(deleteContact(_:)) || selectionCount == 1
    }

    // Called just before the shortcut menu opens. It's for the row that was
    // clicked: a Control-click, or VoiceOver's VO-Shift-M (which simulates
    // a right-click on the row under the VoiceOver cursor). If there was no
    // click at all, it's for the selected row.
    func menuNeedsUpdate(_ menu: NSMenu) {
        shortcutMenuRow = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
    }

    // The row a command is for: the shortcut menu's row, the double-clicked
    // row, or otherwise the selected row.
    private func targetRow(_ sender: Any?) -> Int {
        if isFromShortcutMenu(sender) { return shortcutMenuRow }
        if (sender as AnyObject?) === tableView { return tableView.clickedRow }
        return tableView.selectedRow
    }

    // MARK: - Rows and contacts

    // The table shows `rows` (newest first, perhaps only one call); the
    // logbook keeps every contact oldest first. These find one in the other.
    private func contact(atRow row: Int) -> QSO? {
        guard row >= 0, row < rows.count else { return nil }
        return rows[row]
    }

    private func row(for id: UUID) -> Int? {
        rows.firstIndex { $0.id == id }
    }

    // Highlights a contact without moving focus to the log (the logging
    // form shows which contact it's correcting this way).
    func highlight(id: UUID) {
        showAllContacts()
        select(id: id)
    }

    private func select(id: UUID) {
        guard let row = row(for: id) else { return }
        select(row: row)
    }

    private func select(row: Int) {
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func isFromShortcutMenu(_ sender: Any?) -> Bool {
        (sender as? NSMenuItem)?.menu === tableView.menu
    }

    // MARK: - Table data (macOS asks for these as it draws)

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn,
              let column = columns.first(where: { $0.id == tableColumn.identifier.rawValue }),
              let qso = contact(atRow: row) else { return nil }

        // Reuse a cell that has scrolled out of view, or make a new one.
        let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? LogCellView
            ?? LogCellView(identifier: tableColumn.identifier)
        cell.textField?.stringValue = column.text(qso)
        let id = qso.id
        cell.deleteAction = { [weak self] in self?.delete(id: id) }
        cell.editAction = { [weak self] in self?.openEditor(id: id) }
        return cell
    }
}

// The table itself, with Return, Delete and Escape added.
final class LogTableView: NSTableView {
    var onDelete: (() -> Void)?
    var onEdit: (() -> Void)?
    var onEscape: (() -> Void)?
    var onTab: (() -> Void)?
    var onBackTab: (() -> Void)?
    // Left and Right Arrow: choose a column (-1 or +1). With Option and
    // Command: move the chosen column.
    var onColumnStep: ((Int) -> Void)?
    var onColumnMove: ((Int) -> Void)?

    // Key codes are the physical keys: 51 is Delete (Backspace), 117 is
    // Forward Delete (Fn-Delete), 53 is Escape, 36 is Return and 76 is
    // Enter on a numeric keypad, 48 is Tab, 123 and 124 are Left and Right
    // Arrow.
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        // ("where" applies to each key separately, so it's written twice.)
        case 51 where modifiers.isEmpty, 117 where modifiers.isEmpty:
            onDelete?()
        case 53:
            onEscape?()
        case 36 where modifiers.isEmpty, 76 where modifiers.isEmpty:
            onEdit?()
        case 48 where modifiers.isEmpty && onTab != nil:
            onTab?()
        case 48 where modifiers == .shift && onBackTab != nil:
            onBackTab?()
        case 123 where modifiers.isEmpty && onColumnStep != nil:
            onColumnStep?(-1)
        case 124 where modifiers.isEmpty && onColumnStep != nil:
            onColumnStep?(1)
        case 123 where modifiers == [.command, .option] && onColumnMove != nil:
            onColumnMove?(-1)
        case 124 where modifiers == [.command, .option] && onColumnMove != nil:
            onColumnMove?(1)
        default:
            super.keyDown(with: event)
        }
    }
}

// One cell of the table: a line of text, plus Edit Contact and Delete
// Contact in VoiceOver's Actions rotor, and "press" to edit.
//
// Where VoiceOver actually lands: not on this cell view, and not on the
// text label inside it, but on the label's inner "cell" object
// (LogTextCell, below). macOS leaves the cell view out of what VoiceOver
// sees. A test that prints what VoiceOver sees showed this on 2026-11-14.
// So the actions are defined here and passed on by LogTextCell.
//
// (VO-Shift-M doesn't come here: VoiceOver opens the table's shortcut
// menu with a simulated right-click on the row. See menuNeedsUpdate.)
final class LogCellView: NSTableCellView {
    var deleteAction: (() -> Void)?
    var editAction: (() -> Void)?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        let label = CellLabel(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        var actions: [NSAccessibilityCustomAction] = []
        if let editAction {
            actions.append(NSAccessibilityCustomAction(name: "Edit Contact") { editAction(); return true })
        }
        if let deleteAction {
            actions.append(NSAccessibilityCustomAction(name: "Delete Contact") { deleteAction(); return true })
        }
        return actions
    }

    override func accessibilityPerformPress() -> Bool {
        editAction?()
        return editAction != nil
    }
}

// The cell's text label. Its only change is to use LogTextCell inside.
final class CellLabel: NSTextField {
    override class var cellClass: AnyClass? {
        get { LogTextCell.self }
        set {}
    }
}

// What VoiceOver lands on in a row. It reads the text as usual, and passes
// the actions and "press" on to the LogCellView.
final class LogTextCell: NSTextFieldCell {
    private var owner: LogCellView? { controlView?.superview as? LogCellView }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        owner?.accessibilityCustomActions()
    }

    override func accessibilityPerformPress() -> Bool {
        owner?.accessibilityPerformPress() ?? false
    }

    // An empty cell (no RST sent, no name yet) says "blank", as VoiceOver
    // does for an empty text field, rather than nothing at all, which
    // sounds like VO-Right didn't move. Apple's audit flagged these as
    // "no description" (16 November 2026). Cells with text keep the
    // usual reading: their text, with no label added.
    // With Settings > Log Columns' "Say the column name with each value"
    // on, the column's name comes first: "RST sent, 599", "Comment,
    // blank". VoiceOver says a cell's value before its own heading, so
    // heard as a run, each heading seemed to belong to the next value.
    // The name goes into the value VoiceOver reads, not into a label
    // beside it, so a cell is read once ("RST sent, 599"), not twice.
    private var heading: String? {
        guard Settings.logCellHeadings, let id = owner?.identifier?.rawValue else { return nil }
        return LogTableViewController.columnTitle(for: id)
    }

    override func accessibilityLabel() -> String? {
        if heading != nil { return nil }
        return stringValue.isEmpty ? "blank" : super.accessibilityLabel()
    }

    override func accessibilityValue() -> Any? {
        guard let heading else { return super.accessibilityValue() }
        return "\(heading), \(stringValue.isEmpty ? "blank" : stringValue)"
    }

}

// Hears whether Mail took a card (QSL > Send QSL Card): true once the new
// message has it, false if it couldn't be made.
@MainActor
final class CardMail: NSObject, NSSharingServiceDelegate {
    private let done: (Bool) -> Void
    init(done: @escaping (Bool) -> Void) { self.done = done }

    nonisolated func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        MainActor.assumeIsolated { done(true) }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any],
                                    error: Error) {
        MainActor.assumeIsolated { done(false) }
    }
}
