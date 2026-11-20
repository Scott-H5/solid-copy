// ChoiceListViewController.swift
//
// A list for choosing which items to use and in what order: which fields
// are on the logging form (and which are Tab stops), or which columns the
// log shows. Settings uses it twice.
//
// Each row reads as one line, such as "Name: on the form, not a Tab stop"
// or "Grid square: not on the form". Items in use come first, in their
// order, when the list opens; the rest follow. Showing or hiding an item
// leaves it where it is, so nothing moves under VoiceOver's cursor (it
// used to jump to the end of the items in use, and the row you were on
// then read as a different item: Scott, 16 November 2026). The order of
// the items in use is their order in the list; Move Up and Move Down
// swap an item with the next item in use above or below it.
//
// Keys, with the list focused:
//   - Up and Down move between items.
//   - Space shows or hides the selected item.
//   - Option-Command-Up and Option-Command-Down move it up or down.
//   - Escape closes Settings.
// The same commands, plus Make Tab Stop or Remove Tab Stop where that
// applies, are in VoiceOver's Actions rotor (VO-Command-Space), in the
// shortcut menu (VO-Shift-M), and as buttons under the list. Each change
// is spoken, since nothing else moves.

import AppKit

@MainActor
final class ChoiceListViewController: NSViewController,
    NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, NSMenuItemValidation {

    struct Item {
        let id: String
        let title: String
        var shown: Bool
        var tabStop: Bool
        // Always shown, can't be moved (the Call column).
        var fixed = false
        // Extra words at the end of the row, such as "starts as 5".
        var note = ""
    }

    // Called after every change, with the items in use, in order.
    var onChange: (([Item]) -> Void)?
    // Called when Escape is pressed.
    var onEscape: (() -> Void)?
    // Called when a different item is selected (nil for none).
    var onSelectionChange: ((Item?) -> Void)?

    // The selected item, if any.
    var selectedItem: Item? {
        items.indices.contains(tableView.selectedRow) ? items[tableView.selectedRow] : nil
    }

    // Changes an item's note (shown at the end of its row) and redraws it.
    func setNote(_ note: String, for id: String) {
        guard let row = items.firstIndex(where: { $0.id == id }) else { return }
        items[row].note = note
        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
    }

    private var items: [Item]
    private let offersTabStop: Bool
    // Words for the row text: "on the form" / "shown".
    private let shownWord: String
    private let hiddenWord: String
    private let listName: String
    private let tableView = ChoiceTableView()
    private var menuRow = -1

    // `items` is every possible item: those in use, in order, with shown
    // set, then the rest.
    init(items: [Item], listName: String, shownWord: String, hiddenWord: String, offersTabStop: Bool) {
        self.items = items
        self.listName = listName
        self.shownWord = shownWord
        self.hiddenWord = hiddenWord
        self.offersTabStop = offersTabStop
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    var list: NSView { tableView }

    // MARK: - Building

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = false
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.setAccessibilityLabel(listName)
        tableView.onSpace = { [weak self] in self?.toggleShown(nil) }
        tableView.onMove = { [weak self] up in up ? self?.moveItemUp(nil) : self?.moveItemDown(nil) }
        tableView.onEscape = { [weak self] in self?.onEscape?() }

        let menu = NSMenu()
        menu.allowsContextMenuPlugIns = false
        if #available(macOS 15.2, *) { menu.automaticallyInsertsWritingToolsItems = false }
        menu.delegate = self
        tableView.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: 300).isActive = true
        scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 480).isActive = true

        var buttons = [NSButton(title: "Show or Hide", target: self, action: #selector(toggleShown(_:)))]
        if offersTabStop {
            buttons.append(NSButton(title: "Tab Stop On or Off", target: self, action: #selector(toggleTabStop(_:))))
        }
        buttons += [NSButton(title: "Move Up", target: self, action: #selector(moveItemUp(_:))),
                    NSButton(title: "Move Down", target: self, action: #selector(moveItemDown(_:)))]
        let buttonRow = NSStackView(views: buttons)
        buttonRow.spacing = 8

        let help = NSTextField(wrappingLabelWithString:
            "Space shows or hides the selected item. Option-Command-Up and Down move it."
            + (offersTabStop ? " Make Tab Stop is in the Actions rotor and the shortcut menu." : ""))
        help.preferredMaxLayoutWidth = 480

        let stack = NSStackView(views: [scroll, buttonRow, help])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        view = stack
        if !items.isEmpty { tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
    }

    // MARK: - Commands

    @objc func toggleShown(_ sender: Any?) {
        let row = targetRow(sender)
        guard items.indices.contains(row), !items[row].fixed else { return say("That one is always shown.") }
        items[row].shown.toggle()
        changed(selecting: items[row].id)
        say(describe(items[row]))
    }

    @objc func toggleTabStop(_ sender: Any?) {
        let row = targetRow(sender)
        guard offersTabStop, items.indices.contains(row) else { return }
        guard items[row].shown else { return say("Show it on the form first.") }
        items[row].tabStop.toggle()
        changed(selecting: items[row].id)
        say(describe(items[row]))
    }

    @objc func moveItemUp(_ sender: Any?) { move(by: -1, row: targetRow(sender)) }
    @objc func moveItemDown(_ sender: Any?) { move(by: 1, row: targetRow(sender)) }

    private func move(by offset: Int, row: Int) {
        guard items.indices.contains(row) else { return }
        let item = items[row]
        guard item.shown else { return say("Only items in use can be moved. Press Space to use it.") }
        // Its place among the items in use, and the one it swaps with.
        let used = items.indices.filter { items[$0].shown }
        guard let place = used.firstIndex(of: row) else { return }
        let target = place + offset
        guard !item.fixed, used.indices.contains(target), !items[used[target]].fixed else {
            return say(offset < 0 ? "Already at the top." : "Already at the bottom.")
        }
        items.swapAt(row, used[target])
        changed(selecting: item.id)
        say("\(item.title), now \(target + 1) of \(used.count).")
    }

    private func changed(selecting id: String) {
        tableView.reloadData()
        if let row = items.firstIndex(where: { $0.id == id }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        }
        onChange?(items.filter(\.shown))
    }

    // "Name: on the form, not a Tab stop", "Power (watts): on the form, Tab
    // stop, starts as 5"
    private func describe(_ item: Item) -> String {
        guard item.shown else { return "\(item.title): \(hiddenWord)" }
        var text = "\(item.title): \(shownWord)"
        if offersTabStop { text += ", \(item.tabStop ? "Tab stop" : "not a Tab stop")" }
        if !item.note.isEmpty { text += ", \(item.note)" }
        return text
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        onSelectionChange?(selectedItem)
    }

    private func say(_ text: String) { Speaker.announce(text) }

    private func targetRow(_ sender: Any?) -> Int {
        (sender as? NSMenuItem)?.menu === tableView.menu ? menuRow : tableView.selectedRow
    }

    // The actions for a row, for the Actions rotor and the shortcut menu.
    private func actionTitles(for item: Item) -> [(String, Selector)] {
        var actions: [(String, Selector)] = []
        if !item.fixed {
            actions.append((item.shown ? "Hide" : "Show", #selector(toggleShown(_:))))
        }
        if offersTabStop, item.shown {
            actions.append((item.tabStop ? "Remove Tab Stop" : "Make Tab Stop", #selector(toggleTabStop(_:))))
        }
        if item.shown, !item.fixed {
            actions += [("Move Up", #selector(moveItemUp(_:))), ("Move Down", #selector(moveItemDown(_:)))]
        }
        return actions
    }

    // MARK: - Shortcut menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menuRow = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        menu.removeAllItems()
        guard items.indices.contains(menuRow) else { return }
        for (title, action) in actionTitles(for: items[menuRow]) {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { true }

    // MARK: - Table data

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("choiceCell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = id
            let label = ActionLabel(labelWithString: "")
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
        let item = items[row]
        cell.textField?.stringValue = describe(item)
        // The Actions rotor (on the text cell, which is where VoiceOver
        // lands; see LogTableViewController.swift).
        let itemID = item.id
        (cell.textField?.cell as? ActionTextCell)?.actions = { [weak self] in
            guard let self, let row = self.items.firstIndex(where: { $0.id == itemID }) else { return [] }
            return self.actionTitles(for: self.items[row]).map { title, action in
                NSAccessibilityCustomAction(name: title) { [weak self] in
                    guard let self else { return false }
                    self.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    self.perform(action, with: nil)
                    return true
                }
            }
        }
        return cell
    }
}

// The list, with Space, Option-Command-Up/Down and Escape added.
final class ChoiceTableView: NSTableView {
    var onSpace: (() -> Void)?
    var onMove: ((Bool) -> Void)?
    var onEscape: (() -> Void)?

    // Key codes: 49 is Space, 126 Up Arrow, 125 Down Arrow, 53 Escape.
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        case 49 where modifiers.isEmpty: onSpace?()
        case 126 where modifiers == [.command, .option]: onMove?(true)
        case 125 where modifiers == [.command, .option]: onMove?(false)
        case 53: onEscape?()
        default: super.keyDown(with: event)
        }
    }
}

// A text label whose accessibility element (its cell; VoiceOver lands on
// cells, not on the label itself) offers custom actions.
final class ActionLabel: NSTextField {
    override class var cellClass: AnyClass? {
        get { ActionTextCell.self }
        set {}
    }
}

final class ActionTextCell: NSTextFieldCell {
    var actions: (() -> [NSAccessibilityCustomAction])?

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        actions?()
    }
}
