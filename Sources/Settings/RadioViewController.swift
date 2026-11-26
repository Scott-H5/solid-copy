// RadioViewController.swift
//
// Settings > Radio: your radios. One is in
// use at a time, whatever the profile; switch here, from the radio pop-up
// under the clocks, or with Control-Command-1, 2, ... (Radio menu).
//
// From top to bottom:
//   - Radio in use: a pop-up menu of your radios, and No Radio.
//   - New Radio (added and put in use, ready to set up), Delete Radio, and
//     Move Up and Move Down: the order of your radios is the order of
//     Control-Command-1, 2, ... in the Radio menu. A new radio not set up
//     (no manufacturer or port) is cancelled by Escape, which stays in this
//     section (SettingsWindowController.escape), and is taken off too when
//     Settings closes or another radio is chosen, so an abandoned New
//     Radio leaves nothing behind.
//   - The radio in use:
//     - Connect through: the built-in driver (Kenwood and Elecraft radios,
//       talked to over the USB port, with nothing else to install), or
//       "Hamlib NET rigctl": a rigctld you run yourself, at an IP address
//       and port, for any other radio.
//     - Manufacturer: Kenwood or Elecraft, for the built-in driver.
//     - Model: not chosen, but shown: the radio says which it is when it
//       connects (KenwoodClient.identify), so a TS-890 needs no menu entry
//       of its own. Until then it says so.
//     - Port: the radio's USB serial port. The list is fresh each time it
//       opens, so a radio plugged in a moment ago is there.
//     - Speed: the port's speed, which must match the radio's own setting.
//     - IP address and Network port: only for Hamlib NET rigctl, with the
//       defaults 127.0.0.1 and 4532 (rigctld's usual port).
//     - Status: what the radio is doing now, kept up to date.
//   - Share the radio with other programs: WSJT-X and others that
//     speak Hamlib NET rigctl use the radio through Solid Copy, as "Hamlib NET rigctl" at 127.0.0.1
//     port 4532 (RigctlServer.swift), while the built-in driver is in use.
//     Its note says how to set those programs up.
//
// Every change is saved at once, and Solid Copy reconnects with it.

import AppKit

@MainActor
final class RadioViewController: NSViewController, NSTextFieldDelegate, NSMenuDelegate {

    var onEscape: (() -> Void)?

