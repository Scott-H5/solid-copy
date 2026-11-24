// AwardsWindowController.swift
//
// Window > Awards (Command-5): how far the log is towards DXCC, WAS, WAZ,
// WPX and SKCC's Centurion, Tribune and Senator (Awards.swift), one line
// each, so VoiceOver reads an award in one stop:
//
//   "WAS: 38 states worked, 31 confirmed, 19 more confirmed for the award."
//   "SKCC Centurion: 63 members count, 37 more for Centurion."
//
// Below that, the chosen award's list, one line per country, state, zone
// or prefix:
//
//   "Utah: not worked"
//   "Texas: worked, not confirmed, 2 contacts"
//   "Ohio: confirmed by LoTW, 5 contacts"
//   "K3ABC, SKCC 12345T: counts, 2 contacts"
//   "W1XYZ, SKCC 2345: doesn't count, you weren't a Centurion yet, 1 contact"
//
// For SKCC, a member counts or doesn't (no QSL is needed): Confirmed in
// Show is the members that count, and Still needed the ones that don't,
// with why. SKCC counts CW only, whatever Mode says.
//
// POTA Hunter lists the parks worked ("US-1333, Big Pocono State Park,
// Pennsylvania: worked, 3 contacts"); there's no confirmation to show, so
// Show doesn't apply. pota.app keeps the official count.
//
// Club awards follow, one per club you log numbers for: SKCC, FISTS,
// LICW, CWops and your own named club fields (ClubAwards.swift).
//
//   "NAQCC: 40 of 312 members worked; 10 more for your goal of 50."
//   "W1XYZ, NAQCC 1234: worked, 2 contacts"
//   "K3ABC, NAQCC 2345: not worked"
//
// With a club chosen, Show is Worked, Still needed (members on the club's
// list not worked yet, for a club field with a member list file) or All,
// and three more choices appear: Dates (all dates, this month, last month,
// this year, last year, or between two dates you pick), the From and To
// dates for Between dates, and Goal, a number of members you're aiming
// for. A club's challenge, such as members worked in a month, is the
// right Dates and a goal.
//   Up, Down   move between awards, or through the list
//   Return     from an award, to its list
//   Escape     back to the logging window (this window stays open)
//   Tab        the awards, Band, Mode, Show (still needed, worked but not
//              confirmed, not worked, confirmed, or all), for a club
//              Dates, From, To and Goal, the list, then back
//
// It counts again whenever the log changes (a contact logged, a LoTW sync),
// and the line you're on stays selected. The choices are remembered.

import AppKit

