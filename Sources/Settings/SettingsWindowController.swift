// SettingsWindowController.swift
//
// The Settings window (Solid Copy > Settings…, Command-comma), laid out
// like System Settings: a list of sections down the left (the sidebar),
// and the chosen section on the right, in an area that scrolls when it's
// taller than the window. Command-1 to Command-9 go to a section, with
// focus on its first control.
//
// The sidebar, for VoiceOver, is a list called "Settings sections". Up and
// Down choose a section (it shows at once; focus stays in the list), and
// Return or Right Arrow go into it. Tab goes from the sidebar into the
// section and round it, then back to the sidebar; Shift-Tab goes the
// other way. A list scales better than tabs as sections are added (keyer,
// contest, QSL, ...), and it's the layout sighted people know from System
// Settings.
//
// Section 1, Lookup:
//   - Look up each callsign when you leave the Callsign field (on/off).
//   - QRZ username and password, and a Save and Test button that logs in
//     and says whether the account is free (a few fields) or has an XML
//     subscription (everything). The password goes in the Keychain.
//   - Use callook.info for US calls (free, no account).
//
// Section 2, Profiles: choose, rename, add and delete operating profiles, and
// each one's station details (see ProfilesViewController.swift).
//
// Section 3, Logging Form: the profile in use's form: which fields are on it
// after Callsign, in what order, which are Tab stops, and what each starts
// as (see ChoiceListViewController.swift).
//
// Section 4, Log Columns: which columns the log shows, and in what order. Call
// is always first.
//
// Section 5, Radio: your radios and the one in use, read through rigctld (see
// RadioViewController.swift).
//
// Section 6, Speech: how much is said for lookups, logging and radio
// changes (see Speaker.swift), each a pop-up menu, saved as you choose.
//
// Section 7, Spots: the DX cluster.
//
// Section 8, Uploads: LoTW (login, TQSL station location, the folder TQSL
// uses) and QRZ Logbook (its API key), and for each, whether new contacts
// go up by themselves (see UploadsSettingsViewController.swift).
//
// Section 9, Clubs: SKCC's member list, and names for your own club
// fields (see ClubsSettingsViewController.swift).
//
// Section 10, Backups: a second folder for copies of the log (see
// BackupsSettingsViewController.swift). No Command-number (they stop at
// 9); choose it in the sidebar, or File > Back Up Now does the work.
//
// Section 11, CW: the WinKeyer's port and speed, and the messages F1 to
// F8 send (see CWSettingsViewController.swift). Also in the CW menu.
//
// Keys: it opens in the QRZ username field. Tab moves through the text
// fields (and the checkboxes and button too, if Keyboard navigation is on
// in System Settings). Escape or Command-W closes it. Everything except
// the QRZ login is saved as soon as you change it; the login is saved by
// Save and Test, or when the window closes.