    private let radioMenu = NSPopUpButton()
    private let deleteButton = NSButton(title: "Delete Radio", target: nil, action: nil)
    private let upButton = NSButton(title: "Move Up", target: nil, action: nil)
    private let downButton = NSButton(title: "Move Down", target: nil, action: nil)
    private let heading = NSTextField(labelWithString: "")
    private let connectionMenu = NSPopUpButton()
    private let makerMenu = NSPopUpButton()
    // What the radio said it is ("TS-890S"), selectable so it can be read
    // again and copied.
    private let modelLabel = NSTextField(labelWithString: "")
    private let portMenu = NSPopUpButton()
    private let speedMenu = NSPopUpButton()
    private let ipField = NSTextField(string: "")
    private let netPortField = NSTextField(string: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let shareBox = NSButton(checkboxWithTitle: "Share the radio with other programs", target: nil, action: nil)
    private let transmitBox = NSButton(checkboxWithTitle: "Let them transmit", target: nil, action: nil)
    // A frequency typed in Callsign sets the usual mode (Settings.typedFrequencyMode).
    private let modeBox = NSButton(checkboxWithTitle: "A frequency typed in Callsign sets the usual mode there",
                                   target: nil, action: nil)
    // The rotor (RotorControl.swift): through a rotctld you run.
    private let rotorBox = NSButton(checkboxWithTitle: "Use a rotor through rotctld", target: nil, action: nil)
    private let rotorAddress = NSTextField(string: "")
    private var details: NSStackView!
    private var grid: NSGridView!

    // The radio shown, to tell when another is chosen elsewhere.
    private var shownID: UUID?
    // A radio added with New Radio and not yet set up, and the one in use
    // before it, to go back to if it's abandoned (dropUnfinished).
    private var unfinished: (id: UUID, previous: UUID?)?

    var firstControl: NSView { radioMenu }

    override func loadView() {
        radioMenu.setAccessibilityLabel("Radio in use")
        radioMenu.target = self
        radioMenu.action = #selector(chooseRadio(_:))
        let newButton = NSButton(title: "New Radio", target: self, action: #selector(newRadio(_:)))
        deleteButton.target = self
        deleteButton.action = #selector(deleteRadio(_:))
        upButton.target = self
        upButton.action = #selector(moveRadioUp(_:))
        downButton.target = self
        downButton.action = #selector(moveRadioDown(_:))
        let buttons = NSStackView(views: [newButton, deleteButton, upButton, downButton])
        buttons.spacing = 8
        let top = NSGridView(views: [[FieldLabel("Radio in use"), radioMenu]])
        top.rowAlignment = .firstBaseline

        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        connectionMenu.addItems(withTitles: ["Built-in driver (Kenwood and Elecraft)", "Hamlib NET rigctl"])
        speedMenu.addItems(withTitles: RadioSettings.speeds.map { "\($0) baud" })
        // The port list is made fresh each time it opens (menuNeedsUpdate).
        portMenu.menu?.delegate = self
        // Defaults shown until typed over: this Mac, rigctld's usual port.
        ipField.placeholderString = "127.0.0.1"
        netPortField.placeholderString = "4532"
        for field in [ipField, netPortField] {
            field.delegate = self
            field.widthAnchor.constraint(equalToConstant: 160).isActive = true
        }

        let controls: [(String, NSView)] = [("Connect through", connectionMenu), ("Manufacturer", makerMenu),
                                            ("Model", modelLabel), ("Port", portMenu), ("Speed", speedMenu),
                                            ("IP address", ipField), ("Network port", netPortField)]
        for (label, control) in controls {
            control.setAccessibilityLabel(label)
            if let menu = control as? NSPopUpButton {
                menu.target = self
                menu.action = #selector(changed(_:))
            }
        }
        modelLabel.isSelectable = true
        grid = NSGridView(views: controls.map { [FieldLabel($0.0), $0.1] })
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.rowAlignment = .firstBaseline
        statusLabel.preferredMaxLayoutWidth = 520
        details = NSStackView(views: [heading, grid, statusLabel])
        details.orientation = .vertical
        details.alignment = .leading
        details.spacing = 12

        let note = NSTextField(wrappingLabelWithString:
            "Frequency, band, mode and power come from the radio in use, for any of those you don't type "
            + "yourself. Solid Copy keeps trying to reach it for as long as it's open, so the radio can be "
            + "switched on before or after it.")
        note.preferredMaxLayoutWidth = 520

        shareBox.target = self
        shareBox.action = #selector(toggleSharing(_:))
        // Instructions are a note you can read again and copy (contract
        // rule 40), linked to the checkbox (VO-Command-J).
        let shareNote = NSTextField(wrappingLabelWithString:
            "With this on, programs that can use Hamlib NET rigctl, such as WSJT-X, can use the "
            + "radio through Solid Copy while you log, with no rigctld to run. In the other program, choose "
            + "the radio Hamlib NET rigctl, network "
            + "server 127.0.0.1, port 4532. They can tune the radio and change its mode. It works with the "
            + "built-in driver; with Hamlib NET rigctl, your own rigctld shares the radio instead.")
        shareNote.preferredMaxLayoutWidth = 520
        shareNote.isSelectable = true
        shareBox.setAccessibilityLinkedUIElements([shareNote])

        // Transmit (PTT) is its own choice, off until turned on, with its own
        // note on the safeguards.
        transmitBox.target = self
        transmitBox.action = #selector(toggleTransmit(_:))
        let transmitNote = NSTextField(wrappingLabelWithString:
            "With this on too, those programs can key the radio through Solid Copy (on the TS-590, from "
            + "its data input: the USB audio they play). Solid Copy puts the radio back to receive if the "
            + "program goes, if sharing is turned off or the radio changed, when Solid Copy quits, and "
            + "after 5 minutes of one transmission. A program's first transmission is said. Set the "
            + "program's PTT to CAT. Try it into a dummy load first.")
        transmitNote.preferredMaxLayoutWidth = 520
        transmitNote.isSelectable = true
        transmitBox.setAccessibilityLinkedUIElements([transmitNote])

        rotorBox.target = self
        rotorBox.action = #selector(toggleRotor(_:))
        let rotorNote = NSTextField(wrappingLabelWithString:
            "Turns the antenna from the Radio menu: Turn Rotor to Station (Control-Shift-Command-T), Long "
            + "Path (L), Turn Rotor To a heading (E), Rotor Heading (H) and Stop Rotor (S). Run hamlib's "
            + "rotctld for your rotor first, for example: rotctld -m 1 for a pretend rotor to try it, or "
            + "rotctld -m <your model> -r <its port>. The address is where rotctld listens: empty means "
            + "this Mac, 127.0.0.1 port 4533. The rotor only turns when you choose one of those commands.")
        rotorNote.preferredMaxLayoutWidth = 520
        rotorNote.isSelectable = true
        rotorBox.setAccessibilityLinkedUIElements([rotorNote])
        rotorAddress.placeholderString = "127.0.0.1:4533"
        rotorAddress.setAccessibilityLabel("Rotor's rotctld address")
        rotorAddress.setAccessibilityLinkedUIElements([rotorNote])
        rotorAddress.target = self
        rotorAddress.action = #selector(rotorAddressChanged(_:))
        rotorAddress.cell?.sendsActionOnEndEditing = true
        rotorAddress.widthAnchor.constraint(equalToConstant: 200).isActive = true
        let rotorRow = NSStackView(views: [FieldLabel("rotctld address"), rotorAddress])

        modeBox.target = self
        modeBox.action = #selector(toggleTypedMode(_:))
        let modeNote = NSTextField(wrappingLabelWithString:
            "Type a frequency in Callsign and press Return to tune (14050 or 14.050). With this on, the mode "
            + "follows the band plan (Settings > Band Plan): CW where phone isn't allowed, SSB on the usual "
            + "sideband where it is, data on FT8 and FT4 frequencies. Above 6 meters the mode is left as it is. "
            + "Type a mode as well to choose it yourself: 14.050 CW, 7.200 LSB.")
        modeNote.preferredMaxLayoutWidth = 520
        modeNote.isSelectable = true
        modeBox.setAccessibilityLinkedUIElements([modeNote])


        let stack = NSStackView(views: [top, buttons, details, note, modeBox, modeNote, shareBox, shareNote, transmitBox,
                                        transmitNote,
                                        rotorBox, rotorRow, rotorNote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(24, after: buttons)
        stack.setCustomSpacing(20, after: details)
        stack.setCustomSpacing(20, after: note)
        stack.setCustomSpacing(20, after: modeNote)
        stack.setCustomSpacing(20, after: transmitNote)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        view = stack

        // Tab order, top to bottom (the pop-ups and buttons only when
        // Keyboard navigation is on in System Settings).
        let order = [radioMenu, newButton, deleteButton] + controls.map(\.1) + [modeBox, shareBox, transmitBox,
                                                                       rotorBox, rotorAddress]
        for (index, item) in order.enumerated() {
            item.nextKeyView = order[(index + 1) % order.count]
        }

        // Settings closing (Escape, Command-W, its close button): a new radio
        // never set up is taken off.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) {
            [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let window = notification.object as? NSWindow, window === self.view.window else { return }
                self.dropUnfinished()
            }
        }
        NotificationCenter.default.addObserver(forName: RadioMonitor.didChange, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.showStatus() }
        }
        // Another radio chosen elsewhere (the main window, the Radio menu):
        // show it. Or the radio in use has said which model it is: show
        // its new name. A moment later, so a menu isn't refilled while
        // macOS is still handling a choice from it.
        NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) {
            [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let radio = Settings.currentRadio
                    if radio?.id != self.shownID {
                        self.refresh()
                    } else if let radio, self.title(of: radio) != self.heading.stringValue {
                        self.showTitles(radio)
                        self.showModel(radio)
                    }
                }
            }
        }
        refresh()
    }

