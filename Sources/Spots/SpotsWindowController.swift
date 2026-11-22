// SpotsWindowController.swift
//
// The Spots window (Window > Spots, Command-1): who's on the air, newest
// first, one line each, so VoiceOver reads a spot in one stop:
//
//   "W1AW, 14.062 CW, US-1333 Big Pocono State Park, Pennsylvania,
//    3 minutes ago, worked today. QRV"
//
//   Up, Down     move between spots
//   Return       use the spot: tunes the radio (frequency and mode), puts
//                the call and park in the logging form and goes there, so
//                you only add the reports and press Return to log
//   Escape       back to the logging window (Spots stays open)
//   Tab          to the filters: Source, Band (all, the radio's current
//                band, or any one band), Mode (all, CW, phone, data),
//                Refresh (Live, or every 15, 30 or 45 seconds or minute:
//                RefreshPacer.swift), Hide Worked Today, DX: Needed Only
//                and DX: Heard Near Me, then back
//
// Its own window, so Command-backtick moves between it, the logging
// window and Settings. The list is fetched once a minute while the window
// is open (SpotList, in Spots.swift), and cluster spots stream in as
// they're posted; the Refresh pop-up sets how often new ones are shown.
// A new list never moves focus or speaks, and the spot you're on stays
// selected.

import AppKit

