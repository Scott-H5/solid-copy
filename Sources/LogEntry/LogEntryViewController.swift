// LogEntryViewController.swift
//
// The main window's contents: the clocks, the logging form, the log table,
// and the details panel for the selected contact.
//
// The form is Callsign, then the fields you choose in Settings > Logging
// Form (Name, RST sent, RST received and Comment to begin with), in your
// order. Each can be a Tab stop or not; fields that aren't are still on
// screen and filled in by lookups, but Tab skips them. Changing the
// choices in Settings rebuilds the form at once, keeping what's typed.
//
// What it does, matching the accessibility contract:
//   - Callsign has focus when the window opens (rule 1).
//   - Tab goes through Callsign and the form's Tab stops, then back to
//     Callsign. Shift-Tab goes the other way (rule 2). The log table isn't
//     in this loop, so it never slows down logging; Command-I goes to it.
//     Name starts as not a Tab stop, because lookups fill it in (rule 7).
//   - Return in any field logs the contact, resets the form and goes back
//     to Callsign (rule 4). Escape clears the form (rule 5).
//   - Logging is announced, with the call spoken letter by letter
//     (rules 9 and 10).
//   - Leaving the Callsign field looks the call up (QRZ, then
//     callook.info; see CallsignLookup.swift). The result appears on a
//     line under the form and is spoken once, briefly (rule 11). Focus
//     never moves (rule 8). Name is filled in only if you haven't typed
//     one. If you log before the lookup finishes, the details are added to
//     that contact when they arrive.
//
// Contacts are saved to the log file the moment they're logged (see
// Logbook.swift). If saving fails, the form keeps what you typed.

import AppKit