    // Shows your radios and the one in use.
    @objc private func toggleTransmit(_ sender: NSButton) {
        Settings.shareRadioTransmit = sender.state == .on
        Speaker.announce(sender.state == .on
            ? "Programs sharing the radio may transmit."
            : "Programs sharing the radio can't transmit.")
    }

    @objc private func toggleRotor(_ sender: NSButton) {
        Settings.rotorEnabled = sender.state == .on
        rotorAddress.isEnabled = sender.state == .on
        RotorControl.shared.settingsChanged()
        let address = RotctldClient.address(Settings.rotorAddress)
        Speaker.announce(sender.state == .on ? "Rotor on, through rotctld at \(address.host) port \(address.port)."
                                             : "Rotor off.")
    }

    // Return or leaving the field: the new address is used from the next
    // rotor command.
    @objc private func toggleTypedMode(_ sender: NSButton) {
        Settings.typedFrequencyMode = sender.state == .on
    }

    @objc private func rotorAddressChanged(_ sender: NSTextField) {
        guard sender.stringValue.trimmingCharacters(in: .whitespaces) != Settings.rotorAddress else { return }
        Settings.rotorAddress = sender.stringValue
        RotorControl.shared.settingsChanged()
        let address = RotctldClient.address(Settings.rotorAddress)
        Speaker.announce("The rotor's rotctld is at \(address.host) port \(address.port).")
    }