@MainActor
final class SpotsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    // Called with the spot chosen with Return.
    var onUse: ((Spot) -> Void)?
    // Escape: back to the logging window.
    var onEscape: (() -> Void)?

    private let logbook: Logbook
    private let table = SpotsTableView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let sourceMenu = NSPopUpButton()
    private let neededBox = NSButton(checkboxWithTitle: "DX: needed only", target: nil, action: nil)
    private let nearBox = NSButton(checkboxWithTitle: "DX: heard near me", target: nil, action: nil)
    // Each DX spot's country and whether it's needed, worked out per list.
    private var countries: [String: Country] = [:]
    private var needed: [String: String] = [:]
    private let bandMenu = NSPopUpButton()
    private let modeMenu = NSPopUpButton()
    private let refreshMenu = NSPopUpButton()
    // Shows new spots at the Refresh pop-up's pace (made in init).
    private var pacer: RefreshPacer!
    private let hideWorkedBox = NSButton(checkboxWithTitle: "Hide spots worked today", target: nil, action: nil)
    // The spots shown, after the filters, and which of them you've worked.
    private var shown: [Spot] = []
    private var worked: Set<String> = []
    private var shownBand: String?

    private static let modes = ["All modes", "CW", "Phone", "Data"]
    // Saved by position, so new ones go at the end.
    private static let sources = [("All sources", ""), ("POTA", "POTA"), ("DX cluster", "DX"), ("SOTA", "SOTA")]
    // The Band filter: All bands, Current band (the radio's), then each
    // band, by its ADIF name, shown in words ("20 meters").
    private static let bands = ["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m",
                                "6m", "2m", "70cm"]

    // The band chosen in the filter: nil for all, "current", or "20m".
    private var chosenBand: String? {
        switch bandMenu.indexOfSelectedItem {
        case ...0: return nil
        case 1: return "current"
        default: return Self.bands[bandMenu.indexOfSelectedItem - 2]
        }
    }

    init(logbook: Logbook) {
        self.logbook = logbook
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Spots"
        window.contentMinSize = NSSize(width: 520, height: 300)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("SpotsWindow")
        super.init(window: window)
        window.delegate = self
        window.contentView = build()
        window.initialFirstResponder = table
        if !window.setFrameUsingName("SpotsWindow") { window.center() }

        let saved = UserDefaults.standard.integer(forKey: "spots.refresh")
        let choice = RefreshPacer.choices.indices.contains(saved) ? saved : 0
        pacer = RefreshPacer(interval: RefreshPacer.choices[choice].seconds) { [weak self] in self?.reload() }
        refreshMenu.selectItem(at: choice)
        // New spots: at the Refresh pop-up's pace.
        NotificationCenter.default.addObserver(forName: SpotList.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pacer.changed() }
        }
        // "Current band" follows the radio: reload when its band changes.
        NotificationCenter.default.addObserver(forName: RadioMonitor.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, RadioMonitor.shared.reading?.band != self.shownBand else { return }
                self.reload()
            }
        }
        // A contact logged: it may now be worked today (shown at the same pace).
        logbook.observe { [weak self] in self?.pacer.changed() }
        // For the needed sound as DX spots come in (Spots.swift).
        SpotList.shared.log = { [weak self] in self?.logbook.contacts ?? [] }
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    func show() {
        SpotList.shared.start()
        reload()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(table)
    }

    func windowWillClose(_ notification: Notification) {
        // Nobody's looking: stop fetching.
        SpotList.shared.stop()
        pacer.stop()
    }

    // MARK: - Building

    private func build() -> NSView {
        let heading = NSTextField(labelWithString: "Spots")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        status.preferredMaxLayoutWidth = 700

        sourceMenu.addItems(withTitles: Self.sources.map(\.0))
        sourceMenu.setAccessibilityLabel("Source")
        bandMenu.addItems(withTitles: ["All bands", "Current band"] + Self.bands.map(Bands.spoken))
        bandMenu.setAccessibilityLabel("Band")
        modeMenu.addItems(withTitles: Self.modes)
        modeMenu.setAccessibilityLabel("Mode")
        refreshMenu.addItems(withTitles: RefreshPacer.choices.map(\.title))
        refreshMenu.setAccessibilityLabel("Refresh")
        refreshMenu.target = self
        refreshMenu.action = #selector(refreshChanged(_:))
        let defaults = UserDefaults.standard
        // Remembered by name ("all", "current", "20m").
        switch defaults.string(forKey: "spots.bandName") ?? "all" {
        case "current": bandMenu.selectItem(at: 1)
        case let band: bandMenu.selectItem(at: Self.bands.firstIndex(of: band).map { $0 + 2 } ?? 0)
        }
        modeMenu.selectItem(at: defaults.integer(forKey: "spots.mode"))
        sourceMenu.selectItem(at: defaults.integer(forKey: "spots.source"))
        hideWorkedBox.state = defaults.bool(forKey: "spots.hideWorked") ? .on : .off
        neededBox.state = defaults.bool(forKey: "spots.neededOnly") ? .on : .off
        nearBox.state = defaults.bool(forKey: "spots.nearMe") ? .on : .off
        for control in [sourceMenu, bandMenu, modeMenu, hideWorkedBox, neededBox, nearBox] as [NSControl] {
            control.target = self
            control.action = #selector(filterChanged(_:))
        }
        let filters = NSStackView(views: [FieldLabel("Source"), sourceMenu, FieldLabel("Band"), bandMenu,
                                          FieldLabel("Mode"), modeMenu, FieldLabel("Refresh"), refreshMenu])
        filters.spacing = 8
        let boxes = NSStackView(views: [hideWorkedBox, neededBox, nearBox])
        boxes.spacing = 16

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("spot"))
        column.title = "Spot"
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.setAccessibilityLabel("Spots")
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(useSelected(_:))
        table.onEnter = { [weak self] in self?.useSelected(nil) }
        table.onEscape = { [weak self] in self?.onEscape?() }
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        // Tab: the table, then the filters, then back to the table.
        let order: [NSView] = [table, sourceMenu, bandMenu, modeMenu, refreshMenu, hideWorkedBox, neededBox, nearBox]
        for (index, view) in order.enumerated() { view.nextKeyView = order[(index + 1) % order.count] }

        let stack = NSStackView(views: [heading, status, filters, boxes, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        return stack
    }

    // Refresh: how often new spots are shown. Said, and remembered.
    @objc private func refreshChanged(_ sender: Any?) {
        let index = max(0, refreshMenu.indexOfSelectedItem)
        UserDefaults.standard.set(index, forKey: "spots.refresh")
        pacer.interval = RefreshPacer.choices[index].seconds
        Speaker.announce(index == 0 ? "New spots are shown as they arrive."
                                    : "New spots are shown \(RefreshPacer.choices[index].title.lowercased()).")
    }

    @objc private func filterChanged(_ sender: Any?) {
        let defaults = UserDefaults.standard
        defaults.set(chosenBand ?? "all", forKey: "spots.bandName")
        defaults.set(modeMenu.indexOfSelectedItem, forKey: "spots.mode")
        defaults.set(hideWorkedBox.state == .on, forKey: "spots.hideWorked")
        defaults.set(sourceMenu.indexOfSelectedItem, forKey: "spots.source")
        defaults.set(neededBox.state == .on, forKey: "spots.neededOnly")
        defaults.set(nearBox.state == .on, forKey: "spots.nearMe")
        reload()
        // Said, so the change is heard without reading the list again.
        Speaker.announce(status.stringValue)
    }

    // MARK: - The list

    private func reload() {
        let list = SpotList.shared
        let selectedKey = shown.indices.contains(table.selectedRow) ? shown[table.selectedRow].key : nil
        let radioBand = RadioMonitor.shared.reading?.band
        shownBand = radioBand
        // The band to show: the one chosen, the radio's, or any.
        let current = chosenBand == "current"
        let band = current ? radioBand : chosenBand
        let mode = modeMenu.indexOfSelectedItem > 0 ? Self.modes[modeMenu.indexOfSelectedItem] : nil

        // Worked today: today's contacts only, so a big log costs little.
        let today = POTASpots.utcDay.string(from: Date())
        let start = POTASpots.utcDay.date(from: today) ?? Date()
        let todays = logbook.contacts.filter { $0.timeOn >= start }
        let all = list.spots
        worked = Set(all.filter { spot in todays.contains { spot.isWorked(by: $0, today: today) } }.map(\.key))
        // Cluster spots (DX and SOTA): their country, and whether it's needed.
        countries = [:]
        needed = [:]
        for spot in all where spot.source != "POTA" {
            guard let country = Countries.shared.country(of: spot.call) else { continue }
            countries[spot.key] = country
            needed[spot.key] = list.worked.needed(spot, country: country, log: logbook.contacts)
        }
        let source = Self.sources[max(0, sourceMenu.indexOfSelectedItem)].1
        // Heard near me: spotted by someone on your continent (from your
        // call in the profile in use), so likely to be heard here too.
        let myContinent = Countries.shared.country(of: Settings.currentProfile.station["station_callsign"] ?? "")?.continent
        let nearOnly = nearBox.state == .on && myContinent != nil
        func isNear(_ spot: Spot) -> Bool {
            spot.spotters.contains { Countries.shared.country(of: DXCluster.spotterCall($0))?.continent == myContinent }
        }

        shown = all.filter { spot in
            if !source.isEmpty, spot.source != source { return false }
            if neededBox.state == .on, spot.source == "DX", needed[spot.key] == nil { return false }
            if nearOnly, spot.source == "DX", !isNear(spot) { return false }
            if let band, spot.band != band { return false }
            if let mode, spot.modeGroup != mode { return false }
            if hideWorkedBox.state == .on, worked.contains(spot.key) { return false }
            return true
        }
        table.reloadData()
        // The same spot stays selected (if it's still there), so a new
        // list doesn't move you.
        if let selectedKey, let row = shown.firstIndex(where: { $0.key == selectedKey }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if !shown.isEmpty, table.selectedRow < 0 {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        status.stringValue = statusText(band: band, currentWithoutRadio: current && radioBand == nil)
    }

    // "12 of 59 spots, on 20 meters, CW. Updated 14:32 UTC."
    private func statusText(band: String?, currentWithoutRadio: Bool) -> String {
        let list = SpotList.shared
        let total = list.spots.count
        if let problem = list.problem, total == 0 { return problem + " " + list.clusterState }
        // SOTA spots come from the cluster: say so if it's off.
        if sourceMenu.titleOfSelectedItem == "SOTA", !Settings.clusterEnabled {
            return "SOTA spots come from the DX cluster, which is off (Settings > Spots)."
        }
        guard let fetched = list.fetched else { return "Getting spots… " + list.clusterState }
        let count = shown.count == total
            ? (shown.count == 1 ? "1 spot" : "\(shown.count) spots")
            : "\(shown.count) of \(total) spots"
        var filters: [String] = []
        if let band { filters.append("on " + Bands.spoken(band)) }
        if modeMenu.indexOfSelectedItem > 0 { filters.append(Self.modes[modeMenu.indexOfSelectedItem]) }
        var text = count + (filters.isEmpty ? "" : ", " + filters.joined(separator: ", ")) + "."
        if currentWithoutRadio { text += " No radio, so every band is shown." }
        if nearBox.state == .on, Countries.shared.country(of: Settings.currentProfile.station["station_callsign"] ?? "") == nil {
            text += " Heard near me needs your callsign, in Settings > Profiles."
        }
        text += " POTA updated " + Self.time.string(from: fetched) + " UTC."
        if let problem = list.problem { text += " " + problem }
        return text + " " + list.clusterState
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    @objc private func useSelected(_ sender: Any?) {
        guard shown.indices.contains(table.selectedRow) else { return NSSound.beep() }
        onUse?(shown[table.selectedRow])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard shown.indices.contains(row) else { return nil }
        let id = NSUserInterfaceItemIdentifier("spotCell")
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
        let spot = shown[row]
        cell.textField?.stringValue = spot.line(now: Date(), worked: worked.contains(spot.key),
                                                country: countries[spot.key]?.name, needed: needed[spot.key])
        return cell
    }
}

// The spots table: Return (or Enter) uses a spot, Escape goes back.
final class SpotsTableView: NSTableView {
    var onEnter: (() -> Void)?
    var onEscape: (() -> Void)?

    // Key codes: 36 Return, 76 Enter, 53 Escape.
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        case 36 where modifiers.isEmpty, 76 where modifiers.isEmpty: onEnter?()
        case 53: onEscape?()
        default: super.keyDown(with: event)
        }
    }
}
