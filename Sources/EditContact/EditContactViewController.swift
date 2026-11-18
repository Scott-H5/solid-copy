// EditContactViewController.swift
//
// The Edit Contact sheet: every field of one contact, under headings
// (Contact, Radio, Location, Awards and activities, QSL, Contest, My
// station), in a scrolling area. The fields come from LogField.swift, so
// a field added there appears here too.
//
// Keys (accessibility contract, rule 21):
//   - The sheet opens in Callsign. Tab goes down through every field in
//     order (Callsign, Name, RST sent, RST received, Comment, Notes, Date,
//     Time, then the other groups), then Cancel and Save if Keyboard
//     navigation is on in System Settings, then back to Callsign. The area
//     scrolls to keep the field with focus in view.
//   - Return saves, from any field except the multi-line ones (Notes,
//     Address), where Return starts a new line. Command-Return and
//     Command-S (File > Save Contact) save from anywhere.
//   - Escape cancels, from any field, without changing anything.
//   - QSL statuses and "via" are menus in words (Yes, No, Requested ...;
//     Bureau, Direct ...), not ADIF's letters; QSL dates read and type
//     as 2025-12-17. Tab reaches the menus only when Keyboard navigation
//     is on in System Settings (as for buttons); VoiceOver reaches them
//     either way.
// The group headings can be read with VO-arrows; Tab skips them.
//
// Why a sheet rather than editing in the main form? The main form is for
// logging the next contact. Loading an old contact into it would make it
// easy to lose track of which one you're working on. A sheet is clearly
// separate, and Escape always gets you out.

import AppKit

@MainActor
final class EditContactViewController: NSViewController, NSTextFieldDelegate, NSTextViewDelegate {

    // Called with the changed contact when you save, or nil when you cancel.
    var onFinish: ((QSO?) -> Void)?

    private let original: QSO

    let callsignField = ScrollingTextField(string: "")
    private let dateField = ScrollingTextField(string: "")
    private let timeField = ScrollingTextField(string: "")
    // The single-line and multi-line fields, by ADIF name.
    private var lineFields: [String: NSTextField] = [:]
    private var textAreas: [String: NSTextView] = [:]
    // QSL statuses and "via" as menus in words (QSL.choices), with the
    // ADIF letter behind each item; and QSL dates shown as 2025-12-17.
    private var menus: [String: (button: NSPopUpButton, values: [String])] = [:]
    private var dateFieldNames: [String] = []