    @objc private func toggleSharing(_ sender: NSButton) {
        Settings.shareRadio = sender.state == .on
        transmitBox.isEnabled = sender.state == .on
        // (Trouble, such as another program on port 4532, is said by the
        // server itself.)
        let text = sender.state == .off ? "The radio isn't shared with other programs."
            : Settings.currentRadio?.builtIn == true ? "Sharing the radio at 127.0.0.1 port 4532."
            : "Sharing starts when the radio in use connects through the built-in driver."
        Speaker.announce(text)
    }

    func refresh() {
        shareBox.state = Settings.shareRadio ? .on : .off
        transmitBox.state = Settings.shareRadioTransmit ? .on : .off
        transmitBox.isEnabled = Settings.shareRadio
        modeBox.state = Settings.typedFrequencyMode ? .on : .off
        rotorBox.state = Settings.rotorEnabled ? .on : .off
        rotorAddress.stringValue = Settings.rotorAddress
        rotorAddress.isEnabled = Settings.rotorEnabled
        let radios = Settings.radios
        let radio = Settings.currentRadio
        shownID = radio?.id
        // Items added one by one: addItems(withTitles:) drops any title
        // already there (see RadioSettings.titles).
        radioMenu.removeAllItems()
        for title in RadioSettings.titles(radios) + ["No Radio"] { radioMenu.menu?.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: "")) }
        radioMenu.selectItem(at: radios.firstIndex { $0.id == radio?.id } ?? radios.count)
        deleteButton.isEnabled = radio != nil
        let place = radios.firstIndex { $0.id == radio?.id }
        upButton.isEnabled = (place ?? 0) > 0
        downButton.isEnabled = place.map { $0 < radios.count - 1 } ?? false
        // The details only when there's a radio in use.
        details.isHidden = radio == nil
        guard let radio else { return showStatus() }

        heading.stringValue = title(of: radio)
        connectionMenu.selectItem(at: radio.builtIn ? 0 : 1)
        // The manufacturer, then the model the radio said it is.
        makerMenu.removeAllItems()
        makerMenu.addItem(withTitle: "Choose a manufacturer")
        makerMenu.addItems(withTitles: RadioModels.makers.map(\.name))
        if let maker = RadioModels.maker(of: radio.model) {
            makerMenu.selectItem(withTitle: maker)
        } else {
            makerMenu.selectItem(at: 0)
        }
        showModel(radio)
        fillPorts()
        speedMenu.selectItem(at: RadioSettings.speeds.firstIndex(of: radio.baud) ?? 3)
        // The saved address split into its two fields; the defaults show
        // when there isn't one yet.
        if radio.address.isEmpty {
            ipField.stringValue = ""
            netPortField.stringValue = ""
        } else {
            ipField.stringValue = radio.hostAndPort.host
            netPortField.stringValue = String(radio.hostAndPort.port)
        }
        showRows()
        showStatus()
    }

    // MARK: - Filling the menus

    // A radio's title in this list of radios (its name, or with its port
    // when another has the same name).
    private func title(of radio: RadioSettings) -> String {
        RadioSettings.title(of: radio, among: Settings.radios)
    }

    // The heading and the Radio in use items, after a name or port changed:
    // every item, since one radio's change can make another's title need
    // (or no longer need) its port.
    private func showTitles(_ radio: RadioSettings) {
        heading.stringValue = title(of: radio)
        for (index, title) in RadioSettings.titles(Settings.radios).enumerated() {
            radioMenu.item(at: index)?.title = title
        }
    }

    // The model, as the radio named itself ("TS-890S", the saved name
    // without its maker), or what happens until it has.
    private func showModel(_ radio: RadioSettings) {
        let maker = RadioModels.maker(of: radio.model)
        let named = RadioModels.makers.allSatisfy { $0.model != radio.model }
        if maker == nil {
            modelLabel.stringValue = "Choose a manufacturer first."
        } else if named, let maker, radio.modelName.hasPrefix(maker + " ") {
            modelLabel.stringValue = String(radio.modelName.dropFirst(maker.count + 1))
        } else if radio.modelName.hasPrefix("Kenwood (ID") {
            modelLabel.stringValue = radio.modelName + ", used with the TS-590's settings"
        } else {
            modelLabel.stringValue = "Found when the radio connects."
        }
        modelLabel.setAccessibilityValue(modelLabel.stringValue)
    }

    // The serial ports there now ("usbserial-XXXX"), plus the saved
    // one if it isn't (the radio is off), marked as such.
    private func fillPorts() {
        let saved = Settings.currentRadio?.port ?? ""
        var ports = ((try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? [])
            .filter { $0.hasPrefix("cu.") && !["cu.Bluetooth-Incoming-Port", "cu.debug-console"].contains($0) }
            .sorted()
            .map { "/dev/" + $0 }
        let savedMissing = !saved.isEmpty && !ports.contains(saved)
        if savedMissing { ports.insert(saved, at: 0) }
        portMenu.removeAllItems()
        portMenu.addItem(withTitle: "Choose a port")
        for port in ports {
            let name = port.replacingOccurrences(of: "/dev/cu.", with: "")
            portMenu.addItem(withTitle: port == saved && savedMissing ? "\(name) (not there now)" : name)
            portMenu.lastItem?.representedObject = port
        }
        portMenu.selectItem(at: ports.firstIndex(of: saved).map { $0 + 1 } ?? 0)
    }

    // Refreshes the port list just before it opens.
    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated { fillPorts() }
    }

    // Shows only the rows that apply: the IP address and network port for
    // Hamlib NET rigctl; manufacturer, model, port and speed for the others.
    private func showRows() {
        let yours = connectionMenu.indexOfSelectedItem == 1
        for row in 1...4 { grid.row(at: row).isHidden = yours }
        grid.row(at: 5).isHidden = !yours
        grid.row(at: 6).isHidden = !yours
    }

    private func showStatus() {
        let monitor = RadioMonitor.shared
        statusLabel.stringValue = monitor.state == .none ? "No radio in use." : "Now: \(monitor.stateText)"
    }

    // MARK: - Commands

    // Radio in use: switches to it (or to none).
    @objc private func chooseRadio(_ sender: Any?) {
        let radios = Settings.radios
        let index = radioMenu.indexOfSelectedItem
        let chosen = radios.indices.contains(index) ? radios[index] : nil
        // Leaving a new radio not set up takes it off (not when it's the
        // one chosen again).
        if let unfinished, chosen?.id != unfinished.id {
            self.unfinished = nil
            if let radio = radios.first(where: { $0.id == unfinished.id }), !Self.isSetUp(radio) {
                Settings.radios = radios.filter { $0.id != unfinished.id }
            }
        }
        Settings.useRadio(chosen?.id)
        refresh()
        Speaker.announce(chosen.map { "\(title(of: $0))." } ?? "No radio.")
    }

    // A new radio, put in use, with focus on its manufacturer. It starts
    // on the built-in driver, the first choice in Connect through, so the
    // Manufacturer menu that gets focus is shown. (Made as RadioSettings'
    // own default, Hamlib NET rigctl, it hid that menu with focus in it,
    // so VoiceOver lost its place; found 26 November 2026.)
    @objc private func newRadio(_ sender: Any?) {
        dropUnfinished(saying: false)
        let previous = Settings.currentRadio?.id
        let radio = RadioSettings(model: 0, modelName: "", builtIn: true)
        Settings.currentRadio = radio
        unfinished = (radio.id, previous)
        refresh()
        view.window?.makeFirstResponder(makerMenu)
        Speaker.announce("New radio. Choose its manufacturer and port. Solid Copy finds the model when it connects. "
            + "Escape cancels it and stays here.")
    }

    // Escape in Settings > Radio: a new radio not set up yet is cancelled,
    // and focus goes to Radio in use, showing the radio back in use.
    // Returns false when there's nothing to cancel (Escape then closes
    // Settings).
    func cancelNewRadio() -> Bool {
        guard let unfinished, let radio = Settings.radios.first(where: { $0.id == unfinished.id }),
              !Self.isSetUp(radio) else { return false }
        dropUnfinished()
        view.window?.makeFirstResponder(radioMenu)
        return true
    }

    // Set up enough to keep: the built-in driver with a manufacturer and a
    // port, or Hamlib NET rigctl (chosen on purpose, as a new radio starts
    // on the built-in driver).
    private static func isSetUp(_ radio: RadioSettings) -> Bool {
        !radio.builtIn || radio.isComplete
    }

    // A new radio abandoned before it was set up: taken off, and the radio
    // in use before it is used again. Said, unless New Radio is pressed
    // again (which says its own).
    func dropUnfinished(saying: Bool = true) {
        guard let unfinished else { return }
        self.unfinished = nil
        let radios = Settings.radios
        guard let radio = radios.first(where: { $0.id == unfinished.id }), !Self.isSetUp(radio) else { return }
        let remaining = radios.filter { $0.id != unfinished.id }
        Settings.radios = remaining
        let back = remaining.first { $0.id == unfinished.previous }
        Settings.useRadio(back?.id)
        if view.window?.isVisible == true { refresh() }
        guard saying else { return }
        Speaker.announce("New radio cancelled. "
            + (back.map { "Using \(RadioSettings.title(of: $0, among: remaining))." } ?? "No radio."))
    }

    // Move Up and Move Down: the radio in use one place earlier or later
    // in your list, and so in Control-Command-1, 2, ... (Radio menu).
    @objc private func moveRadioUp(_ sender: Any?) { move(by: -1) }
    @objc private func moveRadioDown(_ sender: Any?) { move(by: 1) }

    private func move(by step: Int) {
        var radios = Settings.radios
        guard let radio = Settings.currentRadio, let index = radios.firstIndex(where: { $0.id == radio.id }),
              radios.indices.contains(index + step) else { return }
        radios.swapAt(index, index + step)
        Settings.radios = radios
        refresh()
        // Focus stays on the button pressed, unless it can't be pressed
        // again (top or bottom): then on the other one.
        let pressed = step < 0 ? upButton : downButton
        if !pressed.isEnabled { view.window?.makeFirstResponder(step < 0 ? downButton : upButton) }
        let place = index + step + 1
        let title = RadioSettings.title(of: radio, among: radios)
        Speaker.announce("\(title) is now \(Self.ordinal(place)) of \(radios.count)"
            + (place <= 9 ? ", Control-Command-\(place)." : "."))
    }

    private static func ordinal(_ number: Int) -> String {
        let words = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth"]
        return words.indices.contains(number - 1) ? words[number - 1] : "number \(number)"
    }

    // Deletes the radio in use, after asking (there's no Undo here).
    @objc private func deleteRadio(_ sender: Any?) {
        guard let radio = Settings.currentRadio, let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Delete \(title(of: radio))?"
        alert.informativeText = "Its settings will be gone. Contacts already logged with it aren't changed."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let remaining = Settings.radios.filter { $0.id != radio.id }
            Settings.radios = remaining
            Settings.useRadio(remaining.first?.id)
            self?.refresh()
            Speaker.announce("Deleted. " + (remaining.first.map { "Now using \(RadioSettings.title(of: $0, among: remaining))." } ?? "No radio."))
        }
    }

    // MARK: - Saving

    @objc private func changed(_ sender: NSPopUpButton) {
        save()
        // The built-in driver offers fewer radios, so the lists are made
        // again (refresh also shows the rows that apply).
        if sender === connectionMenu { refresh() }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        save()
    }

    // Saves what the controls show to the radio in use. The radio monitor
    // reconnects when Settings say it changed.
    private func save() {
        guard var radio = Settings.currentRadio else { return }
        let choice = connectionMenu.indexOfSelectedItem
        radio.builtIn = choice == 0
        if choice == 1 {
            // Hamlib NET rigctl: its IP address and port are all that's
            // needed (the rest is kept, for if you switch back). Empty
            // fields mean the defaults. A bad port is refused in plain
            // words and the saved one shown again.
            let host = ipField.stringValue.trimmingCharacters(in: .whitespaces)
            let portText = netPortField.stringValue.trimmingCharacters(in: .whitespaces)
            let savedHost = radio.hostAndPort
            guard !host.contains(":") else {
                Speaker.announce("An IP address like 127.0.0.1, without a port. The port goes in Network port.")
                ipField.stringValue = savedHost.host
                return
            }
            guard let port = portText.isEmpty ? 4532 : UInt16(portText), port > 0 else {
                Speaker.announce("Network port must be a number from 1 to 65535.")
                netPortField.stringValue = String(savedHost.port)
                return
            }
            radio.address = "\(host.isEmpty ? "127.0.0.1" : host):\(port)"
            ipField.stringValue = host.isEmpty ? "127.0.0.1" : host
            netPortField.stringValue = String(port)
        } else {
            radio.address = ""
            // Another manufacturer: its own model until the radio says which
            // it is. The same one keeps the model the radio named.
            if let maker = RadioModels.makers.first(where: { $0.name == makerMenu.titleOfSelectedItem }),
               RadioModels.maker(of: radio.model) != maker.name {
                radio.model = maker.model
                radio.modelName = maker.name
            }
            radio.port = portMenu.selectedItem?.representedObject as? String ?? ""
            radio.baud = RadioSettings.speeds[max(0, speedMenu.indexOfSelectedItem)]
        }
        guard radio != Settings.currentRadio else { return }
        Settings.currentRadio = radio
        if unfinished?.id == radio.id, Self.isSetUp(radio) { unfinished = nil }
        // A new name (a manufacturer chosen) or port: the list and heading
        // show it.
        showTitles(radio)
        showModel(radio)
    }

    // Escape closes Settings from the address field too.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        view.window?.makeFirstResponder(nil)
        onEscape?()
        return true
    }
}
