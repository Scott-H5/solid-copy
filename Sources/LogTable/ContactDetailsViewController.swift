// ContactDetailsViewController.swift
//
// The details panel under the log: every filled-in field of the selected
// contact, one per line ("Name: Hiram Percy", "Grid square: FN31pr").
// Empty fields are left out, so the list stays short.
//
// Why one line per field, as "Label: value"? So VoiceOver reads each field
// in one stop, with its name, and Up and Down move through them. A layout
// with labels and values in separate columns would make VoiceOver stop
// twice per field, or read only the value.
//
// Keys (accessibility contract, rule 22):
//   - Tab in the log, or Option-Command-I anywhere, comes here.
//   - Up and Down move between fields.
//   - Command-C copies the selected field's value.
//   - Escape, Tab or Shift-Tab goes back to the log, on the same contact.
//     So Tab moves back and forth between the log and the details.

import AppKit

@MainActor
final class ContactDetailsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    // Called when you leave the panel (Escape or Shift-Tab).
    var onLeave: (() -> Void)?

    private let tableView = DetailsTableView()
    // What's shown: a label and a value for each line.
    private var lines: [(label: String, value: String)] = []
    private var shownID: UUID?

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("detail"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.onLeave = { [weak self] in self?.onLeave?() }
        tableView.onCopy = { [weak self] in self?.copySelectedValue() }

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        view = scrollView
        show(nil)
    }

    // Shows a contact's fields, or a message when no contact is selected.
    func show(_ qso: QSO?) {
        guard let qso else {
            lines = [("", "No contact selected.")]
            shownID = nil
            tableView.setAccessibilityLabel("Details")
            tableView.reloadData()
            return
        }
        lines = Self.lines(for: qso)
        tableView.setAccessibilityLabel("Details for \(qso.call)")
        // Keep your place when the same contact is redrawn (after an edit);
        // start at the top for a different contact.
        let sameContact = qso.id == shownID
        let row = tableView.selectedRow
        shownID = qso.id
        tableView.reloadData()
        if sameContact, row >= 0, row < lines.count {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
    }

    // Shows a message instead of a contact (when several are selected).
    func showMessage(_ message: String) {
        lines = [("", message)]
        shownID = nil
        tableView.setAccessibilityLabel("Details")
        tableView.reloadData()
    }

    // Moves focus here, on the first field if none is selected.
    func focus() {
        if tableView.selectedRow < 0, !lines.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        tableView.scrollRowToVisible(max(tableView.selectedRow, 0))
        view.window?.makeFirstResponder(tableView)
    }

    // Call, date and time first, then the QSL line (QSL.swift: whether
    // it's confirmed and how), then every filled-in field in the order of
    // LogField.swift. Line breaks (in Notes or Address) are shown as " / "
    // so each field stays on one line. QSL fields are in words ("Card
    // received: Yes", not "Y").
    static func lines(for qso: QSO) -> [(label: String, value: String)] {
        var lines: [(label: String, value: String)] = [
            ("Call", qso.call),
            ("Date (UTC)", qso.utcDateText),
            ("Time (UTC)", qso.utcTimeWithSeconds),
            ("QSL", QSL.summary(qso)),
        ]
        for field in LogField.all {
            let value = qso[field.adif]
            guard !value.isEmpty else { continue }
            let shown = QSL.display(field: field.adif, value: value)
            lines.append((field.label, shown.replacingOccurrences(of: "\n", with: " / ")))
        }
        return lines
    }

    // Command-C: copies the value (not the label) of the selected line.
    private func copySelectedValue() {
        let row = tableView.selectedRow
        guard row >= 0, row < lines.count else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines[row].value, forType: .string)
        Speaker.announce("Copied.")
    }

    // MARK: - Table data

    func numberOfRows(in tableView: NSTableView) -> Int {
        lines.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("detailCell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = id
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        let line = lines[row]
        cell.textField?.stringValue = line.label.isEmpty ? line.value : "\(line.label): \(line.value)"
        return cell
    }
}

// The details list, with Escape, Tab, Shift-Tab and Command-C added.
final class DetailsTableView: NSTableView {
    var onLeave: (() -> Void)?
    var onCopy: (() -> Void)?

    // Key codes: 53 is Escape, 48 is Tab.
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        case 53:
            onLeave?()
        case 48 where modifiers.isEmpty || modifiers == .shift:
            onLeave?()
        default:
            super.keyDown(with: event)
        }
    }

    // Edit > Copy (Command-C) arrives here when the list has focus.
    @objc func copy(_ sender: Any?) {
        onCopy?()
    }
}
