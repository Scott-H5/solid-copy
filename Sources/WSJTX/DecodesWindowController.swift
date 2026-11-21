// DecodesWindowController.swift
//
// Window > WSJT-X Decodes (Command-4): what WSJT-X is decoding, newest
// first, one line each, so VoiceOver reads a decode in one stop:
//
//   "W1AW calling CQ, United States, grid FN31, -12 dB, 14:30:15, new country"
//   "To you, from K1ABC: -08, -15 dB, 14:30:30"
//   "K1ABC to W1AW: RR73, -3 dB, 14:30:45"
//
//   Up, Down   move between decodes
//   Return     answer that station: WSJT-X calls it, as if you'd
//              double-clicked the decode in WSJT-X (its Accept UDP
//              requests must be on). Said: "WSJT-X is calling W1AW."
//   Command-period  Stop Transmitting: WSJT-X stops at once (Halt Tx)
//   Escape     back to the logging window (this window stays open)
//   Tab        to the filters: CQs Only, Needed Only, Hide Worked, then
//              Stop Transmitting, then back
//
// WSJT-X runs as usual and does the decoding; Solid Copy listens to it
// (WSJTXListener.swift) while this window is open. A new decode never
// moves focus; the one you're on stays selected. Only a station calling
// you is said, since that's the one you mustn't miss.
//
// v1.3 item 6, stages 1 and 2. Next: contacts WSJT-X logs arrive in the
// log.

import AppKit

