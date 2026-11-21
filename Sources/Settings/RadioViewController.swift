// RadioViewController.swift
//
// Settings > Radio: your radios. One is in
// use at a time, whatever the profile; switch here, from the radio pop-up
// under the clocks, or with Control-Command-1, 2, ... (Radio menu).
//
// From top to bottom:
//   - Radio in use: a pop-up menu of your radios, and No Radio.
//   - New Radio (added and put in use, ready to set up) and Delete Radio.
//   - The radio in use:
//     - Connect through: the built-in driver (Kenwood and Elecraft radios,
//       talked to over the USB port, with nothing else to install), or
//       "Hamlib NET rigctl": a rigctld you run yourself, at an IP address
//       and port, for any other radio. The built-in driver offers only the
//       Kenwood and Elecraft radios it knows.
//     - Manufacturer and Model: the built-in driver's radios, in two menus.
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
    private let heading = NSTextField(labelWithString: "")
    private let connectionMenu = NSPopUpButton()
    private let makerMenu = NSPopUpButton()
    private let modelMenu = NSPopUpButton()
    private let portMenu = NSPopUpButton()
    private let speedMenu = NSPopUpButton()
    private let ipField = NSTextField(string: "")
    private let netPortField = NSTextField(string: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let shareBox = NSButton(checkboxWithTitle: "Share the radio with other programs", target: nil, action: nil)
    private let transmitBox = NSButton(checkboxWithTitle: "Let them transmit", target: nil, action: nil)
    private var details: NSStackView!
    private var grid: NSGridView!

    // The radio shown, to tell when another is chosen elsewhere.
    private var shownID: UUID?

    var firstControl: NSView { radioMenu }

    override func loadView() {
        radioMenu.setAccessibilityLabel("Radio in use")
        radioMenu.target = self
        radioMenu.action = #selector(chooseRadio(_:))
        let newButton = NSButton(title: "New Radio", target: self, action: #selector(newRadio(_:)))
        deleteButton.target = self
        deleteButton.action = #selector(deleteRadio(_:))
        let buttons = NSStackView(views: [newButton, deleteButton])
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
                                            ("Model", modelMenu), ("Port", portMenu), ("Speed", speedMenu),
                                            ("IP address", ipField), ("Network port", netPortField)]
        for (label, control) in controls {
            control.setAccessibilityLabel(label)
            if let menu = control as? NSPopUpButton {
                menu.target = self
                menu.action = #selector(changed(_:))
            }
        }
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

        let stack = NSStackView(views: [top, buttons, details, note, shareBox, shareNote, transmitBox,
                                        transmitNote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(24, after: buttons)
        stack.setCustomSpacing(20, after: details)
        stack.setCustomSpacing(20, after: note)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        view = stack

        // Tab order, top to bottom (the pop-ups and buttons only when
        // Keyboard navigation is on in System Settings).
        let order = [radioMenu, newButton, deleteButton] + controls.map(\.1) + [shareBox, transmitBox]
        for (index, item) in order.enumerated() {
            item.nextKeyView = order[(index + 1) % order.count]
        }

        NotificationCenter.default.addObserver(forName: RadioMonitor.didChange, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.showStatus() }
        }
        // Another radio chosen elsewhere (the main window, the Radio menu):
        // show it. A moment later, so a menu isn't refilled while macOS is
        // still handling a choice from it.
        NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) {
            [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let self, Settings.currentRadio?.id != self.shownID { self.refresh() }
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
        let radios = Settings.radios
        let radio = Settings.currentRadio
        shownID = radio?.id
        radioMenu.removeAllItems()
        radioMenu.addItems(withTitles: radios.map(\.name) + ["No Radio"])
        radioMenu.selectItem(at: radios.firstIndex { $0.id == radio?.id } ?? radios.count)
        deleteButton.isEnabled = radio != nil
        // The details only when there's a radio in use.
        details.isHidden = radio == nil
        guard let radio else { return showStatus() }

        heading.stringValue = radio.name
        connectionMenu.selectItem(at: radio.builtIn ? 0 : 1)
        // Manufacturers, then the chosen one's models.
        makerMenu.removeAllItems()
        makerMenu.addItem(withTitle: "Choose a manufacturer")
        makerMenu.addItems(withTitles: Self.unique(offeredModels.map(\.maker)))
        let model = offeredModels.first { $0.number == radio.model }
        if let model { makerMenu.selectItem(withTitle: model.maker) } else { makerMenu.selectItem(at: 0) }
        fillModels(selecting: model?.number)
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

    // The radios offered: the built-in driver's (KenwoodRadio). Hamlib NET
    // rigctl doesn't pick a model here; its rigctld is set up separately.
    private var offeredModels: [RadioModels.Model] { RadioModels.builtIn }

    // The chosen manufacturer's models, after "Choose a model" (so choosing
    // a manufacturer doesn't pick one of its radios for you).
    private func fillModels(selecting number: Int?) {
        modelMenu.removeAllItems()
        modelMenu.addItem(withTitle: "Choose a model")
        let maker = makerMenu.titleOfSelectedItem ?? ""
        for model in offeredModels where model.maker == maker {
            modelMenu.addItem(withTitle: model.name)
            modelMenu.lastItem?.tag = model.number
        }
        if let number, modelMenu.indexOfItem(withTag: number) >= 0 {
            modelMenu.selectItem(withTag: number)
        } else {
            modelMenu.selectItem(at: 0)
        }
        modelMenu.isEnabled = makerMenu.indexOfSelectedItem > 0
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
        Settings.useRadio(chosen?.id)
        refresh()
        Speaker.announce(chosen.map { "\($0.name)." } ?? "No radio.")
    }

    // A new radio, put in use, with focus on its manufacturer.
    @objc private func newRadio(_ sender: Any?) {
        Settings.currentRadio = RadioSettings(model: 0, modelName: "")
        refresh()
        view.window?.makeFirstResponder(makerMenu)
        Speaker.announce("New radio. Choose its manufacturer, model and port.")
    }

    // Deletes the radio in use, after asking (there's no Undo here).
    @objc private func deleteRadio(_ sender: Any?) {
        guard let radio = Settings.currentRadio, let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Delete \(radio.name)?"
        alert.informativeText = "Its settings will be gone. Contacts already logged with it aren't changed."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let remaining = Settings.radios.filter { $0.id != radio.id }
            Settings.radios = remaining
            Settings.useRadio(remaining.first?.id)
            self?.refresh()
            Speaker.announce("Deleted. " + (remaining.first.map { "Now using \($0.name)." } ?? "No radio."))
        }
    }

    // MARK: - Saving

    @objc private func changed(_ sender: NSPopUpButton) {
        if sender === makerMenu { fillModels(selecting: nil) }
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
            // A manufacturer but no model yet: keep the old model until
            // one is chosen.
            if let model = offeredModels.first(where: { $0.number == modelMenu.selectedItem?.tag }),
               modelMenu.indexOfSelectedItem > 0 {
                radio.model = model.number
                radio.modelName = "\(model.maker) \(model.name)"
            }
            radio.port = portMenu.selectedItem?.representedObject as? String ?? ""
            radio.baud = RadioSettings.speeds[max(0, speedMenu.indexOfSelectedItem)]
        }
        guard radio != Settings.currentRadio else { return }
        let renamed = radio.name != Settings.currentRadio?.name
        Settings.currentRadio = radio
        // A new name (a model chosen): the list and heading show it.
        if renamed {
            heading.stringValue = radio.name
            let index = radioMenu.indexOfSelectedItem
            radioMenu.item(at: index)?.title = radio.name
        }
    }

    private static func unique(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        return names.filter { seen.insert($0).inserted }
    }

    // Escape closes Settings from the address field too.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        view.window?.makeFirstResponder(nil)
        onEscape?()
        return true
    }
}