@MainActor
final class LogEntryViewController: NSViewController, NSTextFieldDelegate, NSSearchFieldDelegate,
    NSMenuItemValidation {

    // All logged contacts, shared with the log table.
    // The log in use; `use` swaps in another (File > Open Log).
    private var logbook: Logbook

    init(logbook: Logbook) {
        self.logbook = logbook
        super.init(nibName: nil, bundle: nil)
    }

    // Required by AppKit for windows loaded from files, which this app
    // doesn't use.
    required init?(coder: NSCoder) { fatalError("Not used") }

    // The log table under the form. The menus send it commands too.
    private(set) lazy var logTable = LogTableViewController(logbook: logbook)
    // Told each contact logged on the form (automatic uploads,
    // AutoUploader.swift).
    var onLogged: ((UUID) -> Void)?

    // The details panel under the log, for the selected contact.
    private let details = ContactDetailsViewController()

    // The Callsign field, always first and always a Tab stop. Each field
    // has a visible label and the same spoken name (rule 16).
    let callsignField = FormTextField(string: "")

    // The other fields, made as needed and kept by ADIF name, so text you've
    // typed survives the form being rebuilt.
    private var fieldsByName: [String: NSTextField] = [:]

    // The form as it is now: each field after Callsign, and whether Tab
    // stops on it.
    private var formChoices: [FormFieldChoice] = []
    // Their labels when the form was built, so renaming a club field in
    // Settings > Clubs rebuilds it with the new name.
    private var formLabels: [String] = []

    // The grid holding the form, and the stack it sits in (so it can be
    // swapped for a new grid when the choices change).
    private var formGrid = NSGridView()
    private var mainStack: NSStackView?

    private func field(for adif: String) -> NSTextField {
        if let field = fieldsByName[adif] { return field }
        let field = FormTextField(string: "")
        field.setAccessibilityLabel(LogField.named(adif)?.label ?? adif)
        // Signal reports take only a sign and digits (SignalReport.swift).
        if SignalReportFormatter.fields.contains(adif) { field.formatter = SignalReportFormatter() }
        field.delegate = self
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        fieldsByName[adif] = field
        return field
    }



    // The heading over the log, with the number of contacts in it.
    private let logHeading = NSTextField(labelWithString: "")

    // MARK: Search

    // "Search the log", just above the log (Command-F). Not in the form's
    // Tab order, so it never slows down logging.
    private let searchField = NSSearchField()
    // Runs the search, and says how many match, once you pause typing.
    private var searchAnnouncement: Task<Void, Never>?

    // MARK: Callsign lookup

    // The line under the form that shows what the lookup found.
    private let lookupLabel = NSTextField(wrappingLabelWithString: "")
    // Calls being looked up now. Each lookup runs to the end (they're
    // short and limited by a timeout), so a contact logged before its
    // lookup finished still gets its details, even if you've moved on to
    // the next call.
    private var lookupsUnderWay: Set<String> = []
    // What the last lookup said in full, for Option-Command-N to repeat
    // however much was said at the time (Settings > Speech).
    private var lastLookupSpeech: (key: String, text: String)?
    // A lookup Option-Command-N started or is waiting for: said in full
    // when it finishes.
    private var sayWhenLookedUp: String?
    // The latest result for the call in the form.
    private var lookupResult: LookupResult?
    // Contacts logged before their lookup finished, by the call being
    // looked up: the details are added to each when they arrive.
    private var awaitingLookup: [String: [UUID]] = [:]
    // The contact being corrected from the form (Up Arrow in an empty
    // Callsign), or nil when the form is for a new contact.
    private var correctingID: UUID?
    // Their park (POTA_REF) searches POTA's park list (ParkSearch.swift).
    private let parkSearch = ParkSearch()
    // Fields from a spot that aren't on the form (its park, and its
    // frequency, band and mode when there's no radio), logged with the
    // contact. Cleared with the form.
    private var spotFields: [String: String] = [:]
    // The park filled in because the call is spotted at one on POTA
    // (fillParkFromSpots), so changing the call can take it back out.
    private var spottedPark: (call: String, reference: String)?
    // Club numbers for the call in Callsign (ClubNumbers.swift): from
    // SKCC's list and your log, worked out when you leave Callsign. Put
    // in empty form fields then, and logged in fields not on the form.
    private var clubNumbers: (call: String, values: [String: String])?
    // "Dupe: W1AW worked …" for the call in the form, shown and (call
    // spelled out) spoken, said first with its lookup (accessibility
    // contract, rule 12), or nil.
    private var dupeWarning: (shown: String, spoken: String)?

    // MARK: Radio

    // The radio pop-up under the clocks. Its label is the radio in use and
    // what it's doing, "Kenwood TS-590SG: 7.025241 MHz, CW, 40m, 5 W" (or
    // what's wrong); its menu switches to another radio. Hidden until you
    // have a radio. (A "pull-down" pop-up: the first menu item is the
    // label, so the label can say more than the item chosen.)
    private let radioButton = NSPopUpButton(frame: .zero, pullsDown: true)
    // Along the bottom: the Tuning and Offset controls (Command-T, then
    // Tab; see RadioSlider.swift) and the radio's
    // other settings, "Keyer 18 WPM, RIT off, AGC fast, ...". Hidden until
    // you have a radio.
    private let tuning = RadioSlider(
        name: "Tuning", help: "Up and Down tune 100 hertz, with Shift 10, with Option 1 kilohertz. "
            + "Tab goes to Offset, Escape back to Callsign.",
        steps: (RadioMonitor.tuningStep, RadioMonitor.fineTuningStep, RadioMonitor.coarseTuningStep))
    // The RIT or XIT offset. Hidden if the radio doesn't report one.
    private let offset = RadioSlider(
        name: "Offset", help: "The RIT or XIT offset. Up and Down change it 10 hertz, with Option 100. "
            + "Delete clears it. Escape goes back to Callsign.",
        steps: (10, 10, 100))
    // Power (in tenths of a watt, so Shift can step 0.1 W), RF gain and
    // squelch (in percent). Each hidden if the radio doesn't report it;
    // squelch only shows in FM.
    private let power = RadioSlider(
        name: "Power", help: "Transmit power. Up and Down change it 1 watt, with Shift a tenth, with Option 5. "
            + "Escape goes back to Callsign.",
        steps: (10, 1, 50))
    private let rfGain = RadioSlider(
        name: "RF gain", help: "Up and Down change it 5 percent, with Shift 1, with Option 20. "
            + "Escape goes back to Callsign.",
        steps: (5, 1, 20))
    private let squelch = RadioSlider(
        name: "Squelch", help: "FM squelch. Up and Down change it 5 percent, with Shift 1, with Option 20. "
            + "Escape goes back to Callsign.",
        steps: (5, 1, 20))
    // The controls Tab goes round, in order (those shown).
    private var radioSliders: [RadioSlider] { [tuning, offset, power, rfGain, squelch] }
    private let radioStatusLabel = NSTextField(wrappingLabelWithString: "")
    private var radioBar: NSStackView!

    // Radio fields you've typed in since the form was last cleared. The
    // radio doesn't change these: what you type wins.
    private var typedRadioFields: Set<String> = []
    // The call warned about having no band (see logContact): Return again
    // logs it anyway.
    private var noBandWarnedFor: String?

    // MARK: - Building the window

    override func loadView() {
        // The spoken name VoiceOver reads when the field has focus.
        callsignField.setAccessibilityLabel("Callsign")
        // The form reports Return, Escape and typing to this object.
        callsignField.delegate = self
        callsignField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        // A larger, fixed-width font for the call, so 0 and O are distinct.
        callsignField.font = .monospacedSystemFont(ofSize: 18, weight: .medium)
        let grid = makeFormGrid()

        logHeading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        logHeading.setAccessibilityRole(.staticText)

        // The table is a "child" of this view controller, so it's part of
        // the same window and gets keyboard commands in the right order.
        addChild(logTable)
        logTable.onLeave = { [weak self] in self?.focusCallsign() }

        // The details panel: Tab in the log goes there, Escape or
        // Shift-Tab comes back, and it follows the log's selection.
        addChild(details)
        logTable.onTab = { [weak self] in self?.details.focus() }
        // Shift-Tab in the log steps back to the form's last field.
        logTable.onBackTab = { [weak self] in
            guard let self else { return }
            self.view.window?.makeFirstResponder(self.tabStops.last ?? self.callsignField)
        }
        logTable.onSelectionChange = { [weak self] qso in
            guard let self else { return }
            let count = self.logTable.selectionCount
            if count > 1 {
                self.details.showMessage("\(count) contacts selected. Delete removes them all.")
            } else {
                self.details.show(qso)
            }
        }
        logTable.onShownChange = { [weak self] in
            guard let self else { return }
            // When the log stops showing a search (Escape, or Find This
            // Call), empty the search field to match.
            if self.logTable.searchFilter == nil, !self.searchField.stringValue.isEmpty {
                self.searchField.stringValue = ""
            }
            self.updateLogHeading()
        }
        details.onLeave = { [weak self] in self?.logTable.focusTable() }
        let detailsHeading = NSTextField(labelWithString: "Details")
        detailsHeading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        // UTC and local time across the top.
        let clocks = ClockBar()

        lookupLabel.preferredMaxLayoutWidth = 700

        searchField.placeholderString = "Search the log (Command-F)"
        searchField.setAccessibilityLabel("Search the log")
        searchField.delegate = self
        searchField.widthAnchor.constraint(equalToConstant: 360).isActive = true

        tuning.onStep = { RadioMonitor.shared.tune(by: $0) }
        offset.onStep = { RadioMonitor.shared.changeOffset(by: $0) }
        offset.onClear = { RadioMonitor.shared.clearOffset() }
        power.onStep = { RadioMonitor.shared.changeLevel(.power, by: Double($0) / 10) }
        rfGain.onStep = { RadioMonitor.shared.changeLevel(.rfGain, by: Double($0) / 100) }
        squelch.onStep = { RadioMonitor.shared.changeLevel(.squelch, by: Double($0) / 100) }
        // Tab goes on to the next control shown, and from the last back to
        // Callsign; Shift-Tab goes back, and from Tuning to Callsign;
        // Escape goes to Callsign.
        for slider in radioSliders {
            slider.onLeave = { [weak self, weak slider] leaving in
                guard let self, let slider, let index = radioSliders.firstIndex(of: slider) else { return }
                let shown = { (other: RadioSlider) in !other.isHidden }
                let next: RadioSlider?
                switch leaving {
                case .escape: next = nil
                case .tab: next = radioSliders[(index + 1)...].first(where: shown)
                case .backTab: next = radioSliders[..<index].last(where: shown)
                }
                if let next { view.window?.makeFirstResponder(next) } else { focusCallsign() }
            }
        }
        radioStatusLabel.preferredMaxLayoutWidth = 520
        radioBar = NSStackView(views: [tuning, offset, power, rfGain, squelch, radioStatusLabel])
        radioBar.spacing = 16
        radioBar.alignment = .centerY
        radioBar.detachesHiddenViews = false

        let stack = NSStackView(views: [clocks, radioButton, grid, lookupLabel, searchField, logHeading, logTable.view,
                                        detailsHeading, details.view, radioBar])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(20, after: radioButton)
        stack.setCustomSpacing(20, after: lookupLabel)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        // Hidden parts keep their place (see setLookupLine).
        stack.detachesHiddenViews = false
        view = stack
        mainStack = stack

        // The log fills the window's width, and takes any extra height
        // when the window is made bigger.
        logTable.view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        logTable.view.setContentHuggingPriority(.defaultLow, for: .vertical)
        details.view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        observeLogbook()
        // Rebuild the form when its fields change in Settings, and the
        // radio pop-up's menu when the radios do. (The menu a moment later:
        // choosing a radio from this very menu lands here, and its items
        // mustn't be thrown away while macOS is still handling the choice.)
        NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildFormIfChanged() }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.fillRadioButton() } }
        }
        // The radio's frequency, mode and power, as they change.
        NotificationCenter.default.addObserver(forName: RadioMonitor.didChange, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.radioChanged() }
        }
        parkSearch.show = { [weak self] in self?.setLookupLine($0) }
        updateLogHeading()
        resetForm()
        radioChanged()
    }

    // MARK: - Commands (also reachable from the Contact menu)

    // Saves the contact, resets the form and goes back to Callsign.
    @objc func logContact(_ sender: Any?) {
        // A frequency or mode typed in Callsign ("14060", "CW"): tune or
        // change mode, rather than log (see RadioControl.swift).
        if let entry = RadioEntry.parse(callsignField.stringValue, currentHertz: RadioMonitor.shared.reading?.hertz) {
            callsignField.stringValue = ""
            switch entry {
            case .frequency(let hertz): RadioMonitor.shared.tuneAndSay(toHertz: hertz)
            case .mode(let mode): RadioMonitor.shared.setMode(mode)
            }
            return
        }
        let call = Callsign.normalized(callsignField.stringValue)
        guard Callsign.looksValid(call) else {
            focusCallsign()
            Speaker.announce(call.isEmpty ? "Enter a callsign first." : "Callsign not valid.")
            return
        }
        // A park field must hold parks, not a half-typed search.
        for choice in formChoices where ParkSearch.fields.contains(choice.adif) {
            let park = field(for: choice.adif)
            guard parkSearch.resolve(park, label: LogField.named(choice.adif)?.label ?? "Park") else {
                view.window?.makeFirstResponder(park)
                return
            }
        }
        if let id = correctingID { return saveCorrection(id, call: call) }

        // The form as typed, for Undo to put back.
        let typed = formState()
        var qso = QSO(call: call, timeOn: Date())
        // Every field on the form, by its ADIF name.
        for choice in formChoices {
            qso[choice.adif] = field(for: choice.adif).stringValue
        }
        // Your station, from the profile in use (callsign, grid, park, ...).
        for (field, value) in Settings.currentProfile.station where !value.isEmpty {
            qso[field] = value
        }
        // The radio's latest frequency, band, mode and power (read within
        // the last second), for the radio fields you didn't type in.
        if let reading = RadioMonitor.shared.reading {
            for (field, value) in reading.fields where !typedRadioFields.contains(field) {
                qso[field] = value
            }
        }
        // From a spot: its park, and without a radio its frequency, band
        // and mode, for fields still empty.
        for (field, value) in spotFields where qso[field].isEmpty { qso[field] = value }
        // A serial sent by CW ({NR}) with Serial sent off the form.
        if qso["stx"].isEmpty, let serialSent { qso["stx"] = serialSent }
        // Club numbers (SKCC, FISTS, ...), for fields still empty.
        if let clubs = clubNumbers, clubs.call == call {
            for (field, value) in clubs.values where qso[field].isEmpty { qso[field] = value }
        }
        // What the lookup found, for fields you didn't fill in yourself.
        if let result = lookupResult, result.call == CallsignLookup.lookupCall(for: call) {
            for (field, value) in result.fields where qso[field].isEmpty {
                qso[field] = value
            }
        }
        Self.addDistance(to: &qso)
        // Where the antenna pointed (ADIF's ANT_AZ), if a rotor is set up
        // and its heading was read in the last 2 minutes (RotorControl).
        if qso["ant_az"].isEmpty, RotorControl.shared.isOn, let heading = RotorControl.shared.recentHeading {
            qso["ant_az"] = String(Int(heading.rounded()) % 360)
        }
        // Its country from cty.dat, if the lookup didn't give one.
        if qso["country"].isEmpty, let country = Countries.shared.country(of: call) { qso["country"] = country.name }
        // The band in ADIF's terms: "20" (or "20 meters", or "14.058"
        // typed in Band) is LoTW's "20m". Anything else isn't a band.
        guard let band = Bands.normalized(qso["band"]) else {
            Speaker.Cue.warning.play()
            view.window?.makeFirstResponder(field(for: "band"))
            Speaker.announce("Band \(qso["band"]) isn't a band. Type it like 20m, or a frequency like 14.058.")
            return
        }
        qso["band"] = band
        // Receive band likewise, if it's on the form; one that isn't a
        // band is left out rather than sent to LoTW to be refused.
        if !qso["band_rx"].isEmpty { qso["band_rx"] = Bands.normalized(qso["band_rx"]) ?? "" }
        // A frequency without a band (typed, with no radio): the band
        // follows from it.
        if qso["band"].isEmpty, let megahertz = Double(qso["freq"]), megahertz > 0,
           let band = Bands.name(forHertz: Int((megahertz * 1_000_000).rounded())) {
            qso["band"] = band
        }
        // No band at all: most likely the radio dropped without your
        // noticing (the author's VE6BBP, December 2025, logged while another
        // logger had the radio). LoTW won't take a contact without one, and
        // awards need it. Warn once; Return again logs it anyway.
        if qso["band"].isEmpty, noBandWarnedFor != call {
            noBandWarnedFor = call
            Speaker.Cue.warning.play()
            let radio = RadioMonitor.shared.reading == nil ? "The radio isn't connected. " : ""
            Speaker.announce("No band. \(radio)Type the band or frequency, or press Return again to log without it.")
            return
        }
        do {
            try logbook.add(qso)
        } catch {
            // Not saved: keep everything in the form so nothing is lost,
            // and say what went wrong.
            Speaker.announce("Not saved. \(error.localizedDescription)")
            NSSound.beep()
            return
        }

        // If the lookup hasn't finished (or hasn't started), its details
        // are added to this contact when they arrive.
        let key = CallsignLookup.lookupCall(for: call)
        if lookupResult?.call != key, Settings.lookupEnabled {
            awaitingLookup[key, default: []].append(qso.id)
            startLookup(for: call)
        }

        logTable.showAllContacts()
        resetForm()
        focusCallsign()
        registerUndoLog(qso.id, form: typed)
        onLogged?(qso.id)
        // With its serial number, when it has one (a contest), so you
        // needn't look in the details (the author, 17 November 2026).
        let number = qso["stx"].trimmingCharacters(in: .whitespaces)
        let serial = number.isEmpty ? "" : ", number \(number)"
        Speaker.say(.logging, full: "Logged \(Callsign.spoken(qso.call))\(serial). \(logbook.countText) in the log.",
                    brief: number.isEmpty ? "Logged." : "Logged, \(number).", cue: .logged)
    }

    // Empties the form and goes back to Callsign. Edit > Undo brings back
    // what was in it.
    @objc func clearForm(_ sender: Any?) {
        // Correcting a logged contact: leave it as it is in the log.
        if let id = correctingID {
            let call = logbook.index(of: id).map { logbook.contacts[$0].call } ?? ""
            resetForm()
            focusCallsign()
            return Speaker.announce(call.isEmpty ? "New contact." : "\(Callsign.spoken(call)) left as it was.")
        }
        let before = formState()
        logTable.showAllContacts()
        resetForm()
        focusCallsign()
        guard !before.isEmpty else { return Speaker.announce("Cleared.") }
        undoManager?.registerUndo(withTarget: self) { $0.unclear(before) }
        undoManager?.setActionName("Clear Form")
        Speaker.announce(undoManager?.isRedoing == true ? "Cleared again." : "Cleared. Command-Z brings it back.")
    }

    // MARK: - Undo for logging and clearing
    //
    // Command-Z (Edit > Undo) right after logging takes the contact back
    // out of the log and puts what you'd typed back in the form, so a
    // wrong call or report is one key to fix: correct it and press Return
    // again. After Clear Form (Escape or Command-K) it brings the cleared
    // text back. Redo (Shift-Command-Z) does the step again.
    //
    // These share the window's undo list with typing, edits and deletes,
    // so Undo always takes back the most recent thing, whatever it was.
    // The menu item says which ("Undo Log Contact").

    // What the form holds: the call, every field by ADIF name, the radio
    // fields you'd typed in, and the lookup and its line.
    private struct FormState {
        var call: String
        var fields: [String: String]
        var typedRadioFields: Set<String>
        var lookupResult: LookupResult?
        var lookupLine: String
        // True when there's nothing to bring back: no call, and every
        // field at its starting value (set by formState).
        var isEmpty = false
    }

    private func formState() -> FormState {
        let fields = fieldsByName.mapValues(\.stringValue)
        let starting = Dictionary(formChoices.map { ($0.adif, $0.startingValue) }, uniquingKeysWith: { a, _ in a })
        let call = callsignField.stringValue
        let isEmpty = call.trimmingCharacters(in: .whitespaces).isEmpty
            && fields.allSatisfy { $0.value == (starting[$0.key] ?? "") }
        return FormState(call: call, fields: fields, typedRadioFields: typedRadioFields,
                         lookupResult: lookupResult, lookupLine: lookupLabel.stringValue, isEmpty: isEmpty)
    }

    private func observeLogbook() {
        let observed = logbook
        logbook.observe { [weak self] in
            guard let self, self.logbook === observed else { return }
            self.updateLogHeading()
        }
    }

    // Switches the form and the log under it to another log (Logs.swift
    // has already checked the form is empty). Everything tied to the old
    // log goes: the undo history (Command-Z must never act on a log you've
    // left), lookups waiting to fill logged contacts, a correction in
    // progress. The views stay, and focus goes to Callsign.
    func use(_ newLogbook: Logbook) {
        logbook = newLogbook
        view.window?.undoManager?.removeAllActions()
        awaitingLookup = [:]
        observeLogbook()
        logTable.use(newLogbook)
        resetForm()
        updateLogHeading()
    }

    // The mode now, for dupes and "needed": as typed on the form, or the
    // radio's. The radio's data modes (PKTUSB, PKTLSB ...) can't be named
    // for the log (FT8? PSK?), but they're data, so "DATA" here, not
    // unknown, which once made every sideband contact look like a dupe.
    private func modeNow() -> String {
        if let typed = onForm("mode"), !typed.isEmpty { return typed }
        guard let reading = RadioMonitor.shared.reading else { return "" }
        if let mode = reading.fields["mode"] { return mode }
        return reading.mode.uppercased().hasPrefix("PKT") ? "DATA" : ""
    }

    // A field's text, only if it's on the form now. Fields stay made when
    // the form changes (so typing survives a profile switch), and a hidden
    // one can hold old text: a Mode of CW from the Portable profile made
    // every contact a dupe in a Field Day log, whatever the radio said
    // (the author, 17 November 2026). Nil when the field isn't on the form.
    private func onForm(_ adif: String) -> String? {
        guard formChoices.contains(where: { $0.adif == adif }) else { return nil }
        return fieldsByName[adif]?.stringValue.trimmingCharacters(in: .whitespaces)
    }

    // The fill-ins for CW messages (CWMessages.swift): yours from the
    // profile and Settings > CW, theirs from the form, the lookup and
    // club numbers.
    func cwFillIns() -> [String: String] {
        let station = Settings.currentProfile.station
        let call = Callsign.normalized(callsignField.stringValue)
        func theirs(_ adif: String) -> String {
            let typed = onForm(adif) ?? ""
            if !typed.isEmpty { return typed }
            if let clubs = clubNumbers, clubs.call == call, let value = clubs.values[adif] { return value }
            if let result = lookupResult, result.call == CallsignLookup.lookupCall(for: call) {
                // QRZ's name is the full name; CW sends the first.
                if adif == "name" { return result.firstName }
                return result.fields[adif] ?? ""
            }
            return ""
        }
        let rst = onForm("rst_sent") ?? ""
        // Your exchange: as typed in Exchange sent, or its starting value
        // if it's not on the form.
        let sent = onForm("stx_string")
            ?? formChoices.first { $0.adif == "stx_string" }?.startingValue ?? ""
        return ["SENT": sent, "MYCALL": station["station_callsign"] ?? "", "MYNAME": Settings.cwMyName,
                "MYSTATE": station["my_state"] ?? "", "NR": serialForContact(),
                "CALL": call, "NAME": theirs("name"), "STATE": theirs("state"), "SKCC": theirs("skcc"),
                "RST": rst.isEmpty ? "599" : rst]
    }

    // Puts the form back as it was and goes to Callsign. Fields added to
    // the form since are left as they are.
    private func restoreForm(_ state: FormState) {
        correctingID = nil
        dupeWarning = nil
        callsignField.stringValue = state.call
        for (adif, value) in state.fields { fieldsByName[adif]?.stringValue = value }
        typedRadioFields = state.typedRadioFields
        lookupResult = state.lookupResult
        setLookupLine(state.lookupLine)
        // Radio fields you hadn't typed in follow the radio, as usual.
        fillRadioFields()
        logTable.showAllContacts()
        focusCallsign()
    }

    private func registerUndoLog(_ id: UUID, form: FormState) {
        undoManager?.registerUndo(withTarget: self) { $0.unlog(id, form: form) }
        undoManager?.setActionName("Log Contact")
    }

    // Undo of logging: out of the log, back into the form.
    private func unlog(_ id: UUID, form: FormState) {
        // Gone already (deleted, say): nothing to take out, and the undo
        // list moves on.
        guard let index = logbook.index(of: id) else {
            return Speaker.announce("That contact is no longer in the log.")
        }
        let qso: QSO
        do {
            qso = try logbook.remove(at: index)
        } catch {
            Speaker.announce("Not undone. \(error.localizedDescription)")
            NSSound.beep()
            return
        }
        // A lookup still under way mustn't add its details to it now.
        for key in awaitingLookup.keys { awaitingLookup[key]?.removeAll { $0 == id } }
        restoreForm(form)
        // Redo logs it again: the same contact, time and all.
        undoManager?.registerUndo(withTarget: self) { $0.relog(qso, at: index, form: form) }
        undoManager?.setActionName("Log Contact")
        Speaker.announce("\(Callsign.spoken(qso.call)) taken out of the log and back in the form. "
            + "\(logbook.countText) in the log.")
    }

    // Redo of logging: the contact goes back where it was, the form empties.
    private func relog(_ qso: QSO, at index: Int, form: FormState) {
        do {
            try logbook.insert(qso, at: index)
        } catch {
            Speaker.announce("Not logged. \(error.localizedDescription)")
            NSSound.beep()
            return
        }
        logTable.showAllContacts()
        resetForm()
        focusCallsign()
        registerUndoLog(qso.id, form: form)
        Speaker.say(.logging, full: "Logged \(Callsign.spoken(qso.call)) again. \(logbook.countText) in the log.",
                    brief: "Logged again.", cue: .logged)
    }

    // Undo of Clear Form. Redo clears it again.
    private func unclear(_ form: FormState) {
        restoreForm(form)
        undoManager?.registerUndo(withTarget: self) { $0.clearForm(nil) }
        undoManager?.setActionName("Clear Form")
        Speaker.announce("Form back.")
    }

    @objc func goToCallsign(_ sender: Any?) {
        focusCallsign()
    }

    // Moves focus to the newest contact in the log (rule 6). VoiceOver
    // reads it, and Escape comes back to Callsign.
    @objc func showLastContact(_ sender: Any?) {
        logTable.showLastContact()
    }

    // Moves focus to the details panel for the selected contact (or the
    // newest, if none is selected). Escape goes back to the log.
    @objc func showDetails(_ sender: Any?) {
        guard logTable.selectNewestIfNone() else {
            Speaker.announce("No contacts logged yet.")
            return
        }
        details.focus()
    }

    // Turns this form's menu commands off while a sheet (such as Edit
    // Contact) is open, so a shortcut like Command-Return in the sheet
    // can't log or clear the form behind it.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        view.window?.attachedSheet == nil
    }

    // MARK: - Helpers

    func focusCallsign() {
        view.window?.makeFirstResponder(callsignField)
    }

    private func resetForm() {
        correctingID = nil
        spotFields = [:]
        spottedPark = nil
        clubNumbers = nil
        serialSent = nil
        noBandWarnedFor = nil
        dupeWarning = nil
        lookupResult = nil
        lastLookupSpeech = nil
        sayWhenLookedUp = nil
        setLookupLine("")
        callsignField.stringValue = ""
        // Each field back to the profile's starting value (5 for Power on
        // the Portable form, say), or empty.
        let starting = Dictionary(formChoices.map { ($0.adif, $0.startingValue) }, uniquingKeysWith: { a, _ in a })
        for (adif, field) in fieldsByName {
            field.stringValue = starting[adif] ?? ""
        }
        typedRadioFields = []
        fillRadioFields()
        fillSerial()
    }

    // MARK: Serial numbers
    //
    // "Serial sent" (STX) counts itself: when it's on the form, a fresh
    // form shows the next number, 1 more than the highest already logged
    // in this log for the same contest (the form's Contest, or none). So
    // it's right after a deleted contact, a correction, or contacts pasted
    // in, and each log and contest has its own count. Type over it to
    // change it; logging moves on from whatever was logged. {NR} in a CW
    // message sends the same number, and is logged as Serial sent even
    // when the field isn't on the form. (the author, 17 November 2026: contests
    // need serials with or without the keyer.)

    // The contest the form is for: its Contest field, or that field's
    // starting value if it isn't on the form.
    private var formContest: String {
        let typed = onForm("contest_id")
            ?? formChoices.first { $0.adif == "contest_id" }?.startingValue ?? ""
        return typed.trimmingCharacters(in: .whitespaces).uppercased()
    }

    func nextSerial() -> Int {
        Contest.nextSerial(in: logbook.contacts, contest: formContest)
    }

    // Puts the next number in Serial sent, if it's on the form.
    private func fillSerial() {
        guard formChoices.contains(where: { $0.adif == "stx" }), let field = fieldsByName["stx"] else { return }
        field.stringValue = String(nextSerial())
    }

    // This contact's serial: as shown (or typed) in Serial sent, or the
    // next one.
    func serialForContact() -> String {
        let shown = onForm("stx") ?? ""
        return shown.isEmpty ? String(nextSerial()) : shown
    }

    // A CW message sent {NR}: that number is logged with the contact, as
    // its Serial sent, even if the field isn't on the form.
    private var serialSent: String?
    func serialWasSent(_ serial: String) { serialSent = serial }

    // MARK: - Radio

    private func radioChanged() {
        let text = RadioMonitor.shared.stateText
        let shown = text.isEmpty ? "No radio" : "\(RadioMonitor.shared.radioName): \(text)"
        if radioButton.numberOfItems == 0 { fillRadioButton() }
        if radioButton.itemTitle(at: 0) != shown { radioButton.item(at: 0)?.title = shown }
        let monitor = RadioMonitor.shared
        let reading = monitor.reading
        tuning.show(reading.map { "\($0.kilohertzText) kHz" } ?? "No radio",
                    spoken: reading.map { "\($0.kilohertzText) kilohertz" } ?? "no radio")
        if let hertz = monitor.offsetHertz {
            let sign = hertz > 0 ? "+" : ""
            offset.show("Offset \(sign)\(hertz) Hz",
                        spoken: hertz == 0 ? "0 hertz" : "\(hertz > 0 ? "plus" : "minus") \(abs(hertz)) hertz")
        }
        if let watts = monitor.level(.power) {
            power.show("Power \(RadioReading.wattsText(watts)) W", spoken: RadioMonitor.spoken(.power, watts))
        }
        for (slider, level, name) in [(rfGain, RadioMonitor.Level.rfGain, "RF gain"), (squelch, .squelch, "Squelch")] {
            guard let fraction = monitor.level(level) else { continue }
            slider.show("\(name) \(RadioStatus.percent(fraction))", spoken: RadioMonitor.spoken(level, fraction))
        }
        // Each control is hidden while there's nothing to show (no offset,
        // a radio that doesn't report power, squelch outside FM); focus goes
        // back to Callsign first, if it was there.
        let hide: [(RadioSlider, Bool)] = [
            (offset, monitor.offsetHertz == nil), (power, monitor.level(.power) == nil),
            (rfGain, monitor.level(.rfGain) == nil), (squelch, monitor.level(.squelch) == nil),
        ]
        for (slider, hidden) in hide where slider.isHidden != hidden {
            if hidden, view.window?.firstResponder === slider { focusCallsign() }
            slider.isHidden = hidden
        }
        let status = monitor.reading == nil ? "" : monitor.status?.shown ?? ""
        if radioStatusLabel.stringValue != status { radioStatusLabel.stringValue = status }
        // Hidden when empty, so VoiceOver doesn't land on nothing.
        radioStatusLabel.isHidden = status.isEmpty
        fillRadioFields()
    }

    // Radio > Tune (Command-T): focus to the tuning control.
    @objc func focusTuning(_ sender: Any?) {
        guard !radioBar.isHidden else { return Speaker.announce("No radio set up. Add one in Settings, Radio.") }
        view.window?.makeFirstResponder(tuning)
    }

    // The pop-up's menu: the label, then each radio and No Radio (the one
    // in use ticked), then Radio Settings. Hidden when you have no radios,
    // so VoiceOver doesn't land on something with nothing to offer (it
    // keeps its space; see setLookupLine).
    private func fillRadioButton() {
        let label = radioButton.numberOfItems > 0 ? radioButton.itemTitle(at: 0) : "No radio"
        radioButton.removeAllItems()
        radioButton.addItem(withTitle: label)
        for item in RadioMenu.choices(withShortcuts: false) { radioButton.menu?.addItem(item) }
        radioButton.menu?.addItem(.separator())
        radioButton.menu?.addItem(NSMenuItem(title: "Radio Settings…", action: RadioMenu.editRadio, keyEquivalent: ""))
        radioButton.isHidden = Settings.radios.isEmpty
        radioBar.isHidden = Settings.radios.isEmpty
    }

    // Puts the radio's values in the form's radio fields, except ones
    // you've typed in and the one you're in (it would change under you).
    private func fillRadioFields() {
        guard let reading = RadioMonitor.shared.reading else { return }
        let editing = (view.window?.firstResponder as? NSText)?.delegate as? NSTextField
        for (adif, value) in reading.fields where !typedRadioFields.contains(adif) {
            guard let field = fieldsByName[adif], field !== editing, field.stringValue != value else { continue }
            field.stringValue = value
        }
    }

    // MARK: - Building the form

    // The form's Tab stops in order: Callsign, then each field marked as a
    // Tab stop.
    private var tabStops: [NSTextField] {
        [callsignField] + formChoices.filter(\.tabStop).map { field(for: $0.adif) }
    }

    // A grid with labels on the left and fields on the right, from the
    // choices in Settings. The labels are hidden from VoiceOver (see
    // FieldLabel.swift), because each field speaks its own name.
    private func makeFormGrid() -> NSGridView {
        formChoices = Settings.formFields.filter { LogField.named($0.adif)?.canGoOnForm == true }
        var rows: [[NSView]] = [[FieldLabel("Callsign"), callsignField]]
        formLabels = formChoices.map { LogField.named($0.adif)?.label ?? $0.adif }
        for (choice, label) in zip(formChoices, formLabels) {
            let field = field(for: choice.adif)
            field.setAccessibilityLabel(label)
            rows.append([FieldLabel(label), field])
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 10
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.setContentHuggingPriority(.required, for: .vertical)
        formGrid = grid
        linkTabOrder()
        return grid
    }

    // The Tab order, set explicitly rather than left to macOS, so it never
    // changes by accident. Tab goes from each Tab stop to the next, wrapping
    // to Callsign. A field that isn't a Tab stop (if you click in it or
    // reach it with VoiceOver) moves on to the next Tab stop after it.
    private func linkTabOrder() {
        let stops = tabStops
        let all = [callsignField] + formChoices.map { field(for: $0.adif) }
        for (index, field) in all.enumerated() {
            let next = all[(index + 1)...].first { stops.contains($0) } ?? callsignField
            field.nextKeyView = next
        }
    }

    // Shift-Tab: the Tab stop before this field, wrapping from Callsign to
    // the last. Done here rather than by macOS, which works Shift-Tab out
    // from nextKeyView: when a skipped field (Name) and Callsign both lead
    // to RST sent, macOS can pick Name, and Shift-Tab lands on a field
    // that isn't a Tab stop.
    private func previousTabStop(before field: NSTextField) -> NSTextField {
        let stops = tabStops
        let all = [callsignField] + formChoices.map { self.field(for: $0.adif) }
        guard let index = all.firstIndex(of: field) else { return callsignField }
        return all[..<index].last { stops.contains($0) } ?? stops.last ?? callsignField
    }

    // Swaps in a new grid if the form's fields changed in Settings. Text
    // already typed stays in its field; focus stays where it was.
    private func rebuildFormIfChanged() {
        let choices = Settings.formFields.filter { LogField.named($0.adif)?.canGoOnForm == true }
        guard choices != formChoices || choices.map({ LogField.named($0.adif)?.label ?? $0.adif }) != formLabels,
              let stack = mainStack, let index = stack.arrangedSubviews.firstIndex(of: formGrid) else { return }
        // The form field you're in, if any. While you type in a field,
        // macOS's first responder is a shared "field editor" standing in
        // for it, not the field itself, so ask the editor whose it is.
        // (Restoring the field editor itself fails once its field has been
        // moved, and leaves focus nowhere.)
        let responder = view.window?.firstResponder
        let focusedField = ((responder as? NSText)?.delegate as? NSTextField) ?? (responder as? NSTextField)
        let wasInForm = focusedField.map { $0 === callsignField || fieldsByName.values.contains($0) } ?? false
        let wasOnForm = Set(formChoices.map(\.adif))
        let old = formGrid
        // Take the fields out of the old grid before putting them in the new.
        for field in [callsignField] + Array(fieldsByName.values) { field.removeFromSuperview() }
        stack.removeArrangedSubview(old)
        old.removeFromSuperview()
        stack.insertArrangedSubview(makeFormGrid(), at: index)
        // Fields new to the form (after switching profiles, say) start at
        // their starting values; fields already there keep what's typed.
        // (While correcting a contact, they get its values instead, so
        // saving doesn't overwrite them.)
        let corrected = correctingID.flatMap { logbook.index(of: $0) }.map { logbook.contacts[$0] }
        for choice in formChoices where !wasOnForm.contains(choice.adif) {
            field(for: choice.adif).stringValue = corrected?[choice.adif] ?? choice.startingValue
        }
        // Serial sent just added (another profile, say): the next number.
        if corrected == nil, !wasOnForm.contains("stx") { fillSerial() }
        stack.setCustomSpacing(20, after: stack.arrangedSubviews[index - 1])
        // New radio fields get the radio's values.
        fillRadioFields()
        // Back to the field you were in; or, if it's no longer on the form,
        // to Callsign. Focus elsewhere (the log, Settings) is left alone.
        if wasInForm, let focusedField {
            view.window?.makeFirstResponder(focusedField.window == nil ? callsignField : focusedField)
        }
    }

    private func updateLogHeading() {
        if let text = logTable.searchFilter {
            let count = shownCount
            logHeading.stringValue = "Log: \(Self.matchText(count)) “\(text)”. Escape shows the whole log."
        } else if let which = logTable.qslFilter {
            let count = shownCount
            logHeading.stringValue = "Log: \(count == 1 ? "1 contact" : "\(count) contacts") \(which.heading). "
                + "Escape shows the whole log."
        } else if let call = logTable.callFilter {
            let count = logbook.contacts.filter { $0.call == call }.count
            logHeading.stringValue = "Log: \(count == 1 ? "1 contact" : "\(count) contacts") with \(call). "
                + "Escape shows the whole log."
        } else {
            logHeading.stringValue = "Log: \(logbook.countText)"
        }
    }

    // How many contacts the log is showing.
    private var shownCount: Int {
        ((logTable.view as? NSScrollView)?.documentView as? NSTableView)?.numberOfRows ?? 0
    }

    // "No contacts match", "1 contact matches", "12 contacts match".
    private static func matchText(_ count: Int) -> String {
        switch count {
        case 0: return "No contacts match"
        case 1: return "1 contact matches"
        default: return "\(count) contacts match"
        }
    }

    // Contact > Search the Log (Command-F): puts focus in the search field,
    // with any earlier search selected so typing replaces it.
    @objc func searchLog(_ sender: Any?) {
        view.window?.makeFirstResponder(searchField)
        searchField.currentEditor()?.selectAll(nil)
    }

    // Runs the search after a short pause in typing (so a fast typist
    // doesn't search a big log once per letter), then says how many match
    // after a longer pause.
    private func searchChanged() {
        searchAnnouncement?.cancel()
        let text = searchField.stringValue
        searchAnnouncement = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self, !Task.isCancelled else { return }
            let count = self.logTable.search(text)
            self.updateLogHeading()
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled else { return }
            Speaker.announce(Self.matchText(count) + ".")
        }
    }

    // Keys in the search field: Return, Down Arrow or Tab go to the first
    // match; Escape clears the search and goes back to Callsign.
    private func searchKey(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.moveDown(_:)),
             #selector(NSResponder.insertTab(_:)):
            // Search now, in case the pause hasn't passed yet.
            searchAnnouncement?.cancel()
            logTable.search(searchField.stringValue)
            updateLogHeading()
            if shownCount == 0 {
                Speaker.announce(Self.matchText(0) + ".")
            } else {
                searchAnnouncement?.cancel()
                logTable.focusFirstContact()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            searchAnnouncement?.cancel()
            searchField.stringValue = ""
            logTable.showAllContacts()
            focusCallsign()
            return true
        default:
            return false
        }
    }

    // A reminder on the lookup line when there are earlier contacts.
    private func findHint(for call: String) -> String {
        logbook.contacts.contains { $0.call == call } ? " Option-Command-F shows them." : ""
    }

    // Contact > Find This Call in the Log (Option-Command-F): narrows the log to
    // the call in the Callsign field (or, from the log, the selected
    // contact's call) and moves focus to the newest of them. Tab goes to
    // its details (notes and all); Escape shows the whole log again and
    // comes back to Callsign, with the form as you left it.
    @objc func findCallInLog(_ sender: Any?) {
        // In the log or details: the selected contact's call. Anywhere
        // else: the call in the Callsign field.
        let inLog = view.window?.firstResponder is LogTableView || view.window?.firstResponder is DetailsTableView
        let call = inLog ? (logTable.selectedContact?.call ?? "") : Callsign.normalized(callsignField.stringValue)
        guard !call.isEmpty else {
            Speaker.announce("Type a callsign first.")
            return
        }
        let count = logTable.showContacts(with: call)
        if count == 0 {
            Speaker.announce("No contacts with \(Callsign.spoken(call)) in the log.")
        } else {
            Speaker.announce("\(count == 1 ? "1 contact" : "\(count) contacts") with \(Callsign.spoken(call)).")
        }
    }

    // MARK: - Keys typed in the fields

    // Called for special keys typed in any of the fields. Returning true
    // means "handled here"; false lets the field handle the key normally.
    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        if control === searchField { return searchKey(commandSelector) }
        if let field = control as? NSTextField, isParkField(field),
           parkSearch.key(commandSelector, in: field) { return true }
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            logContact(control)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            // CW being sent: Escape stops it, and nothing else, as in
            // contest loggers (the author's choice, 17 November 2026).
            if WinKeyer.shared.stop() {
                Speaker.announce("Stopped.")
                return true
            }
            clearForm(control)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            guard let field = control as? NSTextField else { return false }
            view.window?.makeFirstResponder(previousTabStop(before: field))
            return true
        case #selector(NSResponder.moveUp(_:)) where control === callsignField:
            return stepThroughLog(older: true)
        case #selector(NSResponder.moveDown(_:)) where control === callsignField:
            return stepThroughLog(older: false)
        default:
            return false
        }
    }

    // Called when you leave a field. Leaving Callsign starts its lookup.
    func controlTextDidEndEditing(_ notification: Notification) {
        if let field = notification.object as? NSTextField, isParkField(field) { return parkSearch.left(field) }
        if let field = notification.object as? NSTextField, field === fieldsByName["skcc"] { return checkSKCC() }
        guard (notification.object as? NSTextField) === callsignField else { return }
        callsignDone()
    }

    // A call is in Callsign: look it up, and check for a dupe.
    private func callsignDone() {
        let call = Callsign.normalized(callsignField.stringValue)
        // Correcting a contact without changing its call: nothing to look
        // up, and it would only find itself as a dupe.
        if let id = correctingID, let index = logbook.index(of: id), logbook.contacts[index].call == call { return }
        dupeWarning = correctingID == nil ? dupeText(for: call) : nil
        fillClubNumbers(for: call)
        fillParkFromSpots(for: call)
        let lookingUp = startLookup(for: call)
        // No lookup to say it with (lookups off, or already looked up):
        // the warning is said on its own.
        if let dupe = dupeWarning, !lookingUp {
            Alert.dupe.play()
            setLookupLine(dupe.shown + " " + lookupLabel.stringValue)
            Speaker.announce(dupe.spoken)
        }
        // With lookups off, the country (and whether it's needed) and club
        // numbers are said on their own (with a lookup, they're said with it).
        if !Settings.lookupEnabled, dupeWarning == nil, Callsign.looksValid(call) {
            let entity = entityWords(for: call, lookupPlace: "")
            let clubs = clubsSpoken(call)
            let spoken = [entity.spoken, clubs].filter { !$0.isEmpty }.joined(separator: ". ")
            if !spoken.isEmpty {
                setLookupLine("\(call): \(entity.shown)\(clubsShown(call))")
                sayLookupSpeech(full: spoken + ".", brief: spoken, cue: .found, needed: entityText(for: call)?.needed != nil)
            }
        }
        // An SKCC number typed before the call is checked now.
        if clubNumbers?.values["skcc"] == nil { checkSKCC() }
    }

    // Hunting a park you tuned to yourself (v1.6 item 1): if the call is
    // spotted at a POTA park, the park goes in (their park field if it's
    // on the form and empty, and is logged either way). It's said with
    // the lookup, or on its own if the lookup was already said, since the
    // spots may need fetching first. Not when correcting a contact, not
    // when a spot or you already gave a park.
    private func fillParkFromSpots(for call: String) {
        // A park filled in for an earlier call in this form comes out.
        if let old = spottedPark {
            if spotFields["pota_ref"] == old.reference { spotFields["pota_ref"] = nil }
            if let field = fieldsByName["pota_ref"], field.stringValue == old.reference { field.stringValue = "" }
            spottedPark = nil
        }
        guard correctingID == nil, Callsign.looksValid(call), spotFields["pota_ref"] == nil,
              (fieldsByName["pota_ref"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        else { return }
        var answeredAtOnce = true
        SpotList.shared.withRecentPOTASpots { [weak self] spots in
            guard let self, Callsign.normalized(self.callsignField.stringValue) == call,
                  self.correctingID == nil, self.spotFields["pota_ref"] == nil,
                  let spot = POTASpots.matchingPark(for: call, in: spots) else { return }
            if let field = self.fieldsByName["pota_ref"] {
                guard field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                field.stringValue = spot.reference
            }
            self.spotFields["pota_ref"] = spot.reference
            self.spottedPark = (call, spot.reference)
            // Said with the lookup unless that's already been said.
            let key = CallsignLookup.lookupCall(for: call)
            guard !answeredAtOnce, !self.lookupsUnderWay.contains(key) else { return }
            let park = self.spottedParkText(call)
            self.setLookupLine(self.lookupLabel.stringValue + " " + park.shown)
            Speaker.say(.lookup, full: park.spoken + ".", brief: spot.reference, cue: .found)
        }
        answeredAtOnce = false
    }

    // "At park US-1333 Big Pocono State Park, Pennsylvania", for the
    // lookup line (shown) and speech, or empty.
    private func spottedParkText(_ call: String) -> (shown: String, spoken: String) {
        guard let park = spottedPark, park.call == Callsign.normalized(call) else { return ("", "") }
        let name = ParkList.shared.park(park.reference)?.spoken ?? park.reference
        return ("At park \(name). ", "at park \(name)")
    }

    // The call's club numbers, into any empty club field on the form.
    // An SKCC number already typed is left for checkSKCC.
    private func fillClubNumbers(for call: String) {
        guard Callsign.looksValid(call) else { clubNumbers = nil; return }
        SKCCRoster.shared.start()
        var values = ClubNumbers.numbers(for: call, in: logbook.contacts)
        for (adif, value) in values {
            guard let field = fieldsByName[adif], formChoices.contains(where: { $0.adif == adif }) else { continue }
            if field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
                field.stringValue = value
            } else {
                // You typed one: yours is logged, and not said as found.
                values.removeValue(forKey: adif)
            }
        }
        clubNumbers = (call, values)
    }

    // Leaving SKCC number (or Callsign, with one typed): is it this
    // call's? A number that's someone else's means the call or the number
    // was miscopied, so it's a warning, said with whose number it is. It
    // can still be logged (SKCC's list may be a few days behind).
    private func checkSKCC() {
        guard let field = fieldsByName["skcc"] else { return }
        let typed = field.stringValue.trimmingCharacters(in: .whitespaces).uppercased()
        if typed != field.stringValue { field.stringValue = typed }
        let call = Callsign.normalized(callsignField.stringValue)
        guard Callsign.looksValid(call),
              let shown = SKCCRoster.shared.problem(withNumber: typed, for: call),
              let spoken = SKCCRoster.shared.problem(withNumber: typed, for: call, callText: Callsign.spoken)
        else { return }
        Speaker.Cue.warning.play()
        setLookupLine(shown)
        Speaker.announce(spoken)
    }

    // Their park (or any POTA park field on the form).
    private func isParkField(_ field: NSTextField) -> Bool {
        fieldsByName.contains { ParkSearch.fields.contains($0.key) && $0.value === field }
    }

    // MARK: - Using a spot
    //
    // Return in the Spots window: the radio goes to the spot's frequency
    // and mode, and the form gets its call and park, with focus in
    // Callsign. Add the reports and press Return to log. What was in the
    // form is cleared (Command-Z brings it back).
    func useSpot(_ spot: Spot) {
        let before = formState()
        resetForm()
        if !before.isEmpty {
            undoManager?.registerUndo(withTarget: self) { $0.unclear(before) }
            undoManager?.setActionName("Clear Form")
        }
        callsignField.stringValue = spot.call
        if !spot.reference.isEmpty {
            spotFields[spot.referenceField] = spot.reference
            fieldsByName[spot.referenceField]?.stringValue = spot.reference
        }
        let monitor = RadioMonitor.shared
        if let reading = monitor.reading {
            monitor.tune(toHertz: spot.hertz)
            if let mode = spot.radioMode, mode.uppercased() != reading.mode.uppercased() {
                monitor.change("M \(mode) 0") { _ in }
            }
        } else {
            // No radio: the spot's frequency, band and mode are logged, as
            // if typed.
            var fields = ["freq": RadioReading(hertz: spot.hertz, mode: "").megahertzText]
            if let band = spot.band { fields["band"] = band }
            if !spot.mode.isEmpty { fields["mode"] = spot.mode == "PHONE" ? "SSB" : spot.mode }
            for (adif, value) in fields {
                spotFields[adif] = value
                if let field = fieldsByName[adif] {
                    field.stringValue = value
                    typedRadioFields.insert(adif)
                }
            }
        }
        view.window?.makeKeyAndOrderFront(nil)
        focusCallsign()
        let park = spot.reference.isEmpty ? "" : spot.source == "SOTA" ? ", summit \(spot.reference)"
            : ", " + (ParkList.shared.park(spot.reference)?.spoken
            ?? [spot.reference, spot.parkName].filter { !$0.isEmpty }.joined(separator: " "))
        let tuned = monitor.reading == nil ? "" : " Tuned to \(RadioReading.trimmedMegahertz(spot.hertz)) \(spot.mode)."
        Speaker.announce("\(Callsign.spoken(spot.call))\(park).\(tuned)")
        // Looked up and checked for a dupe, as if typed.
        callsignDone()
    }

    // MARK: - Correcting a logged contact
    //
    // Up Arrow in an empty Callsign brings the newest contact into the form;
    // Up again goes to the one before, Down to the one after, and Down past
    // the newest gives an empty form again. Return saves the correction to
    // that same contact (its time, radio and station are kept); Escape
    // leaves it as it was. Command-Z undoes a correction. The log
    // highlights the contact being corrected. Fields not on the form are
    // corrected in Edit Contact.

    // Up or Down in Callsign. Returns false (so the key does what it
    // usually does) when there's a new contact being typed.
    private func stepThroughLog(older: Bool) -> Bool {
        if let id = correctingID {
            guard let index = logbook.index(of: id) else {
                resetForm()
                Speaker.announce("That contact is no longer in the log. New contact.")
                return true
            }
            if formDiffers(from: logbook.contacts[index]) {
                NSSound.beep()
                Speaker.announce("Changed. Return saves, Escape leaves it as it was.")
                return true
            }
            let next = index + (older ? -1 : 1)
            if next < 0 {
                NSSound.beep()
                Speaker.announce("Oldest contact.")
            } else if next >= logbook.contacts.count {
                resetForm()
                Speaker.announce("New contact.")
            } else {
                startCorrecting(at: next)
            }
            return true
        }
        guard older, formState().isEmpty, !logbook.contacts.isEmpty else { return false }
        startCorrecting(at: logbook.contacts.count - 1)
        return true
    }

    // Puts a logged contact in the form to correct.
    private func startCorrecting(at index: Int) {
        let qso = logbook.contacts[index]
        resetForm()
        correctingID = qso.id
        callsignField.stringValue = qso.call
        for choice in formChoices { field(for: choice.adif).stringValue = qso[choice.adif] }
        // Its radio fields are what was logged, not what the radio says now.
        typedRadioFields = RadioReading.fieldNames
        let mode = qso["submode"].isEmpty ? qso["mode"] : qso["submode"]
        let how = [qso["band"], mode].filter { !$0.isEmpty }.joined(separator: " ")
        let time = Self.spokenUTCTime.string(from: qso.timeOn) + " UTC"
        setLookupLine("Correcting \(qso.call), logged \(Self.longUTCDate.string(from: qso.timeOn)) \(time)"
            + (how.isEmpty ? "" : ", \(how)")
            + ". Return saves, Escape leaves it as it was, Up and Down go to other contacts.")
        logTable.highlight(id: qso.id)
        // Selected, so typing replaces the call (rule 3).
        callsignField.currentEditor()?.selectAll(nil)
        let spokenHow = [Self.spokenBand(qso["band"]), mode].filter { !$0.isEmpty }.joined(separator: " ")
        let parts = [Callsign.spoken(qso.call), time, spokenHow, qso["name"]].filter { !$0.isEmpty }
        Speaker.announce("Correcting " + parts.joined(separator: ", ") + ".")
    }

    // True if anything on the form differs from the contact.
    private func formDiffers(from qso: QSO) -> Bool {
        Callsign.normalized(callsignField.stringValue) != qso.call
            || formChoices.contains { field(for: $0.adif).stringValue != qso[$0.adif] }
    }

    // Return while correcting: the form's fields go into the contact.
    private func saveCorrection(_ id: UUID, call: String) {
        // The log's copy now, which a late lookup may have added to.
        guard let index = logbook.index(of: id) else {
            NSSound.beep()
            return Speaker.announce("Not saved: that contact is no longer in the log. Escape clears the form.")
        }
        let old = logbook.contacts[index]
        var updated = old
        updated.call = call
        for choice in formChoices {
            let typed = field(for: choice.adif).stringValue
            // QSO notes with line breaks (from Edit Contact) show on one line
            // here, so the field may not match them exactly. If you didn't
            // change them, keep the contact's own notes rather than lose the breaks.
            if choice.adif == "notes", typed == old.notes || typed == old.notes.replacingOccurrences(of: "\n", with: " ") {
                continue
            }
            updated[choice.adif] = typed
        }
        // The band in ADIF's terms, as when logging; one that isn't a band
        // is kept as typed rather than lost.
        for adif in ["band", "band_rx"] {
            if let band = Bands.normalized(updated[adif]) { updated[adif] = band }
        }
        // A new call: the old one's lookup details go, except ones on the
        // form (you may have typed them), and the new call is looked up.
        let callChanged = call != old.call
        if callChanged {
            let onForm = Set(formChoices.map(\.adif))
            for name in LookupResult.filledFields where !onForm.contains(name) { updated[name] = "" }
            if let result = lookupResult, result.call == CallsignLookup.lookupCall(for: call) {
                for (field, value) in result.fields where updated[field].isEmpty { updated[field] = value }
            }
            Self.addDistance(to: &updated)
        }
        guard updated != old else {
            resetForm()
            focusCallsign()
            return Speaker.announce("No changes. New contact.")
        }
        guard replaceContact(with: updated) else { return }
        let key = CallsignLookup.lookupCall(for: call)
        if callChanged, lookupResult?.call != key, Settings.lookupEnabled {
            awaitingLookup[key, default: []].append(id)
            startLookup(for: call)
        }
        resetForm()
        focusCallsign()
        Speaker.say(.logging, full: "Corrected \(Callsign.spoken(call)).", brief: "Corrected.", cue: .logged)
    }

    // Saves a new version of a logged contact, and teaches Undo to put the
    // old one back (and Redo the new). Returns false if it couldn't save.
    @discardableResult
    private func replaceContact(with updated: QSO) -> Bool {
        guard let index = logbook.index(of: updated.id) else {
            Speaker.announce("That contact is no longer in the log.")
            return false
        }
        let old = logbook.contacts[index]
        do {
            try logbook.update(updated)
        } catch {
            Speaker.announce("Not saved. \(error.localizedDescription)")
            NSSound.beep()
            return false
        }
        undoManager?.registerUndo(withTarget: self) { controller in
            guard controller.replaceContact(with: old) else { return }
            let what = controller.undoManager?.isUndoing == true ? "Correction undone for" : "Corrected again"
            Speaker.announce("\(what) \(Callsign.spoken(old.call)).")
        }
        undoManager?.setActionName("Correct Contact")
        return true
    }

    // MARK: - Dupes
    //
    // A dupe is a call already worked on this band and mode, where working
    // it again doesn't count: in a contest (the profile's form has Contest),
    // the same contest in the last 4 days (none runs longer); on a park
    // activation (the profile has your park), the same park and UTC day,
    // as POTA counts them. Other profiles have no dupes: the worked-before
    // line says what's needed. A dupe can still be logged.

    private static let contestWindow: TimeInterval = 4 * 24 * 60 * 60

    // "Dupe: W1AW worked on 20 meters CW at 14:32 UTC.", or nil.
    private func dupeText(for call: String) -> (shown: String, spoken: String)? {
        guard Callsign.looksValid(call) else { return nil }
        // A contest log: its contest's rule over the whole log (the log is
        // the event), from its file, or once per band and mode if it has
        // none (Contest.swift).
        if let id = logbook.info.contest {
            let contest = ContestList.named(id) ?? Contest(id: id, name: id)
            let radio = RadioMonitor.shared.reading?.fields ?? [:]
            func now(_ adif: String) -> String {
                let typed = onForm(adif) ?? ""
                return typed.isEmpty ? radio[adif] ?? "" : typed
            }
            let band = Bands.normalized(now("band")) ?? now("band")
            guard contest.dupes == .once || !band.isEmpty,
                  let dupe = contest.dupe(of: call, band: band, mode: modeNow(), in: logbook.contacts) else { return nil }
            let how = [Self.spokenBand(dupe["band"]), dupe["mode"]].filter { !$0.isEmpty }.joined(separator: " ")
            let rest = " worked on \(how) at " + Self.spokenUTCTime.string(from: dupe.timeOn) + " UTC."
            return ("Dupe: \(call)" + rest, "Dupe: \(Callsign.spoken(call))" + rest)
        }
        let inContest = formChoices.contains { $0.adif == "contest_id" }
        let park = Settings.currentProfile.station["my_pota_ref"] ?? ""
        // Everyday logging (CLAUDE.md item 5): the same call, band and mode
        // (CW, phone, data) on the same UTC day.
        guard inContest || !park.isEmpty else { return everydayDupe(call) }
        // The band and mode now: as typed on the form, or from the radio.
        let radio = RadioMonitor.shared.reading?.fields ?? [:]
        func now(_ adif: String) -> String {
            let typed = onForm(adif) ?? ""
            return (typed.isEmpty ? radio[adif] ?? "" : typed).uppercased()
        }
        let band = now("band"), group = Spot.group(of: modeNow())
        // Without a band or mode there's no telling, so no warning.
        guard !band.isEmpty, !group.isEmpty else { return nil }
        let contest = onForm("contest_id") ?? ""
        let today = Self.utcDay.string(from: Date())
        let cutoff = Date().addingTimeInterval(-Self.contestWindow)
        let dupe = logbook.contacts.last { qso in
            guard qso.call == call, qso["band"].uppercased() == band,
                  Spot.group(of: qso["mode"]) == group else { return false }
            if inContest { return qso.timeOn >= cutoff && qso["contest_id"] == contest }
            return qso["my_pota_ref"] == park && Self.utcDay.string(from: qso.timeOn) == today
        }
        guard let dupe else { return nil }
        let how = [Self.spokenBand(dupe["band"]), dupe["mode"]].filter { !$0.isEmpty }.joined(separator: " ")
        let rest = " worked on \(how) at " + Self.spokenUTCTime.string(from: dupe.timeOn) + " UTC."
        return ("Dupe: \(call)" + rest, "Dupe: \(Callsign.spoken(call))" + rest)
    }

    private func everydayDupe(_ call: String) -> (shown: String, spoken: String)? {
        let radio = RadioMonitor.shared.reading?.fields ?? [:]
        func now(_ adif: String) -> String {
            let typed = onForm(adif) ?? ""
            return typed.isEmpty ? radio[adif] ?? "" : typed
        }
        guard let band = Bands.normalized(now("band")) else { return nil }
        let group = Spot.group(of: modeNow())
        // Without a mode there's no telling, so no warning.
        guard !group.isEmpty else { return nil }
        let today = Self.utcDay.string(from: Date())
        guard let dupe = logbook.contacts.last(where: { qso in
            qso.call == call && qso["band"].caseInsensitiveCompare(band) == .orderedSame
                && Spot.group(of: qso["mode"]) == group
                && Self.utcDay.string(from: qso.timeOn) == today
        }) else { return nil }
        let how = [Self.spokenBand(dupe["band"]), dupe["mode"]].filter { !$0.isEmpty }.joined(separator: " ")
        let rest = " already worked today on \(how) at " + Self.spokenUTCTime.string(from: dupe.timeOn) + " UTC."
        return ("Dupe: \(call)" + rest, "Dupe: \(Callsign.spoken(call))" + rest)
    }

    // MARK: DXCC entity and "needed" (CLAUDE.md item 6)
    //
    // The call's country (DXCC entity) from cty.dat (Countries.swift), and
    // whether you need it: a new country, a new band for it, or a new mode
    // (CW, phone, data), counted from this log (WorkedCountries, as the
    // Spots window does). Said with the lookup ("Falkland Islands, needed:
    // new country"); the country goes in the contact's Country if the
    // lookup didn't give one.
    private let workedCountries = WorkedCountries()

    private func entityText(for call: String) -> (country: String, needed: String?)? {
        guard let country = Countries.shared.country(of: call) else { return nil }
        let radio = RadioMonitor.shared.reading?.fields ?? [:]
        func now(_ adif: String) -> String {
            let typed = onForm(adif) ?? ""
            return typed.isEmpty ? radio[adif] ?? "" : typed
        }
        let needed = workedCountries.needed(country: country, band: Bands.normalized(now("band")),
                                            modeGroup: Spot.group(of: modeNow()), log: logbook.contacts)
        return (country.name, needed)
    }

    // "Falkland Islands, needed: new country. " for the line, and the same
    // for speech; empty when cty.dat doesn't know the call. A needed one
    // is always said, as news; the country alone only when the lookup
    // gave no place (otherwise every US call would add "United States").
    private func entityWords(for call: String, lookupPlace: String) -> (shown: String, spoken: String) {
        guard let entity = entityText(for: call) else { return ("", "") }
        let needed = entity.needed.map { ", needed: \($0)" } ?? ""
        let shown = entity.country + needed + ". "
        let spoken = entity.needed != nil || lookupPlace.isEmpty ? entity.country + needed : ""
        return (shown, spoken)
    }

    // "2026-11-15", the UTC day, for POTA's one-contact-a-day rule.
    private static let utcDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    // MARK: - Callsign lookup

    // Shows a line under the form, or hides the line when there's nothing
    // to say. Hidden, it isn't something VoiceOver can land on and hear
    // nothing (the accessibility audit flagged the empty line). It keeps
    // its space, so the log doesn't jump up and down.
    private func setLookupLine(_ text: String) {
        lookupLabel.stringValue = text
        lookupLabel.isHidden = text.isEmpty
    }

    // A contact logged elsewhere (from WSJT-X) gets the lookup's details
    // too, quietly: the form and what it shows aren't touched.
    func lookUpQuietly(_ call: String, forContact id: UUID) {
        guard Settings.lookupEnabled, Callsign.looksValid(call) else { return }
        let key = CallsignLookup.lookupCall(for: call)
        Task { @MainActor [weak self] in
            if case .found(let result) = await CallsignLookup.shared.lookUp(key) {
                self?.addLookup(result, toContact: id)
            }
        }
    }

    // Returns true if a lookup started (its answer will be spoken).
    @discardableResult
    private func startLookup(for call: String) -> Bool {
        guard Settings.lookupEnabled, Callsign.looksValid(call) else { return false }
        let key = CallsignLookup.lookupCall(for: call)
        // Already looked up, or being looked up.
        guard key != lookupResult?.call, !lookupsUnderWay.contains(key) else { return false }
        lookupsUnderWay.insert(key)
        lookupResult = nil
        setLookupLine("Looking up \(call)…")
        Task { @MainActor [weak self] in
            let outcome = await CallsignLookup.shared.lookUp(key)
            self?.lookupFinished(key, outcome)
        }
        return true
    }

    private func lookupFinished(_ key: String, _ outcome: CallsignLookup.Outcome) {
        lookupsUnderWay.remove(key)

        // Contacts already logged for this call get the details now.
        if let waiting = awaitingLookup.removeValue(forKey: key), case .found(let result) = outcome {
            for id in waiting { addLookup(result, toContact: id) }
        }

        // Only show and speak it if the form still has this call.
        let formCall = Callsign.normalized(callsignField.stringValue)
        guard !formCall.isEmpty, CallsignLookup.lookupCall(for: formCall) == key else { return }
        let spokenCall = Callsign.spoken(formCall)
        // A dupe goes first, on the line and in what's said.
        let dupe = dupeWarning.map { $0.shown + " " } ?? ""
        switch outcome {
        case .found(let result):
            lookupResult = result
            // Fill any empty field on the form that the lookup has an answer
            // for (Name, and Grid, State and so on if you've added them).
            for choice in formChoices {
                let field = field(for: choice.adif)
                if field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty,
                   let value = result.fields[choice.adif] {
                    field.stringValue = value
                }
            }
            let worked = workedBeforeText(for: formCall)
            let path = pathText(result)
            let entity = entityWords(for: formCall, lookupPlace: result.place)
            setLookupLine(dupe + "\(formCall): \(result.summary) \(entity.shown)\(path.shown)\(clubsShown(formCall))"
                          + "\(worked)." + findHint(for: formCall))
            let speech = [spokenCall, result.firstName, result.place.replacingOccurrences(of: ",", with: ""),
                          entity.spoken, path.spoken, clubsSpoken(formCall)]
                .filter { !$0.isEmpty }.joined(separator: ", ")
            // Needed is news: said at the brief level too.
            let neededBrief = entityText(for: formCall)?.needed.map { ", needed: \($0)" } ?? ""
            sayLookup(key, full: "\(speech). \(worked).",
                      brief: (result.firstName.isEmpty ? spokenCall : result.firstName) + neededBrief, cue: .found)
        case .notFound:
            let worked = workedBeforeText(for: formCall)
            let entity = entityWords(for: formCall, lookupPlace: "")
            setLookupLine(dupe + "\(formCall): not found. \(entity.shown)\(clubsShown(formCall))\(worked)."
                          + findHint(for: formCall))
            let clubs = clubsSpoken(formCall)
            let place = entity.spoken.isEmpty ? "" : entity.spoken + ". "
            sayLookup(key, full: "\(spokenCall), not found. \(place)\(clubs.isEmpty ? "" : clubs + ". ")\(worked).",
                      brief: "Not found." + (entityText(for: formCall)?.needed.map { " Needed: \($0)." } ?? ""),
                      cue: .notFound)
        case .failed(let message):
            if sayWhenLookedUp == key { sayWhenLookedUp = nil }
            setLookupLine(dupe + "\(formCall): lookup didn't work. \(message)")
            if !dupe.isEmpty { Alert.dupe.play() }
            Speaker.announce((dupeWarning.map { $0.spoken + " " } ?? "") + "Lookup didn't work. \(message)")
        }
    }

    // ADIF's DISTANCE (whole kilometres), from your grid to theirs, if
    // both are known and it isn't set already (GreatCircle.swift).
    static func addDistance(to qso: inout QSO) {
        guard qso["distance"].isEmpty, let path = GreatCircle.path(for: qso) else { return }
        qso["distance"] = String(Int(path.km.rounded()))
    }

    // The call in the form and the bearing to it, for Turn Rotor to
    // Station: from the profile's grid to what its lookup found. Nil if
    // there's no call, no lookup for it yet, or no position to aim at.
    func stationBearing() -> (call: String, bearing: Double)? {
        let call = Callsign.normalized(callsignField.stringValue)
        let myGrid = Settings.currentProfile.station["my_gridsquare"] ?? ""
        guard !call.isEmpty, let result = lookupResult, result.call == CallsignLookup.lookupCall(for: call),
              let path = GreatCircle.path(myGrid: myGrid, fields: result.fields) else { return nil }
        return (call, path.bearing)
    }

    // How far and which way, for the lookup line and speech, from the
    // profile's grid to what the lookup found; empty if either is unknown.
    private func pathText(_ result: LookupResult) -> (shown: String, spoken: String) {
        let myGrid = Settings.currentProfile.station["my_gridsquare"] ?? ""
        guard let path = GreatCircle.path(myGrid: myGrid, fields: result.fields) else { return ("", "") }
        return (GreatCircle.shown(km: path.km, bearing: path.bearing) + ". ",
                GreatCircle.spoken(km: path.km, bearing: path.bearing))
    }

    // The call's club numbers for the lookup line ("SKCC 12345T. ") and
    // speech ("SKCC 12345 Tribune"), or empty.
    // A park the call is spotted at comes after them (fillParkFromSpots).
    private func clubsShown(_ call: String) -> String {
        let park = spottedParkText(call).shown
        guard let clubs = clubNumbers, clubs.call == call, !clubs.values.isEmpty else { return park }
        return ClubNumbers.shown(clubs.values) + ". " + park
    }

    private func clubsSpoken(_ call: String) -> String {
        let park = spottedParkText(call).spoken
        guard let clubs = clubNumbers, clubs.call == call else { return park }
        return [ClubNumbers.spoken(clubs.values), park].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    // Says a lookup at the level chosen for lookups, or in full if
    // Option-Command-N asked for it, and keeps it for Option-Command-N.
    private func sayLookup(_ key: String, full: String, brief: String, cue: Speaker.Cue) {
        lastLookupSpeech = (key, full)
        // A dupe is a warning: always said, first, with the lookup at its
        // chosen level after it.
        if let dupe = dupeWarning?.spoken {
            Alert.dupe.play()
            let level = sayWhenLookedUp == key ? .full : Speaker.level(for: .lookup)
            sayWhenLookedUp = nil
            switch level {
            case .full: Speaker.announce(dupe + " " + full)
            case .brief: Speaker.announce(dupe + " " + brief)
            case .sound, .off: Speaker.announce(dupe)
            }
            return
        }
        let needed = entityText(for: Callsign.normalized(callsignField.stringValue))?.needed != nil
        if sayWhenLookedUp == key {
            sayWhenLookedUp = nil
            if needed { Alert.needed.play() }
            Speaker.announce(full)
        } else {
            sayLookupSpeech(full: full, brief: brief, cue: cue, needed: needed)
        }
    }

    // A lookup said at its chosen level. A needed call (a new country,
    // band or mode; CLAUDE.md items 6 and 9) plays the needed sound in
    // place of the lookup's own, whatever the level, so it's heard even
    // with lookups set to a sound or nothing.
    private func sayLookupSpeech(full: String, brief: String, cue: Speaker.Cue, needed: Bool) {
        guard needed else { return Speaker.say(.lookup, full: full, brief: brief, cue: cue) }
        Alert.needed.play()
        switch Speaker.level(for: .lookup) {
        case .full: Speaker.announce(full)
        case .brief: Speaker.announce(brief)
        case .sound, .off: break
        }
    }

    // Speech > Say Name and Place (Option-Command-N): the lookup for the
    // call in the form, in full, whatever Settings > Speech says. If it
    // hasn't been looked up yet (you're still in Callsign), it's looked
    // up now and said when the answer comes.
    @objc func sayNameAndPlace(_ sender: Any?) {
        let call = Callsign.normalized(callsignField.stringValue)
        guard Callsign.looksValid(call) else {
            return Speaker.announce(call.isEmpty ? "Type a callsign first." : "Callsign not valid.")
        }
        let key = CallsignLookup.lookupCall(for: call)
        if let last = lastLookupSpeech, last.key == key { return Speaker.announce(last.text) }
        guard Settings.lookupEnabled else {
            return Speaker.announce("\(Callsign.spoken(call)): lookups are off. \(workedBeforeText(for: call)).")
        }
        sayWhenLookedUp = key
        if !lookupsUnderWay.contains(key) { startLookup(for: call) }
        Speaker.announce("Looking up \(Callsign.spoken(call)).")
    }

    // Speech > Say Last Contact (Option-Command-L): the newest contact,
    // without moving focus (Command-I goes to it).
    @objc func sayLastContact(_ sender: Any?) {
        guard let last = logbook.contacts.last else { return Speaker.announce("No contacts logged yet.") }
        let mode = last["submode"].isEmpty ? last["mode"] : last["submode"]
        let how = [Self.spokenBand(last["band"]), mode].filter { !$0.isEmpty }.joined(separator: " ")
        let parts = [Callsign.spoken(last.call), Self.spokenUTCTime.string(from: last.timeOn) + " UTC",
                     how, last["name"]].filter { !$0.isEmpty }
        Speaker.announce("Last contact: " + parts.joined(separator: ", ") + ".")
    }

    // "14:32", for saying a contact's time.
    private static let spokenUTCTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    // "New call", or "Worked 3 times before, last on 30 October 2026 on
    // 20 meters CW". Option-Command-F shows those contacts.
    private func workedBeforeText(for call: String) -> String {
        let previous = logbook.contacts.filter { $0.call == call }
        // The log is oldest first, so the last one is the most recent.
        guard let last = previous.last else { return "New call" }
        let times = previous.count == 1 ? "Worked once before" : "Worked \(previous.count) times before"
        var when = "last on \(Self.longUTCDate.string(from: last.timeOn))"
        let band = Self.spokenBand(last["band"])
        let mode = last["submode"].isEmpty ? last["mode"] : last["submode"]
        let how = [band, mode].filter { !$0.isEmpty }.joined(separator: " ")
        if !how.isEmpty { when += " on \(how)" }
        return "\(times), \(when)"
    }

    // "30 October 2026", in UTC (the log's dates are UTC). Made once.
    private static let longUTCDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    // "20m" -> "20 meters" (see Bands.spoken).
    static func spokenBand(_ band: String) -> String { Bands.spoken(band) }

    // Adds a late lookup's details to a contact already logged, filling
    // only fields that are still empty.
    private func addLookup(_ result: LookupResult, toContact id: UUID) {
        guard let index = logbook.index(of: id) else { return }
        var qso = logbook.contacts[index]
        for (field, value) in result.fields where qso[field].isEmpty {
            qso[field] = value
        }
        Self.addDistance(to: &qso)
        guard qso != logbook.contacts[index] else { return }
        _ = try? logbook.update(qso)
    }

    // Called as you type. Keeps the callsign in capitals, so what you hear
    // when reviewing the field matches what will be logged.
    func controlTextDidChange(_ notification: Notification) {
        if (notification.object as? NSTextField) === searchField { return searchChanged() }
        if let field = notification.object as? NSTextField, isParkField(field) { parkSearch.textChanged(in: field) }
        if let field = notification.object as? NSTextField, field !== callsignField {
            // Typing in a radio field: keep what you type.
            if let adif = fieldsByName.first(where: { $0.value === field })?.key,
               RadioReading.fieldNames.contains(adif) {
                typedRadioFields.insert(adif)
            }
            return
        }
        // Starting a new call: check the radio now, so the contact gets
        // its frequency even if the radio was only just switched on.
        if callsignField.stringValue.count == 1 { RadioMonitor.shared.checkNow() }
        let upper = callsignField.stringValue.uppercased()
        if upper != callsignField.stringValue {
            callsignField.stringValue = upper
        }
    }
}