    init(qso: QSO) {
        original = qso
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    // MARK: - Building the sheet

    override func loadView() {
        let heading = NSTextField(labelWithString: "Edit contact with \(original.call)")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 2)

        // Every field goes into one grid, so all the labels line up.
        // `order` collects the fields in Tab order as they're added.
        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        var order: [NSView] = []

        func addLine(_ label: String, _ field: NSTextField, value: String) {
            field.stringValue = value
            field.setAccessibilityLabel(label)
            field.delegate = self
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
            grid.addRow(with: [FieldLabel(label), field])
            order.append(field)
        }

        // A menu for a QSL status or "via": words, not ADIF's letters. An
        // odd value already in the log gets an item of its own, so
        // opening and saving never changes it.
        func addMenu(_ field: LogField, _ choices: [(value: String, title: String)]) {
            var choices = choices
            let current = original[field.adif]
            if !choices.contains(where: { $0.value.caseInsensitiveCompare(current) == .orderedSame }) {
                choices.append((current, "\(current) (as logged)"))
            }
            let button = NSPopUpButton()
            button.addItems(withTitles: choices.map(\.title))
            button.selectItem(at: choices.firstIndex { $0.value.caseInsensitiveCompare(current) == .orderedSame } ?? 0)
            button.setAccessibilityLabel(field.label)
            grid.addRow(with: [FieldLabel(field.label), button])
            menus[field.adif] = (button, choices.map(\.value))
            order.append(button)
        }

        func addArea(_ field: LogField) {
            let area = ScrollingTextView()
            area.isRichText = false
            area.font = .systemFont(ofSize: NSFont.systemFontSize)
            area.delegate = self
            area.isVerticallyResizable = true
            area.autoresizingMask = [.width]
            area.textContainer?.widthTracksTextView = true
            area.setAccessibilityLabel(field.label)
            area.string = original[field.adif]
            let scroll = NSScrollView()
            scroll.documentView = area
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            scroll.heightAnchor.constraint(equalToConstant: field.adif == "notes" ? 90 : 60).isActive = true
            scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
            grid.addRow(with: [FieldLabel(field.label), scroll])
            textAreas[field.adif] = area
            order.append(area)
        }

        func addHeading(_ title: String) {
            let label = NSTextField(labelWithString: title)
            label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
            let row = grid.addRow(with: [label, NSGridCell.emptyContentView])
            // The heading spans both columns, starting at the left.
            row.mergeCells(in: NSRange(location: 0, length: 2))
            row.cell(at: 0).xPlacement = .leading
            row.topPadding = grid.numberOfRows > 1 ? 12 : 0
        }

        for group in LogField.Group.allCases {
            addHeading(group.rawValue)
            if group == .contact {
                addLine("Callsign", callsignField, value: original.call)
                callsignField.font = .monospacedSystemFont(ofSize: 16, weight: .medium)
            }
            // Your club fields show once named, or if this contact has a value in one.
                for field in LogField.all where field.group == group && field.editable
                    && (!field.isUnnamedClubField || !original[field.adif].isEmpty) {
                if field.multiline {
                    addArea(field)
                } else if let choices = QSL.choices(for: field.adif) {
                    addMenu(field, choices)
                } else if QSL.isDateField(field.adif) {
                    let textField = ScrollingTextField(string: "")
                    textField.placeholderString = "2025-12-17"
                    addLine(field.label, textField, value: QSL.readableDate(original[field.adif]))
                    lineFields[field.adif] = textField
                    dateFieldNames.append(field.adif)
                } else {
                    let textField = ScrollingTextField(string: "")
                    // Signal reports take only a sign and digits.
                    if SignalReportFormatter.fields.contains(field.adif) {
                        textField.formatter = SignalReportFormatter()
                    }
                    addLine(field.label, textField, value: original[field.adif])
                    lineFields[field.adif] = textField
                }
                // Date and Time go right after Notes, with the fields you
                // change most.
                if field.adif == "notes" {
                    addLine("Date (UTC)", dateField, value: original.utcDateText)
                    dateField.placeholderString = "2026-11-14"
                    addLine("Time (UTC)", timeField, value: original.utcTimeText)
                    timeField.placeholderString = "1432"
                }
            }
        }

        // The grid scrolls. A "flipped" document view starts at the top.
        let document = FlippedView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: document.topAnchor, constant: 4),
            grid.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 4),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -4),
            grid.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -4),
        ])
        let fieldsScroll = NSScrollView()
        fieldsScroll.documentView = document
        fieldsScroll.hasVerticalScroller = true
        fieldsScroll.drawsBackground = false
        document.translatesAutoresizingMaskIntoConstraints = false
        document.widthAnchor.constraint(equalTo: fieldsScroll.contentView.widthAnchor).isActive = true
        fieldsScroll.heightAnchor.constraint(equalToConstant: 520).isActive = true
        fieldsScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 540).isActive = true

        // Escape presses Cancel, and Command-Return presses Save, wherever
        // focus is in the sheet. (Plain Return is handled by the fields
        // themselves, so that Return in Notes can still start a new line.)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "Save", target: self, action: #selector(save(_:)))
        save.keyEquivalent = "\r"
        save.keyEquivalentModifierMask = [.command]
        let buttons = NSStackView(views: [cancel, save])
        buttons.spacing = 12

        let stack = NSStackView(views: [heading, fieldsScroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        view = stack

        // Tab order: every field from top to bottom, then Cancel and Save
        // (macOS lets Tab reach buttons only when Keyboard navigation is on
        // in System Settings > Keyboard), then back to Callsign.
        order += [cancel, save]
        for (index, item) in order.enumerated() {
            item.nextKeyView = order[(index + 1) % order.count]
        }
    }

    // MARK: - Save and Cancel

    @objc func save(_ sender: Any?) {
        let call = Callsign.normalized(callsignField.stringValue)
        guard Callsign.looksValid(call) else {
            return problem("Callsign not valid.", in: callsignField)
        }

        // The date and time. If you didn't change them, the original moment
        // is kept exactly, seconds included (the fields show only minutes).
        var timeOn = original.timeOn
        if dateField.stringValue != original.utcDateText || timeField.stringValue != original.utcTimeText {
            let date = dateField.stringValue.filter(\.isNumber)
            let time = timeField.stringValue.filter(\.isNumber)
            guard date.count == 8 else {
                return problem("Date not valid. Use year, month, day, like 2026-11-14.", in: dateField)
            }
            guard time.count == 4 || time.count == 6,
                  let parsed = QSO.date(adifDate: date, adifTime: time) else {
                return problem("Time not valid. Use hours and minutes in UTC, like 1432.", in: timeField)
            }
            timeOn = parsed
        }

        var updated = original
        updated.call = call
        updated.timeOn = timeOn
        for (adif, field) in lineFields {
            updated[adif] = field.stringValue
        }
        for (adif, area) in textAreas {
            updated[adif] = area.string
        }
        for (adif, menu) in menus where menu.values.indices.contains(menu.button.indexOfSelectedItem) {
            updated[adif] = menu.values[menu.button.indexOfSelectedItem]
        }
        // QSL dates as typed (2025-12-17) back to ADIF's 20251217.
        for adif in dateFieldNames {
            guard let field = lineFields[adif] else { continue }
            guard let day = QSL.adifDate(typed: field.stringValue) else {
                let name = LogField.named(adif)?.label ?? adif
                return problem("\(name) not valid. Type it like 2025-12-17, or leave it empty.", in: field)
            }
            updated[adif] = day
        }
        // The bands in ADIF's terms ("20" or "14.058" becomes "20m"), or
        // the band from the frequency if it's empty, so LoTW will take the
        // contact. Receive band too: TQSL refuses one that isn't a band
        // (VE6AAA, 16 November 2026, "Invalid RX BAND (14.058)").
        for (adif, name) in [("band", "Band"), ("band_rx", "Receive band")] {
            guard let field = lineFields[adif] else { continue }
            guard let band = Bands.normalized(field.stringValue) else {
                return problem("\(name) not valid. Type it like 20m, or a frequency like 14.058.", in: field)
            }
            updated[adif] = band
        }
        if updated["band"].isEmpty, let megahertz = Double(updated["freq"]), megahertz > 0,
           let band = Bands.name(forHertz: Int((megahertz * 1_000_000).rounded())) {
            updated["band"] = band
        }
        onFinish?(updated)
    }

    // File > Save Contact (Command-S). Added 16 November 2026, after an
    // edit was lost: Command-S is what Mac fingers reach for.
    @objc func saveContact(_ sender: Any?) {
        save(sender)
    }

    @objc func cancel(_ sender: Any?) {
        onFinish?(nil)
    }

    // Says what's wrong, and puts focus in the field that needs fixing.
    private func problem(_ message: String, in field: NSView) {
        view.window?.makeFirstResponder(field)
        NSSound.beep()
        Speaker.announce(message)
    }

    // MARK: - Keys

    // Return and Escape in the single-line fields.
    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            save(control)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancel(control)
            return true
        default:
            return false
        }
    }

    // Keys in the multi-line fields. Return makes a new line (Command-Return
    // is caught by the Save button first). Tab and Shift-Tab move between
    // fields, as everywhere else, instead of typing a tab character.
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            cancel(textView)
            return true
        case #selector(NSResponder.insertTab(_:)):
            view.window?.selectNextKeyView(textView)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            view.window?.selectPreviousKeyView(textView)
            return true
        default:
            return false
        }
    }

    // Keeps the callsign in capitals as you type.
    func controlTextDidChange(_ notification: Notification) {
        guard (notification.object as? NSTextField) === callsignField else { return }
        let upper = callsignField.stringValue.uppercased()
        if upper != callsignField.stringValue {
            callsignField.stringValue = upper
        }
    }
}

// A text field that scrolls itself into view when it gets focus, so Tab
// never moves focus to a field you can't see.
final class ScrollingTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { scrollToVisible(bounds.insetBy(dx: 0, dy: -24)) }
        return accepted
    }
}

// The same, for multi-line fields. The text sits in its own small
// scrolling box, so it's that box that's scrolled into view.
final class ScrollingTextView: NSTextView {
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, let box = enclosingScrollView {
            box.scrollToVisible(box.bounds.insetBy(dx: 0, dy: -24))
        }
        return accepted
    }
}

// A view whose y coordinates count down from the top, so scrolling content
// starts at the top rather than the bottom.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