@MainActor
final class DecodesWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var onEscape: (() -> Void)?

    private let logbook: Logbook
    private let table = SpotsTableView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let cqBox = NSButton(checkboxWithTitle: "CQs only", target: nil, action: nil)
    private let neededBox = NSButton(checkboxWithTitle: "Needed only", target: nil, action: nil)
    private let hideWorkedBox = NSButton(checkboxWithTitle: "Hide stations worked before", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop Transmitting", target: nil, action: nil)
    private let worked = WorkedCountries()

    // The decodes shown, after the filters, with their words worked out.
    private var shown: [Row] = []
    // Decodes already said (a call to you), so each is said once.
    private var said: Set<String> = []

    private struct Row {
        var decode: WSJTXDecode
        var line: String
        var key: String { "\(decode.milliseconds) \(decode.df) \(decode.text)" }
    }

    init(logbook: Logbook) {
        self.logbook = logbook
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "WSJT-X Decodes"
        window.contentMinSize = NSSize(width: 480, height: 300)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("DecodesWindow")
        super.init(window: window)
        window.delegate = self
        window.contentView = build()
        window.initialFirstResponder = table
        if !window.setFrameUsingName("DecodesWindow") { window.center() }
        NotificationCenter.default.addObserver(forName: WSJTXListener.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        // A contact logged: a station may now be worked.
        logbook.observe { [weak self] in self?.reload() }
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    func show() {
        WSJTXListener.shared.start()
        reload()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(table)
    }

    func windowWillClose(_ notification: Notification) {
        // Nobody's looking: stop listening, so the port is free for others.
        WSJTXListener.shared.stop()
    }

    private func build() -> NSView {
        let heading = NSTextField(labelWithString: "WSJT-X Decodes")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        status.preferredMaxLayoutWidth = 660
        status.isSelectable = true

        let defaults = UserDefaults.standard
        cqBox.state = defaults.bool(forKey: "decodes.cqOnly") ? .on : .off
        neededBox.state = defaults.bool(forKey: "decodes.neededOnly") ? .on : .off
        hideWorkedBox.state = defaults.bool(forKey: "decodes.hideWorked") ? .on : .off
        for box in [cqBox, neededBox, hideWorkedBox] {
            box.target = self
            box.action = #selector(filterChanged(_:))
        }
        // Command-period, the Mac's "stop", while this window is in front.
        stopButton.target = self
        stopButton.action = #selector(stopTransmitting(_:))
        stopButton.keyEquivalent = "."
        stopButton.keyEquivalentModifierMask = .command
        stopButton.toolTip = "Stops WSJT-X transmitting at once (Command-period)"
        let boxes = NSStackView(views: [cqBox, neededBox, hideWorkedBox, stopButton])
        boxes.spacing = 16

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("decode"))
        column.title = "Decode"
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.setAccessibilityLabel("Decodes")
        table.dataSource = self
        table.delegate = self
        table.onEnter = { [weak self] in self?.answerSelected() }
        table.doubleAction = #selector(answerSelectedAction(_:))
        table.target = self
        table.onEscape = { [weak self] in self?.onEscape?() }
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let order: [NSView] = [table, cqBox, neededBox, hideWorkedBox, stopButton]
        for (index, view) in order.enumerated() { view.nextKeyView = order[(index + 1) % order.count] }

        let stack = NSStackView(views: [heading, status, boxes, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        return stack
    }

    @objc private func answerSelectedAction(_ sender: Any?) { answerSelected() }

    // Return: WSJT-X calls the station that sent the chosen decode.
    private func answerSelected() {
        guard shown.indices.contains(table.selectedRow) else { return NSSound.beep() }
        let decode = shown[table.selectedRow].decode
        guard let words = FT8Text(decode.text), FT8Text.looksLikeCall(words.from), !words.from.hasPrefix("<") else {
            NSSound.beep()
            return Speaker.announce("That decode doesn't name a station to answer.")
        }
        let call = words.plainFrom
        Speaker.announce("Answering \(call).")
        WSJTXListener.shared.answer(decode, call: call) { result in
            switch result {
            case .sent:
                Speaker.announce("WSJT-X is calling \(call).")
            case .ignored:
                NSSound.beep()
                Speaker.announce("WSJT-X didn't take it. In WSJT-X's Settings > Reporting, turn on Accept UDP "
                                 + "requests, and check its Enable Tx.")
            case .unheard:
                NSSound.beep()
                Speaker.announce("WSJT-X hasn't been heard yet, so there's nothing to answer through.")
            }
        }
    }

    // Command-period: WSJT-X stops transmitting at once.
    @objc private func stopTransmitting(_ sender: Any?) {
        guard WSJTXListener.shared.haltTransmitting() else {
            NSSound.beep()
            return Speaker.announce("WSJT-X hasn't been heard yet.")
        }
        Speaker.announce("Told WSJT-X to stop transmitting.")
    }

    @objc private func filterChanged(_ sender: Any?) {
        let defaults = UserDefaults.standard
        defaults.set(cqBox.state == .on, forKey: "decodes.cqOnly")
        defaults.set(neededBox.state == .on, forKey: "decodes.neededOnly")
        defaults.set(hideWorkedBox.state == .on, forKey: "decodes.hideWorked")
        reload()
        Speaker.announce(status.stringValue)
    }

    private func reload() {
        let listener = WSJTXListener.shared
        let selectedKey = shown.indices.contains(table.selectedRow) ? shown[table.selectedRow].key : nil
        let myCall = (listener.status?.deCall).flatMap { $0.isEmpty ? nil : $0 }
            ?? Settings.currentProfile.station["station_callsign"] ?? ""
        let band = listener.status.flatMap { Bands.name(forHertz: Int($0.dialHertz)) }
        let contacts = logbook.contacts
        let workedCalls = Set(contacts.map { Callsign.normalized($0.call) })

        var rows: [Row] = []
        for (decode, _) in listener.decodes {
            guard let words = FT8Text(decode.text) else {
                if cqBox.state == .off, neededBox.state == .off {
                    rows.append(Row(decode: decode, line: DecodeLine.line(for: decode, words: nil, myCall: myCall)))
                }
                continue
            }
            if cqBox.state == .on, !words.isCQ { continue }
            let call = Callsign.normalized(words.plainFrom)
            let country = Countries.shared.country(of: call)
            let needed = worked.needed(country: country, band: band, modeGroup: "Data", log: contacts)
            let before = workedCalls.contains(call)
            if neededBox.state == .on, needed == nil { continue }
            if hideWorkedBox.state == .on, before { continue }
            let line = DecodeLine.line(for: decode, words: words, myCall: myCall, country: country?.name,
                                       needed: needed, workedBefore: before)
            rows.append(Row(decode: decode, line: line))
            // Someone calling you: said once, wherever focus is.
            if DecodeLine.isToMe(words, myCall: myCall), said.insert("\(decode.milliseconds) \(decode.text)").inserted,
               decode.isNew {
                Speaker.announce("\(words.from) is calling you in WSJT-X: \(words.exchange).")
            }
        }
        shown = rows
        table.reloadData()
        if let selectedKey, let row = shown.firstIndex(where: { $0.key == selectedKey }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if !shown.isEmpty, table.selectedRow < 0 {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        status.stringValue = DecodeLine.status(listener: listener, shown: shown.count, total: listener.decodes.count)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard shown.indices.contains(row) else { return nil }
        let id = NSUserInterfaceItemIdentifier("decodeCell")
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
        cell.textField?.stringValue = shown[row].line
        return cell
    }
}
