// BandPlanWindowController.swift
//
// Window > Band Plan (Command-6; v1.6 item 6): the band plan chosen in
// Settings > Band Plan as a list, one line each, low to high, so
// VoiceOver reads a segment in one stop:
//
//   "14.000 to 14.025 MHz, 20 meters: CW and data. Extra only."
//   "14.074 MHz, 20 meters: FT8."
//
// Above the list, Band, Class and Mode narrow it: Class starts on your
// license class, and shows the segments that class may use and the
// activities inside them. A line above says where the radio is: "Radio:
// 14.074 MHz: CW and data for Extra. FT8."
//   Up, Down   through the list
//   Return     tunes the radio there: an activity's frequency, or 5 kHz
//              into a segment (the middle of a narrow one), never its edge
//   Escape     back to the logging window
//   Tab        the list, Band, Class, Mode, then back
// The choices are remembered, apart from Class, which starts on yours.

import AppKit

@MainActor
final class BandPlanWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var onEscape: (() -> Void)?

    private struct Row {
        var line: String
        var hertz: Int   // where Return tunes
        var low: Int
        var high: Int
    }

    private let table = SpotsTableView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let bandMenu = NSPopUpButton()
    private let classMenu = NSPopUpButton()
    private let modeMenu = NSPopUpButton()
    private var plan = BandWarning.shared.plan
    private var bands: [String] = []
    private var rows: [Row] = []

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Band Plan"
        window.contentMinSize = NSSize(width: 480, height: 360)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("BandPlanWindow")
        super.init(window: window)
        window.delegate = self
        window.contentView = build()
        window.initialFirstResponder = table
        if !window.setFrameUsingName("BandPlanWindow") { window.center() }
        NotificationCenter.default.addObserver(forName: RadioMonitor.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard self?.window?.isVisible == true else { return }
                self?.showRadio()
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    func show() {
        // The plan as Settings has it now (a file may have changed).
        BandWarning.shared.reloadPlan()
        plan = BandWarning.shared.plan
        fillMenus()
        reload()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(table)
        // The line for where the radio is, if it's in the list.
        if let hertz = RadioMonitor.shared.reading?.hertz,
           let row = rows.firstIndex(where: { hertz >= $0.low && hertz <= $0.high }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
    }

    private func build() -> NSView {
        let heading = NSTextField(labelWithString: "Band Plan")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        let note = NSTextField(wrappingLabelWithString:
            "Each line is a range and who may use it for what, or an activity frequency. Band, Class and "
            + "Mode narrow the list; Class starts on your license class (Settings > Band Plan). Return tunes "
            + "the radio there. Activities are where things usually happen and give no privileges.")
        note.preferredMaxLayoutWidth = 660
        note.isSelectable = true
        status.preferredMaxLayoutWidth = 660
        status.isSelectable = true

        bandMenu.setAccessibilityLabel("Band")
        classMenu.setAccessibilityLabel("Class")
        modeMenu.setAccessibilityLabel("Mode")
        for menu in [bandMenu, classMenu, modeMenu] {
            menu.target = self
            menu.action = #selector(filterChanged(_:))
        }
        let filters = NSStackView(views: [bandMenu, classMenu, modeMenu])
        filters.spacing = 16

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("segment"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.setAccessibilityLabel("Band plan")
        table.setAccessibilityLinkedUIElements([note])
        table.dataSource = self
        table.delegate = self
        table.onEnter = { [weak self] in self?.tune() }
        table.onEscape = { [weak self] in self?.onEscape?() }
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let order: [NSView] = [table, bandMenu, classMenu, modeMenu]
        for (index, view) in order.enumerated() { view.nextKeyView = order[(index + 1) % order.count] }

        let stack = NSStackView(views: [heading, note, filters, status, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        return stack
    }

    // The pop-ups for this plan: its bands, its classes (yours chosen),
    // and the modes.
    private func fillMenus() {
        let defaults = UserDefaults.standard
        var seen: [String] = []
        for segment in plan.segments {
            if let band = Bands.name(forHertz: segment.low), !seen.contains(band) { seen.append(band) }
        }
        bands = seen
        bandMenu.removeAllItems()
        bandMenu.addItems(withTitles: ["All bands"] + bands.map(Bands.spoken))
        bandMenu.selectItem(at: (bands.firstIndex(of: defaults.string(forKey: "bandPlan.window.band") ?? "") ?? -1) + 1)
        classMenu.removeAllItems()
        classMenu.addItems(withTitles: ["All classes"] + plan.classes)
        classMenu.selectItem(at: (plan.classes.firstIndex(of: Settings.licenseClass) ?? -1) + 1)
        modeMenu.removeAllItems()
        modeMenu.addItems(withTitles: ["All modes"] + BandPlan.Mode.allCases.map(\.title))
        modeMenu.selectItem(at: (BandPlan.Mode.allCases.firstIndex { $0.rawValue == defaults.string(forKey: "bandPlan.window.mode") } ?? -1) + 1)
    }

    private var chosenBand: String? { bandMenu.indexOfSelectedItem > 0 ? bands[bandMenu.indexOfSelectedItem - 1] : nil }
    private var chosenClass: String? {
        classMenu.indexOfSelectedItem > 0 ? plan.classes[classMenu.indexOfSelectedItem - 1] : nil
    }
    private var chosenMode: BandPlan.Mode? {
        modeMenu.indexOfSelectedItem > 0 ? BandPlan.Mode.allCases[modeMenu.indexOfSelectedItem - 1] : nil
    }

    @objc private func filterChanged(_ sender: Any?) {
        let defaults = UserDefaults.standard
        defaults.set(chosenBand ?? "", forKey: "bandPlan.window.band")
        defaults.set(chosenMode?.rawValue ?? "", forKey: "bandPlan.window.mode")
        reload()
        Speaker.announce(rows.count == 1 ? "1 line." : "\(rows.count) lines.")
    }

    // The lines, low to high, as the pop-ups say.
    private func reload() {
        let selected = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].line : nil
        let band = chosenBand, licenseClass = chosenClass, mode = chosenMode
        var found: [(sort: Int, row: Row)] = []
        for segment in plan.segments {
            if let band, Bands.name(forHertz: segment.low) != band { continue }
            if let licenseClass, !segment.classes.contains(licenseClass) { continue }
            if let mode, !segment.modes.contains(mode) { continue }
            let width = segment.high - segment.low
            let into = width > 20_000 ? 5_000 : width / 2
            found.append((segment.low, Row(line: plan.line(for: segment), hertz: segment.low + into,
                                           low: segment.low, high: segment.high)))
        }
        for activity in plan.activities {
            if let band, Bands.name(forHertz: activity.hertz) != band { continue }
            if let mode, activity.mode != mode { continue }
            // A class sees the activities inside its own privileges.
            if let licenseClass, plan.modes(at: activity.hertz, for: licenseClass).isEmpty { continue }
            found.append((activity.hertz, Row(line: plan.line(for: activity), hertz: activity.hertz,
                                              low: activity.hertz, high: activity.hertz)))
        }
        rows = found.sorted { $0.sort < $1.sort }.map(\.row)
        table.reloadData()
        if let selected, let row = rows.firstIndex(where: { $0.line == selected }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if !rows.isEmpty, table.selectedRow < 0 {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        showRadio()
    }

    private func showRadio() {
        let count = rows.count == 1 ? "1 line" : "\(rows.count) lines"
        guard let hertz = RadioMonitor.shared.reading?.hertz else {
            status.stringValue = "\(plan.name): \(count). No radio connected."
            return
        }
        status.stringValue = "\(plan.name): \(count). Radio: "
            + plan.whereYouAre(hertz, licenseClass: chosenClass ?? Settings.licenseClass)
    }

    private func tune() {
        guard rows.indices.contains(table.selectedRow) else { return }
        let row = rows[table.selectedRow]
        guard RadioMonitor.shared.reading != nil else {
            NSSound.beep()
            return Speaker.announce("No radio connected to tune.")
        }
        RadioMonitor.shared.tuneAndSay(toHertz: row.hertz)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let id = NSUserInterfaceItemIdentifier("bandPlanCell")
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
        cell.textField?.stringValue = rows[row].line
        return cell
    }
}