@MainActor
final class AwardsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate,
    NSTextFieldDelegate {
    var onEscape: (() -> Void)?

    // What the list shows of the chosen award.
    enum Show: String, CaseIterable {
        case needed, workedOnly, notWorked, confirmed, all

        var title: String {
            switch self {
            case .needed: "Still needed"
            case .workedOnly: "Worked, not confirmed"
            case .notWorked: "Not worked"
            case .confirmed: "Confirmed"
            case .all: "All"
            }
        }

        func includes(_ item: AwardItem) -> Bool {
            switch self {
            case .needed: !item.isConfirmed
            case .workedOnly: item.isWorked && !item.isConfirmed
            case .notWorked: !item.isWorked
            case .confirmed: item.isConfirmed
            case .all: true
            }
        }
    }

    // What the list shows of a club: members worked, members on its list
    // not worked yet, or both.
    enum ClubShow: String, CaseIterable {
        case worked, needed, all

        var title: String {
            switch self {
            case .worked: "Worked"
            case .needed: "Still needed"
            case .all: "All"
            }
        }

        func includes(_ item: AwardItem) -> Bool {
            switch self {
            case .worked: item.isConfirmed
            case .needed: !item.isConfirmed
            case .all: true
            }
        }
    }

    // One line of the awards list: a fixed award or a club.
    private enum Row {
        case award(AwardProgress)
        case club(ClubProgress)

        var line: String {
            switch self {
            case .award(let progress): progress.line
            case .club(let progress): progress.line
            }
        }
        var items: [AwardItem] {
            switch self {
            case .award(let progress): progress.items
            case .club(let progress): progress.items
            }
        }
        // Remembered between launches: "dxcc", or "club:fists".
        var id: String {
            switch self {
            case .award(let progress): progress.award.rawValue
            case .club(let progress): "club:" + progress.field
            }
        }
        var club: ClubProgress? {
            if case .club(let progress) = self { return progress }
            return nil
        }
        var award: Award? {
            if case .award(let progress) = self { return progress.award }
            return nil
        }
    }

    private static let bands = ["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m", "2m", "70cm"]

    private let logbook: Logbook
    private let awardsTable = SpotsTableView()
    private let itemsTable = SpotsTableView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let bandMenu = NSPopUpButton()
    private let modeMenu = NSPopUpButton()
    private let showMenu = NSPopUpButton()
    // For a club only.
    private let periodMenu = NSPopUpButton()
    private let fromPicker = NSDatePicker()
    private let toPicker = NSDatePicker()
    private let goalField = NSTextField()
    private let clubControls = NSStackView()
    // Whether Show holds a club's choices or an award's.
    private var showIsForClub = false

    private var rows: [Row] = []
    private var shownItems: [AwardItem] = []

    init(logbook: Logbook) {
        self.logbook = logbook
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Awards"
        window.contentMinSize = NSSize(width: 480, height: 360)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("AwardsWindow")
        super.init(window: window)
        window.delegate = self
        window.contentView = build()
        window.initialFirstResponder = awardsTable
        if !window.setFrameUsingName("AwardsWindow") { window.center() }
        // A contact logged, edited or confirmed: count again.
        logbook.observe { [weak self] in
            guard self?.window?.isVisible == true else { return }
            self?.reload()
        }
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    func show() {
        // SKCC's member list: read from disk now (fetched later if old),
        // so the first count has it.
        SKCCRoster.shared.start()
        reload()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(awardsTable)
        // DXCC needs cty.dat's list of countries; fetched if it isn't here.
        Countries.shared.fetchIfNeeded { [weak self] in self?.reload() }
    }

    private func build() -> NSView {
        let heading = NSTextField(labelWithString: "Awards")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        // Instructions are a note you can read again (contract rule 40),
        // linked to the awards list (VO-Command-J).
        let note = NSTextField(wrappingLabelWithString:
            "Counts contacts confirmed by LoTW or a paper card, as ARRL and CQ do. SKCC awards need no QSL: "
            + "a member counts if both of you had joined, or reached the level, by the day of the contact, "
            + "from SKCC's member list. Club awards, after those, count different members worked, with no QSL "
            + "needed, over the dates you choose and towards a goal you set. Choose an award, then Tab to choose "
            + "a band, a mode and what its list shows. Return goes to the list.")
        note.preferredMaxLayoutWidth = 660
        note.isSelectable = true
        status.preferredMaxLayoutWidth = 660
        status.isSelectable = true

        let defaults = UserDefaults.standard
        bandMenu.addItems(withTitles: ["All bands"] + Self.bands.map(Bands.spoken))
        bandMenu.setAccessibilityLabel("Band")
        bandMenu.selectItem(at: (Self.bands.firstIndex(of: defaults.string(forKey: "awards.band") ?? "") ?? -1) + 1)
        modeMenu.addItems(withTitles: AwardMode.allCases.map(\.title))
        modeMenu.setAccessibilityLabel("Mode")
        modeMenu.selectItem(at: AwardMode.allCases.firstIndex { $0.rawValue == defaults.string(forKey: "awards.mode") } ?? 0)
        showMenu.setAccessibilityLabel("Show")
        fillShowMenu(forClub: false)
        periodMenu.addItems(withTitles: ClubPeriod.allCases.map(\.title))
        periodMenu.setAccessibilityLabel("Dates")
        periodMenu.selectItem(at: ClubPeriod.allCases.firstIndex { $0.rawValue == defaults.string(forKey: "awards.clubPeriod") } ?? 0)
        for menu in [bandMenu, modeMenu, showMenu, periodMenu] {
            menu.target = self
            menu.action = #selector(filterChanged(_:))
        }
        let filters = NSStackView(views: [bandMenu, modeMenu, showMenu])
        filters.spacing = 16

        // A club's dates (UTC, as the log is) and goal. Between dates
        // starts as this month so far.
        let utc = ClubPeriod.utc
        let monthStart = utc.dateInterval(of: .month, for: Date())?.start ?? Date()
        for (picker, label, key, start) in [(fromPicker, "From", "awards.clubFrom", monthStart),
                                            (toPicker, "To", "awards.clubTo", Date())] {
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = .yearMonthDay
            picker.timeZone = utc.timeZone
            picker.calendar = utc
            picker.dateValue = defaults.object(forKey: key) as? Date ?? start
            picker.setAccessibilityLabel(label)
            picker.target = self
            picker.action = #selector(datesChanged(_:))
        }
        goalField.placeholderString = "None"
        goalField.setAccessibilityLabel("Goal, members")
        goalField.delegate = self
        goalField.widthAnchor.constraint(equalToConstant: 70).isActive = true
        let datesRow = NSStackView(views: [periodMenu, FieldLabel("From"), fromPicker, FieldLabel("To"), toPicker])
        datesRow.spacing = 8
        let goalRow = NSStackView(views: [FieldLabel("Goal"), goalField])
        goalRow.spacing = 8
        clubControls.setViews([datesRow, goalRow], in: .leading)
        clubControls.orientation = .vertical
        clubControls.alignment = .leading
        clubControls.spacing = 8
        clubControls.isHidden = true

        let awardsScroll = Self.scroll(for: awardsTable, label: "Awards", id: "award")
        awardsTable.dataSource = self
        awardsTable.delegate = self
        awardsTable.onEnter = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.itemsTable)
            if self.itemsTable.selectedRow < 0, !self.shownItems.isEmpty {
                self.itemsTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            }
        }
        awardsTable.onEscape = { [weak self] in self?.onEscape?() }
        awardsTable.setAccessibilityLinkedUIElements([note])
        awardsScroll.heightAnchor.constraint(equalToConstant: 170).isActive = true

        let itemsScroll = Self.scroll(for: itemsTable, label: "List", id: "item")
        itemsTable.dataSource = self
        itemsTable.delegate = self
        itemsTable.onEscape = { [weak self] in self?.onEscape?() }

        // Hidden ones (a club's, when an award is chosen) are passed over.
        let order: [NSView] = [awardsTable, bandMenu, modeMenu, showMenu, periodMenu, fromPicker, toPicker,
                               goalField, itemsTable]
        for (index, view) in order.enumerated() { view.nextKeyView = order[(index + 1) % order.count] }

        let stack = NSStackView(views: [heading, note, awardsScroll, filters, clubControls, status, itemsScroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        for scroll in [awardsScroll, itemsScroll] {
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        }
        itemsScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        // The rows, and the award last chosen, come with the first count
        // (reload).
        return stack
    }

    private static func scroll(for table: NSTableView, label: String, id: String) -> NSScrollView {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.setAccessibilityLabel(label)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        return scroll
    }

    private var chosenRow: Row? { rows.indices.contains(awardsTable.selectedRow) ? rows[awardsTable.selectedRow] : rows.first }
    private var chosenBand: String? {
        bandMenu.indexOfSelectedItem > 0 ? Self.bands[bandMenu.indexOfSelectedItem - 1] : nil
    }
    private var chosenMode: AwardMode { AwardMode.allCases[max(0, modeMenu.indexOfSelectedItem)] }
    private var chosenShow: Show {
        Show.allCases.indices.contains(showMenu.indexOfSelectedItem) ? Show.allCases[showMenu.indexOfSelectedItem] : .needed
    }
    private var chosenClubShow: ClubShow {
        ClubShow.allCases.indices.contains(showMenu.indexOfSelectedItem)
            ? ClubShow.allCases[showMenu.indexOfSelectedItem] : .worked
    }
    private var chosenPeriod: ClubPeriod { ClubPeriod.allCases[max(0, periodMenu.indexOfSelectedItem)] }
    private var chosenInterval: DateInterval? {
        chosenPeriod.interval(now: Date(), from: fromPicker.dateValue, to: toPicker.dateValue)
    }

    // Show's choices: an award's, or a club's, each remembered apart.
    private func fillShowMenu(forClub club: Bool) {
        showIsForClub = club
        showMenu.removeAllItems()
        let saved = UserDefaults.standard.string(forKey: club ? "awards.clubShow" : "awards.show")
        if club {
            showMenu.addItems(withTitles: ClubShow.allCases.map(\.title))
            showMenu.selectItem(at: ClubShow.allCases.firstIndex { $0.rawValue == saved } ?? 0)
        } else {
            showMenu.addItems(withTitles: Show.allCases.map(\.title))
            showMenu.selectItem(at: Show.allCases.firstIndex { $0.rawValue == saved } ?? 0)
        }
    }

    @objc private func filterChanged(_ sender: Any?) {
        let defaults = UserDefaults.standard
        defaults.set(chosenBand ?? "", forKey: "awards.band")
        defaults.set(chosenMode.rawValue, forKey: "awards.mode")
        if showIsForClub {
            defaults.set(chosenClubShow.rawValue, forKey: "awards.clubShow")
        } else {
            defaults.set(chosenShow.rawValue, forKey: "awards.show")
        }
        defaults.set(chosenPeriod.rawValue, forKey: "awards.clubPeriod")
        reload()
        sayChosen()
    }

    @objc private func datesChanged(_ sender: Any?) {
        UserDefaults.standard.set(fromPicker.dateValue, forKey: "awards.clubFrom")
        UserDefaults.standard.set(toPicker.dateValue, forKey: "awards.clubTo")
        reload()
    }

    // The new count of the chosen award, and what the list now shows.
    private func sayChosen() {
        Speaker.announce((chosenRow?.line ?? "") + " " + status.stringValue)
    }

    // Goal: saved on Return or on leaving the field. Empty is no goal; a
    // number that isn't one is refused and put back.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard notification.object as? NSTextField === goalField, let club = chosenRow?.club else { return }
        let typed = goalField.stringValue.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty {
            guard ClubAwards.goal(for: club.field) != nil else { return }
            ClubAwards.setGoal(nil, for: club.field)
        } else if let goal = Int(typed), goal > 0, goal <= 1_000_000 {
            guard ClubAwards.goal(for: club.field) != goal else { return }
            ClubAwards.setGoal(goal, for: club.field)
        } else {
            NSSound.beep()
            goalField.stringValue = ClubAwards.goal(for: club.field).map(String.init) ?? ""
            Speaker.announce("The goal is a number of members, such as 50, or empty for none.")
            return
        }
        reload()
        Speaker.announce(chosenRow?.line ?? "")
    }

    // The clubs with an award line: your named club fields, and SKCC,
    // FISTS, LICW and CWops once the log has a number for them (or, for
    // SKCC, its member list is on).
    private func clubs() -> [ClubAwards.Club] {
        let log = logbook.contacts
        let roster = SKCCRoster.shared
        return LogField.clubNumberFields.compactMap { field in
            let slot = LogField.named(field)?.clubSlot
            if let slot {
                guard !ClubNames.name(slot).isEmpty else { return nil }
            } else if !(field == "skcc" && roster.isReady), !log.contains(where: { !$0[field].isEmpty }) {
                return nil
            }
            let listed = slot.flatMap(ClubLists.members)
            let number: (String) -> String? = field == "skcc" ? { roster.number(for: $0) }
                : { call in slot.flatMap { ClubLists.number(slot: $0, for: call) } }
            return ClubAwards.Club(field: field, title: ClubNumbers.shortName(field), goal: ClubAwards.goal(for: field),
                                   listed: listed, number: number)
        }
    }

    // Counts every award again, keeping the lines you're on. (Not private:
    // tools/check-screen-size.sh counts with a club chosen.)
    func reload() {
        let table = Countries.shared
        // One country look-up per call, not one per award.
        var cache: [String: Country?] = [:]
        let country: (String) -> Country? = { call in
            if let found = cache[call] { return found }
            let found = table.country(of: call)
            cache[call] = found
            return found
        }
        let all = table.all
        // SKCC: your dates and each member's, from SKCC's list, if it's on.
        let roster = SKCCRoster.shared
        let myCall = Settings.currentProfile.station["station_callsign"] ?? ""
        let skcc = roster.isReady ? Awards.SKCC(mine: roster.number(for: myCall).flatMap(roster.dates(forNumber:)),
                                                number: roster.number(for:), dates: roster.dates(forNumber:)) : nil
        let parks = ParkList.shared
        // The line you're on, kept by what it is (club lines come and go).
        let chosenID = chosenRow?.id ?? UserDefaults.standard.string(forKey: "awards.award")
        let interval = chosenInterval
        rows = Award.allCases.map {
            .award(Awards.progress($0, log: logbook.contacts, band: chosenBand, mode: chosenMode,
                                   country: country, allCountries: all, skcc: skcc,
                                   parkName: { parks.park($0)?.spoken }))
        } + clubs().map {
            .club(ClubAwards.progress($0, log: logbook.contacts, band: chosenBand, mode: chosenMode, period: interval))
        }
        awardsTable.reloadData()
        let row = rows.firstIndex { $0.id == chosenID } ?? 0
        awardsTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        reloadItems()
    }

    private func reloadItems() {
        guard let chosen = chosenRow else { return }
        let selectedKey = shownItems.indices.contains(itemsTable.selectedRow) ? shownItems[itemsTable.selectedRow].key : nil
        // A club's choices, shown only for a club.
        let club = chosen.club
        if (club != nil) != showIsForClub { fillShowMenu(forClub: club != nil) }
        clubControls.isHidden = club == nil
        let between = chosenPeriod == .between
        for view in clubControls.views.first.map({ ($0 as? NSStackView)?.views.dropFirst() ?? [] }) ?? [] {
            view.isHidden = !between
        }
        if let club, goalField.currentEditor() == nil {
            goalField.stringValue = club.goal.map(String.init) ?? ""
        }
        let items = chosen.items
        if club != nil {
            shownItems = items.filter(chosenClubShow.includes)
        } else {
            shownItems = chosen.award == .pota ? items : items.filter(chosenShow.includes)
        }
        itemsTable.reloadData()
        if let selectedKey, let row = shownItems.firstIndex(where: { $0.key == selectedKey }) {
            itemsTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        UserDefaults.standard.set(chosen.id, forKey: "awards.award")
        let band = chosenBand.map { "on " + Bands.spoken($0) } ?? "on all bands"
        let count = shownItems.count == 1 ? "1 line" : "\(shownItems.count) lines"
        if let club {
            var text = "\(club.title) \(band), \(chosenMode.title.lowercased()), "
                + "\(chosenPeriod.spoken(chosenInterval)). \(chosenClubShow.title): \(count)."
            if club.listCount == nil, chosenClubShow != .worked {
                text += " Still needed lists members not worked yet from a member list file, which your own "
                    + "club fields can have (Settings > Clubs)."
            }
            status.stringValue = text
            return
        }
        guard let award = chosen.award else { return }
        let mode = award.isSKCC ? "CW" : chosenMode.title.lowercased()
        var text = "\(award.title) \(band), \(mode). \(award == .pota ? "Parks worked" : chosenShow.title): \(count)."
        if award == .pota {
            text += " pota.app keeps the official count, from the activators' logs."
        }
        if award == .dxcc, Countries.shared.all.isEmpty {
            text += " The country list (cty.dat) isn't here yet, so DXCC can't be counted. It's fetched from "
                + "country-files.com when Solid Copy is online."
        }
        status.stringValue = text
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // A different award: its list.
        if notification.object as? NSTableView === awardsTable { reloadItems() }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === awardsTable ? rows.count : shownItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let text: String
        if tableView === awardsTable {
            guard rows.indices.contains(row) else { return nil }
            text = rows[row].line
        } else {
            guard shownItems.indices.contains(row) else { return nil }
            text = shownItems[row].line
        }
        let id = NSUserInterfaceItemIdentifier("awardCell")
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
        cell.textField?.stringValue = text
        return cell
    }
}