import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate,
    NSTableViewDataSource, NSTableViewDelegate {

    // One section: its name in the sidebar, its contents, and the control
    // focus goes to when you go into it.
    private struct Section {
        let title: String
        let view: () -> NSView
        let firstControl: () -> NSView?
    }
    private var sections: [Section] = []
    private var current = 0

    // The sidebar, and the scrolling area the section is shown in.
    private let sidebar = SidebarTableView()
    private let content = NSScrollView()
    // Where the sidebar was spliced into the shown section's Tab loop,
    // so it can be put back when another section is shown.
    private var splice: (view: NSView, next: NSView?)?
    private var formList: ChoiceListViewController?
    private var columnList: ChoiceListViewController?
    private let profiles = ProfilesViewController()
    private let radio = RadioViewController()
    private let uploads = UploadsSettingsViewController()
    private let clubs = ClubsSettingsViewController()
    let backups = BackupsSettingsViewController()
    private let cw = CWSettingsViewController()
    private let card = QSLCardSettingsViewController()

    // The Logging Form tab's heading ("Logging form for the Home profile"),
    // and the Starting value field for the selected field.
    private let formHeading = NSTextField(labelWithString: "")
    private let startingValueField = NSTextField(string: "")
    // The Logging Form section, rebuilt when the profile changes.
    private var formView = NSView()
    // The Log Columns section, rebuilt when a club field is named.
    private var columnsView = NSView()

    private let lookupBox = NSButton(checkboxWithTitle: "Look up each callsign when you leave the Callsign field",
                                     target: nil, action: nil)
    private let usernameField = NSTextField(string: "")
    private let passwordField = NSSecureTextField(string: "")
    private let testButton = NSButton(title: "Save and Test QRZ Login", target: nil, action: nil)
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    // Settings > Speech: one pop-up per kind of message, in Kind order.
    private var speechMenus: [NSPopUpButton] = []
    // Settings > Speech, Sounds: the dupe and needed sounds, and which DX
    // spots play the needed one.
    private var alertMenus: [NSPopUpButton] = []
    private let spotSoundMenu = NSPopUpButton()

    // Settings > Spots: the DX cluster.
    private let clusterBox = NSButton(checkboxWithTitle: "Get DX cluster spots in the Spots window",
                                      target: nil, action: nil)
    private let skimmerBox = NSButton(checkboxWithTitle: "Include skimmer spots (CW heard by machine, many)",
                                      target: nil, action: nil)
    private let ft8Box = NSButton(checkboxWithTitle: "Include FT8 and FT4 spots (many)", target: nil, action: nil)
    private let nodeMenu = NSPopUpButton()
    private let hostField = NSTextField(string: "")
    private let portField = NSTextField(string: "")

    private func buildSpots() -> NSView {
        let heading = NSTextField(labelWithString: "DX cluster")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        let note = NSTextField(wrappingLabelWithString:
            "A DX cluster passes on spots from hams everywhere, thousands an hour. Solid Copy logs in with the "
            + "callsign in the profile in use, only while the Spots window is open. Each spot says its country "
            + "and whether you need it: a new country, or a new band or mode for one.")
        note.preferredMaxLayoutWidth = 520
        clusterBox.state = Settings.clusterEnabled ? .on : .off
        skimmerBox.state = Settings.clusterSkimmer ? .on : .off
        ft8Box.state = Settings.clusterFT8 ? .on : .off
        for box in [skimmerBox, ft8Box] {
            box.target = self
            box.action = #selector(clusterKindsChanged(_:))
        }
        nodeMenu.setAccessibilityLabel("Node")
        nodeMenu.addItems(withTitles: DXCluster.nodes.map(\.name) + ["Other (type its address below)"])
        hostField.stringValue = Settings.clusterHost
        hostField.setAccessibilityLabel("Node address")
        portField.stringValue = String(Settings.clusterPort)
        portField.setAccessibilityLabel("Port")
        portField.widthAnchor.constraint(equalToConstant: 80).isActive = true
        hostField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        showChosenNode()
        clusterBox.target = self
        clusterBox.action = #selector(clusterChanged(_:))
        nodeMenu.target = self
        nodeMenu.action = #selector(nodeChosen(_:))
        hostField.delegate = self
        portField.delegate = self
        let grid = NSGridView(views: [[FieldLabel("Node"), nodeMenu], [FieldLabel("Node address"), hostField],
                                      [FieldLabel("Port"), portField]])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.rowAlignment = .firstBaseline
        let order: [NSView] = [clusterBox, skimmerBox, ft8Box, nodeMenu, hostField, portField]
        for (index, view) in order.enumerated() { view.nextKeyView = order[(index + 1) % order.count] }
        let stack = NSStackView(views: [heading, note, clusterBox, skimmerBox, ft8Box, grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        return stack
    }

    // The node pop-up shows the ready-made node in use, or Other.
    private func showChosenNode() {
        let index = DXCluster.nodes.firstIndex { $0.host == Settings.clusterHost && $0.port == Settings.clusterPort }
        nodeMenu.selectItem(at: index ?? DXCluster.nodes.count)
    }

    @objc private func clusterChanged(_ sender: Any?) {
        Settings.clusterEnabled = clusterBox.state == .on
        SpotList.shared.applyClusterSettings()
        Speaker.announce(Settings.clusterEnabled
            ? "DX cluster spots on, while the Spots window is open." : "DX cluster spots off.")
    }

    @objc private func clusterKindsChanged(_ sender: NSButton) {
        Settings.clusterSkimmer = skimmerBox.state == .on
        Settings.clusterFT8 = ft8Box.state == .on
        SpotList.shared.applyClusterSettings()
        Speaker.announce("\(sender === skimmerBox ? "Skimmer" : "FT8 and FT4") spots \(sender.state == .on ? "on" : "off").")
    }

    @objc private func nodeChosen(_ sender: Any?) {
        let index = nodeMenu.indexOfSelectedItem
        guard DXCluster.nodes.indices.contains(index) else {
            // Other: type it.
            window?.makeFirstResponder(hostField)
            return
        }
        let node = DXCluster.nodes[index]
        Settings.clusterHost = node.host
        Settings.clusterPort = node.port
        hostField.stringValue = node.host
        portField.stringValue = String(node.port)
        SpotList.shared.applyClusterSettings()
    }

    // The node's address or port typed: saved on leaving the field.
    private func saveNode() {
        let host = hostField.stringValue.trimmingCharacters(in: .whitespaces)
        guard let port = Int(portField.stringValue.trimmingCharacters(in: .whitespaces)), (1...65_535).contains(port),
              !host.isEmpty else {
            NSSound.beep()
            Speaker.announce("The node needs an address and a port from 1 to 65535.")
            return
        }
        guard host != Settings.clusterHost || port != Settings.clusterPort else { return }
        Settings.clusterHost = host
        Settings.clusterPort = port
        showChosenNode()
        SpotList.shared.applyClusterSettings()
    }

    private let parkStatus = NSTextField(wrappingLabelWithString: "")
    private let parkButton = NSButton(title: "Get the Park List Now", target: nil, action: nil)

    // Settings > Lookup > Get the Park List Now: fetches POTA's list and
    // says how it went.
    @objc private func updateParks(_ sender: Any?) {
        parkStatus.stringValue = "Getting POTA's park list…"
        Speaker.announce("Getting POTA's park list.")
        ParkList.shared.update { [weak self] result in
            switch result {
            case .success(let count):
                self?.parkStatus.stringValue = ParkList.shared.summary
                Speaker.announce("Park list ready: \(count.formatted()) parks.")
            case .failure(let error):
                self?.parkStatus.stringValue = "Couldn't get the park list. \(error.localizedDescription)"
                Speaker.announce("Couldn't get the park list. \(error.localizedDescription)")
            }
        }
    }

    private let callookBox = NSButton(checkboxWithTitle: "Use callook.info for US calls (free, no account needed)",
                                      target: nil, action: nil)

    init() {
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 640),
                                    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.contentMinSize = NSSize(width: 720, height: 420)
        super.init(window: window)
        window.delegate = self
        window.contentView = buildWindow()
        window.initialFirstResponder = usernameField
        window.center()
        window.onEscape = { [weak self] in self?.window?.performClose(nil) }
        window.onTabNumber = { [weak self] number in self?.showTab(number: number) }
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    // Shows the window with current settings, focus in the QRZ username.
    func show() {
        lookupBox.state = Settings.lookupEnabled ? .on : .off
        callookBox.state = Settings.useCallook ? .on : .off
        usernameField.stringValue = Settings.qrzUsername
        passwordField.stringValue = Settings.qrzPassword
        profiles.refresh()
        radio.refresh()
        uploads.refresh()
        clubs.refresh()
        backups.refresh()
        cw.refresh()
        card.refresh()
        reloadFormList()
        if statusLabel.stringValue.isEmpty {
            statusLabel.stringValue = Settings.qrzUsername.isEmpty
                ? "QRZ isn't set up. Add your QRZ username and password, then press Save and Test."
                : "QRZ login saved for \(Settings.qrzUsername)."
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        showSection(current, focusInside: true)
    }

    // Goes to a section by its name in the sidebar ("CW"), for sections
    // past 9, which have no Command-number.
    func showSection(named title: String) {
        guard let index = sections.firstIndex(where: { $0.title == title }) else { return }
        showSection(index, focusInside: true)
    }

    // Goes to a section by number (1 is Lookup), focus on its first control.
    func showTab(number: Int) {
        guard number >= 1, number <= sections.count else { return }
        showSection(number - 1, focusInside: true)
    }

    // Settings > Uploads with focus straight in a service's login (the QRZ
    // Logbook API key, the Club Log token, the eQSL username), so pasting
    // it is one menu command and Command-V, not a Tab past every LoTW
    // control. (The field is in the section's Tab loop like any other, so
    // Tab and Shift-Tab carry on from there as usual.)
    func showLogin(for service: UploadService) {
        guard let index = sections.firstIndex(where: { $0.title == "Uploads" }) else { return }
        show()
        showSection(index, focusInside: true)
        window?.makeFirstResponder(uploads.loginControl(for: service))
    }

    // MARK: - Building the window

    private func buildWindow() -> NSView {
        let lookupView = buildContent()
        // Build every section now, not when first shown: show() refreshes
        // Profiles and Radio each time the window opens, and refreshing one
        // whose controls don't exist yet crashes (it did, 15 November 2026).
        _ = profiles.view
        _ = radio.view
        profiles.onProfileChange = { [weak self] in self?.reloadFormList() }
        profiles.onEscape = { [weak self] in self?.window?.performClose(nil) }
        reloadFormList()
        reloadColumnList()
        radio.onEscape = { [weak self] in self?.window?.performClose(nil) }
        let speechView = buildSpeech()
        let spotsView = buildSpots()
        _ = uploads.view
        uploads.onEscape = { [weak self] in self?.window?.performClose(nil) }
        _ = clubs.view
        _ = backups.view
        _ = cw.view
        cw.onEscape = { [weak self] in self?.window?.performClose(nil) }
        _ = card.view
        card.onEscape = { [weak self] in self?.window?.performClose(nil) }
        backups.onEscape = { [weak self] in self?.window?.performClose(nil) }
        clubs.onEscape = { [weak self] in self?.window?.performClose(nil) }
        // A club field named or renamed: the form and column lists show it.
        clubs.onNamesChanged = { [weak self] in
            self?.reloadFormList()
            self?.reloadColumnList()
            self?.card.reloadList()
        }

        sections = [
            Section(title: "Lookup", view: { lookupView }, firstControl: { [unowned self] in usernameField }),
            Section(title: "Profiles", view: { [unowned self] in profiles.view },
                    firstControl: { [unowned self] in profiles.firstControl }),
            Section(title: "Logging Form", view: { [unowned self] in formView },
                    firstControl: { [unowned self] in formList?.list }),
            Section(title: "Log Columns", view: { [unowned self] in columnsView },
                    firstControl: { [unowned self] in columnList?.list }),
            Section(title: "Radio", view: { [unowned self] in radio.view },
                    firstControl: { [unowned self] in radio.firstControl }),
            Section(title: "Speech", view: { speechView },
                    firstControl: { [unowned self] in speechMenus.first }),
            Section(title: "Spots", view: { spotsView },
                    firstControl: { [unowned self] in clusterBox }),
            Section(title: "Uploads", view: { [unowned self] in uploads.view },
                    firstControl: { [unowned self] in uploads.firstControl }),
            Section(title: "Clubs", view: { [unowned self] in clubs.view },
                    firstControl: { [unowned self] in clubs.firstControl }),
            Section(title: "Backups", view: { [unowned self] in backups.view },
                    firstControl: { [unowned self] in backups.firstControl }),
            Section(title: "CW", view: { [unowned self] in cw.view },
                    firstControl: { [unowned self] in cw.firstControl }),
            Section(title: "QSL Card", view: { [unowned self] in card.view },
                    firstControl: { [unowned self] in card.firstControl }),
        ]

        // The sidebar: one column, no header, in the source-list style
        // System Settings uses.
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section"))
        sidebar.addTableColumn(column)
        sidebar.headerView = nil
        sidebar.style = .sourceList
        sidebar.rowSizeStyle = .large
        sidebar.dataSource = self
        sidebar.delegate = self
        sidebar.setAccessibilityLabel("Settings sections")
        sidebar.onEnter = { [weak self] in self?.focusSection() }
        let sidebarScroll = NSScrollView()
        sidebarScroll.documentView = sidebar
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.drawsBackground = false
        sidebarScroll.widthAnchor.constraint(equalToConstant: 190).isActive = true

        content.hasVerticalScroller = true
        content.autohidesScrollers = true
        content.drawsBackground = false

        // A thin line between the sidebar and the section.
        let line = NSBox()
        line.boxType = .separator
        let split = NSStackView(views: [sidebarScroll, line, content])
        split.orientation = .horizontal
        split.spacing = 0
        split.distribution = .fill
        split.alignment = .height
        sidebar.reloadData()
        sidebar.selectRowIndexes(IndexSet(integer: current), byExtendingSelection: false)
        showSection(current, focusInside: false)
        return split
    }

    // MARK: - Sections

    // Shows a section on the right, and puts the sidebar into its Tab loop.
    // focusInside: focus goes to its first control (Command-number, opening
    // the window); otherwise it stays where it is (arrows in the sidebar).
    private func showSection(_ index: Int, focusInside: Bool) {
        guard sections.indices.contains(index) else { return }
        current = index
        if sidebar.selectedRow != index {
            sidebar.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        let section = sections[index]
        let view = section.view()
        if content.documentView?.subviews.first !== view {
            // A flipped holder, so the section sits at the top and grows
            // downward; its width follows the area's, its height its own.
            let holder = FlippedView()
            view.removeFromSuperview()
            view.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(view)
            holder.translatesAutoresizingMaskIntoConstraints = false
            content.documentView = holder
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: holder.topAnchor),
                view.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
                view.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
                holder.widthAnchor.constraint(equalTo: content.contentView.widthAnchor),
                holder.topAnchor.constraint(equalTo: content.contentView.topAnchor),
            ])
        }
        spliceSidebar(before: section.firstControl())
        if focusInside { focusSection() }
    }

    // Focus to the shown section's first control.
    private func focusSection() {
        guard let first = sections[current].firstControl() else { return }
        window?.makeFirstResponder(first)
    }

    // Each section's controls Tab round in a loop. This puts the sidebar
    // in that loop, just before the first control, so Tab comes back out
    // to the sidebar and Shift-Tab from the first control goes to it. The
    // last splice is undone first, so a section hidden again is as it was.
    private func spliceSidebar(before first: NSView?) {
        if let splice { splice.view.nextKeyView = splice.next }
        splice = nil
        guard let first else { return }
        // Follow the loop to the control that leads to the first one (or,
        // for a section of one control, to where the chain ends).
        var view = first
        var seen = Set<ObjectIdentifier>()
        while let next = view.nextKeyView, next !== first, seen.insert(ObjectIdentifier(next)).inserted {
            view = next
        }
        splice = (view, view.nextKeyView)
        view.nextKeyView = sidebar
        sidebar.nextKeyView = first
    }

    // The sidebar's rows.
    func numberOfRows(in tableView: NSTableView) -> Int { sections.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("sectionCell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = id
            let text = NSTextField(labelWithString: "")
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(text)
            cell.textField = text
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        cell.textField?.stringValue = sections[row].title
        return cell
    }

    // Choosing a row shows its section at once, as System Settings does.
    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = sidebar.selectedRow
        guard row >= 0, row != current else { return }
        showSection(row, focusInside: false)
    }

    private func padded(_ view: NSView) -> NSView {
        let stack = NSStackView(views: [view])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        return stack
    }

    // Builds the Logging Form tab for the profile in use: a heading, the
    // list, and the Starting value field. Rebuilt when the profile changes.
    private func reloadFormList() {
        let list = makeFormList()
        formList = list
        formHeading.stringValue = "Logging form for the \(Settings.currentProfile.name) profile"
        formHeading.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)

        startingValueField.setAccessibilityLabel("Starting value")
        startingValueField.placeholderString = "Empty"
        startingValueField.delegate = self
        startingValueField.widthAnchor.constraint(equalToConstant: 200).isActive = true
        startingValueField.removeFromSuperview()
        let startingRow = NSStackView(views: [FieldLabel("Starting value for the selected field"), startingValueField])
        startingRow.spacing = 8
        let stack = NSStackView(views: [formHeading, list.view, startingRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        formView = stack
        list.list.nextKeyView = startingValueField
        startingValueField.nextKeyView = list.list
        showStartingValue(for: list.selectedItem)
        // Showing now: put the new one in place (the old one is gone).
        if sections.indices.contains(current), sections[current].title == "Logging Form" {
            splice = nil
            showSection(current, focusInside: false)
        }
    }

    // Logging Form: every one-line field can go on the form. Those on it
    // come first, in order; each row says what it starts as, if anything.
    private func makeFormList() -> ChoiceListViewController {
        // Fields that can't go on the form (QSL statuses: LogField.canGoOnForm)
        // are left out, even if an older setting has one on it.
        let inUse = Settings.formFields.filter { LogField.named($0.adif)?.canGoOnForm == true }
        let candidates = LogField.all.filter(\.canGoOnForm)
        var items = inUse.compactMap { choice in
            LogField.named(choice.adif).map {
                ChoiceListViewController.Item(id: $0.adif, title: $0.label, shown: true, tabStop: choice.tabStop,
                                              note: Self.startingNote(choice.startingValue))
            }
        }
        items += candidates.filter { field in !inUse.contains { $0.adif == field.adif } }.map {
            ChoiceListViewController.Item(id: $0.adif, title: $0.label, shown: false, tabStop: true)
        }
        let list = ChoiceListViewController(items: items, listName: "Fields on the logging form, after Callsign",
                                            shownWord: "on the form", hiddenWord: "not on the form",
                                            offersTabStop: true)
        list.onChange = { used in
            let starting = Dictionary(Settings.formFields.map { ($0.adif, $0.startingValue) },
                                      uniquingKeysWith: { a, _ in a })
            Settings.formFields = used.map {
                FormFieldChoice(adif: $0.id, tabStop: $0.tabStop, startingValue: starting[$0.id] ?? "")
            }
        }
        list.onSelectionChange = { [weak self] item in self?.showStartingValue(for: item) }
        list.onEscape = { [weak self] in self?.window?.performClose(nil) }
        return list
    }

    private static func startingNote(_ value: String) -> String {
        value.isEmpty ? "" : "starts as \(value)"
    }

    // Shows the selected field's starting value, or disables the field for
    // one that isn't on the form.
    private func showStartingValue(for item: ChoiceListViewController.Item?) {
        let choice = item.flatMap { item in Settings.formFields.first { $0.adif == item.id } }
        startingValueField.isEnabled = choice != nil
        startingValueField.stringValue = choice?.startingValue ?? ""
    }

    // Saves the starting value when you leave its field, and shows it on
    // the field's row.
    private func saveStartingValue() {
        guard let id = formList?.selectedItem?.id,
              let index = Settings.formFields.firstIndex(where: { $0.adif == id }) else { return }
        let value = startingValueField.stringValue.trimmingCharacters(in: .whitespaces)
        var fields = Settings.formFields
        guard fields[index].startingValue != value else { return }
        fields[index].startingValue = value
        Settings.formFields = fields
        formList?.setNote(Self.startingNote(value), for: id)
        Speaker.announce(value.isEmpty ? "No starting value." : "Starts as \(value).")
    }

    // Builds (or rebuilds) the Log Columns list; if it's showing, the new
    // one takes its place.
    private func reloadColumnList() {
        let list = makeColumnList()
        columnList = list
        columnsView = padded(list.view)
        if sections.indices.contains(current), sections[current].title == "Log Columns" {
            splice = nil
            showSection(current, focusInside: false)
        }
    }

    // Log Columns: Call (always first), Date, Time, and every field
    // (but not your club fields until they're named).
    private func makeColumnList() -> ChoiceListViewController {
        let inUse = Settings.logColumns
        let all = ["call", "date", "time"] + LogField.all.filter { !$0.isUnnamedClubField }.map(\.adif)
        func item(_ id: String, shown: Bool) -> ChoiceListViewController.Item {
            ChoiceListViewController.Item(id: id, title: LogTableViewController.columnTitle(for: id),
                                          shown: shown, tabStop: false, fixed: id == "call")
        }
        var items = [item("call", shown: true)]
        items += inUse.filter { $0 != "call" && all.contains($0) }.map { item($0, shown: true) }
        items += all.filter { !inUse.contains($0) && $0 != "call" }.map { item($0, shown: false) }
        let list = ChoiceListViewController(items: items, listName: "Columns in the log",
                                            shownWord: "shown", hiddenWord: "not shown", offersTabStop: false)
        list.onChange = { used in Settings.logColumns = used.map(\.id) }
        list.onEscape = { [weak self] in self?.window?.performClose(nil) }
        return list
    }

    // The Speech section: a pop-up for each kind of message, and what the
    // other speech keys do.
    private func buildSpeech() -> NSView {
        let heading = NSTextField(labelWithString: "What Solid Copy says")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        let note = NSTextField(wrappingLabelWithString:
            "For messages that come often and can talk over a contact you're copying. "
            + "Errors and anything you ask to hear are always said in full. "
            + "Speech goes through VoiceOver, so it reaches a braille display too.")
        note.preferredMaxLayoutWidth = 520

        var rows: [[NSView]] = []
        for kind in Speaker.Kind.allCases {
            let menu = NSPopUpButton()
            menu.setAccessibilityLabel(kind.title)
            for level in kind.levels {
                menu.addItem(withTitle: level.title(for: kind))
                menu.lastItem?.representedObject = level.rawValue
            }
            menu.selectItem(at: kind.levels.firstIndex(of: Settings.speechLevel(for: kind)) ?? 0)
            menu.target = self
            menu.action = #selector(speechChanged(_:))
            menu.tag = Speaker.Kind.allCases.firstIndex(of: kind) ?? 0
            speechMenus.append(menu)
            rows.append([FieldLabel(kind.title), menu])
        }
        let grid = NSGridView(views: rows)
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.rowAlignment = .firstBaseline

        let soundsHeading = NSTextField(labelWithString: "Sounds")
        soundsHeading.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        let soundsNote = NSTextField(wrappingLabelWithString:
            "Solid Copy's own sounds, for the moments that should stand out: a dupe, and a call you need (a new "
            + "country, band or mode, typed on the form or spotted on the DX cluster). They play whatever the levels "
            + "above say, so you hear them even in Quiet Mode. Choosing one plays it.")
        soundsNote.preferredMaxLayoutWidth = 520
        var soundRows: [[NSView]] = []
        for alert in Alert.allCases {
            let menu = NSPopUpButton()
            menu.setAccessibilityLabel(alert.title)
            for choice in Alert.choices {
                menu.addItem(withTitle: choice.title)
                menu.lastItem?.representedObject = choice.id
            }
            menu.selectItem(at: Alert.choices.firstIndex { $0.id == Settings.alertSound(for: alert) } ?? 0)
            menu.target = self
            menu.action = #selector(alertSoundChanged(_:))
            menu.tag = Alert.allCases.firstIndex(of: alert) ?? 0
            alertMenus.append(menu)
            soundRows.append([FieldLabel(alert.title), menu])
        }
        spotSoundMenu.setAccessibilityLabel("Needed sound for DX spots")
        spotSoundMenu.addItems(withTitles: Settings.NeededSpotSound.allCases.map(\.title))
        spotSoundMenu.selectItem(at: Settings.NeededSpotSound.allCases.firstIndex(of: Settings.neededSpotSound) ?? 0)
        spotSoundMenu.target = self
        spotSoundMenu.action = #selector(spotSoundChanged(_:))
        soundRows.append([FieldLabel("Needed sound for DX spots"), spotSoundMenu])
        let soundsGrid = NSGridView(views: soundRows)
        soundsGrid.column(at: 0).xPlacement = .trailing
        soundsGrid.rowSpacing = 8
        soundsGrid.rowAlignment = .firstBaseline
        let spotNote = NSTextField(wrappingLabelWithString:
            "DX spots play the needed sound as they come in, while the Spots window is getting them: once per "
            + "call and band, and at most every 30 seconds. New countries only is the starting choice, because a "
            + "young log needs nearly every band and mode.")
        spotNote.preferredMaxLayoutWidth = 520

        let keys = NSTextField(wrappingLabelWithString:
            "Radio lost or back always plays its own tones (two falling notes when the radio drops, two rising when "
            + "it's back); choose whether the words come too. "
            + "Speech menu: Quiet Mode (Option-Command-period) turns these down to sounds for a while, "
            + "say for a pile-up. Option-Command-N says the name and place for the call in the form; "
            + "Option-Command-L says the last contact logged. Radio Status (Command-R) says what the radio is doing.")
        keys.preferredMaxLayoutWidth = 520

        let stack = NSStackView(views: [heading, note, grid, soundsHeading, soundsNote, soundsGrid, spotNote, keys])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(20, after: grid)
        stack.setCustomSpacing(20, after: spotNote)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        // Tab goes through the pop-ups (when Keyboard navigation is on).
        let order = speechMenus + alertMenus + [spotSoundMenu]
        for (index, menu) in order.enumerated() {
            menu.nextKeyView = order[(index + 1) % order.count]
        }
        return stack
    }

    // Saves a Speech choice, and says it the new way so you hear the
    // difference.
    @objc private func speechChanged(_ sender: NSPopUpButton) {
        let kind = Speaker.Kind.allCases[sender.tag]
        guard let raw = sender.selectedItem?.representedObject as? String,
              let level = Speaker.Level(rawValue: raw) else { return }
        Settings.setSpeechLevel(level, for: kind)
        switch level {
        case .sound:
            if kind == .connection { Tone.radioLost.play() } else { Speaker.Cue.of(kind).play() }
        case .off:
            Speaker.announce("\(kind.title): nothing said.")
        default:
            Speaker.announce("\(kind.title): \(level.title(for: kind)).")
        }
    }

    // Saves a dupe or needed sound, and plays it.
    @objc private func alertSoundChanged(_ sender: NSPopUpButton) {
        guard Alert.allCases.indices.contains(sender.tag), let id = sender.selectedItem?.representedObject as? String else { return }
        Settings.setAlertSound(id, for: Alert.allCases[sender.tag])
        if id == "none" { Speaker.announce("\(Alert.allCases[sender.tag].title): none.") } else { Alert.play(id) }
    }

    @objc private func spotSoundChanged(_ sender: NSPopUpButton) {
        let all = Settings.NeededSpotSound.allCases
        guard all.indices.contains(sender.indexOfSelectedItem) else { return }
        Settings.neededSpotSound = all[sender.indexOfSelectedItem]
        if Settings.neededSpotSound != .off { Alert.needed.play() }
    }

    private func buildContent() -> NSView {
        func heading(_ title: String) -> NSTextField {
            let label = NSTextField(labelWithString: title)
            label.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
            return label
        }

        for (field, label) in [(usernameField, "QRZ username"), (passwordField, "QRZ password")] {
            field.setAccessibilityLabel(label)
            field.delegate = self
            field.widthAnchor.constraint(equalToConstant: 220).isActive = true
        }
        usernameField.placeholderString = "Usually your callsign"
        // Marked as a login (what the fields are, for macOS and password
        // managers). Tried 16 November 2026: macOS offers nothing from the
        // Passwords app here, as it only offers a site's password to an
        // app the site names (an "associated domain"), and qrz.com and
        // arrl.org don't name Solid Copy. Copy and paste from Passwords.
        usernameField.contentType = .username
        passwordField.contentType = .password

        lookupBox.target = self
        lookupBox.action = #selector(checkboxChanged(_:))
        callookBox.target = self
        callookBox.action = #selector(checkboxChanged(_:))
        testButton.target = self
        testButton.action = #selector(saveAndTest(_:))
        statusLabel.preferredMaxLayoutWidth = 500

        let qrzGrid = NSGridView(views: [[FieldLabel("QRZ username"), usernameField],
                                         [FieldLabel("QRZ password"), passwordField]])
        qrzGrid.column(at: 0).xPlacement = .trailing
        qrzGrid.rowSpacing = 8
        let stationNote = NSTextField(wrappingLabelWithString:
            "Your callsign, grid and other station details are in Profiles.")

        // POTA's park list (ParkList.swift): what's here, and fetching it now.
        parkStatus.stringValue = ParkList.shared.summary
        parkStatus.preferredMaxLayoutWidth = 500
        parkButton.target = self
        parkButton.action = #selector(updateParks(_:))
        let parkNote = NSTextField(wrappingLabelWithString:
            "Park fields search POTA's list of parks by reference, name or state, with no internet needed. "
            + "It's fetched the first time you use one, and again each month.")
        parkNote.preferredMaxLayoutWidth = 500

        let stack = NSStackView(views: [heading("Callsign lookup"), lookupBox, qrzGrid, testButton,
                                        statusLabel, callookBox, stationNote,
                                        heading("Parks"), parkNote, parkStatus, parkButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(24, after: callookBox)
        stack.setCustomSpacing(24, after: stationNote)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        // Tab order, top to bottom. Tab reaches the checkboxes and button
        // only when Keyboard navigation is on in System Settings.
        let order: [NSView] = [lookupBox, usernameField, passwordField, testButton, callookBox, parkButton]
        for (index, item) in order.enumerated() {
            item.nextKeyView = order[(index + 1) % order.count]
        }
        return stack
    }

    // MARK: - Saving

    @objc private func checkboxChanged(_ sender: NSButton) {
        Settings.lookupEnabled = lookupBox.state == .on
        Settings.useCallook = callookBox.state == .on
    }

    // Saves the starting value as soon as you leave its field.
    func controlTextDidEndEditing(_ notification: Notification) {
        let field = notification.object as? NSTextField
        if field === startingValueField { saveStartingValue() }
        if field === hostField || field === portField { saveNode() }
    }

    // Return in a field: Save and Test from the QRZ fields; Escape closes.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)) where control === usernameField || control === passwordField:
            saveAndTest(control)
            return true
        case #selector(NSResponder.insertNewline(_:)) where control === startingValueField:
            saveStartingValue()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            // Finish editing first, so what was just typed is saved.
            window?.makeFirstResponder(nil)
            window?.performClose(nil)
            return true
        default:
            return false
        }
    }

    // Saves the QRZ login (the password into the Keychain), then logs in
    // to check it, and says what QRZ answered.
    @objc private func saveAndTest(_ sender: Any?) {
        guard saveLogin() else { return }
        guard !Settings.qrzUsername.isEmpty else {
            report("QRZ login removed. Lookups will use callook.info only, if it's turned on.")
            return
        }
        report("Logging in to QRZ…", speak: false)
        testButton.isEnabled = false
        Task { @MainActor in
            defer { testButton.isEnabled = true }
            do {
                let info = try await CallsignLookup.shared.qrz.login(username: Settings.qrzUsername,
                                                                     password: Settings.qrzPassword)
                if info.hasSubscription {
                    report("Logged in to QRZ with an XML subscription (\(info.subscription)). "
                           + "Lookups will fill in every field QRZ has.")
                } else {
                    report("Logged in to QRZ with a free account. QRZ sends only a few fields, mostly the "
                           + "name, without an XML subscription. callook.info can fill in more for US calls.")
                }
            } catch {
                report("QRZ login didn't work. \(error.localizedDescription)")
            }
        }
    }

    // Saves the username, and the password in the Keychain. Changing the
    // login clears the lookup cache, so results from the old login (perhaps
    // a free account's few fields) are looked up again.
    @discardableResult
    private func saveLogin() -> Bool {
        let username = usernameField.stringValue.trimmingCharacters(in: .whitespaces)
        let password = passwordField.stringValue
        let changed = username != Settings.qrzUsername || password != Settings.qrzPassword
        guard changed else { return true }
        do {
            if username != Settings.qrzUsername {
                Keychain.deletePassword(for: Settings.qrzUsername)
            }
            Settings.qrzUsername = username
            try Keychain.setPassword(password, for: username)
        } catch {
            report(error.localizedDescription)
            return false
        }
        CallsignLookup.shared.clearCache()
        return true
    }

    // Shows a status message under the button, and says it.
    private func report(_ message: String, speak: Bool = true) {
        statusLabel.stringValue = message
        if speak { Speaker.announce(message) }
    }

    func windowWillClose(_ notification: Notification) {
        // Leaving the focused field saves what's in it.
        window?.makeFirstResponder(nil)
        saveLogin()
    }
}

// The Settings window, with Escape closing it from anywhere in it (the
// text fields handle Escape themselves, above), and Command-1 to Command-9
// going to a section.
final class SettingsWindow: NSWindow {
    var onEscape: (() -> Void)?
    var onTabNumber: ((Int) -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command, let key = event.charactersIgnoringModifiers, let number = Int(key),
           (1...9).contains(number) {
            onTabNumber?(number)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// The sidebar list: Return or Right Arrow go into the section shown.
final class SidebarTableView: NSTableView {
    var onEnter: (() -> Void)?

    // Key codes: 36 Return, 76 Enter, 124 Right Arrow.
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        // (Each with its own "where": one "where" would only apply to 124.)
        case 36 where modifiers.isEmpty, 76 where modifiers.isEmpty, 124 where modifiers.isEmpty: onEnter?()
        default: super.keyDown(with: event)
        }
    }
}

