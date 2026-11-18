// RadioViewController.swift
//
// Settings > Radio: your radios, read through hamlib's rigctld. One is in
// use at a time, whatever the profile; switch here, from the radio pop-up
// under the clocks, or with Control-Command-1, 2, ... (Radio menu).
//
// From top to bottom:
//   - Radio in use: a pop-up menu of your radios, and No Radio.
//   - New Radio (added and put in use, ready to set up) and Delete Radio.
//   - The radio in use:
//     - Connect through: Solid Copy's own rigctld (the usual way: Solid
//       Copy starts it, and starts it again whenever it needs to), or a
//       rigctld you run yourself, at an address.
//     - Manufacturer and Model: two pop-up menus rather than one long
//       one, since hamlib knows hundreds of radios.
//     - Port: the radio's USB serial port. The list is fresh each time it
//       opens, so a radio plugged in a moment ago is there.
//     - Speed: the port's speed, which must match the radio's own setting.
//     - Address: only for a rigctld you run yourself ("127.0.0.1:4532").
//     - Status: what the radio is doing now, kept up to date.
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
    private let addressField = NSTextField(string: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var details: NSStackView!
    private var grid: NSGridView!

    // hamlib's radios, once loaded (see RadioModels).
    private var models: [RadioModels.Model] = []
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
        connectionMenu.addItems(withTitles: ["Solid Copy's own rigctld", "A rigctld you run yourself"])
        speedMenu.addItems(withTitles: RadioSettings.speeds.map { "\($0) baud" })
        // The port list is made fresh each time it opens (menuNeedsUpdate).
        portMenu.menu?.delegate = self
        addressField.placeholderString = "127.0.0.1:4532"
        addressField.delegate = self
        addressField.widthAnchor.constraint(equalToConstant: 260).isActive = true

        let controls: [(String, NSView)] = [("Connect through", connectionMenu), ("Manufacturer", makerMenu),
                                            ("Model", modelMenu), ("Port", portMenu), ("Speed", speedMenu),
                                            ("Address", addressField)]
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

        let stack = NSStackView(views: [top, buttons, details, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(24, after: buttons)
        stack.setCustomSpacing(20, after: details)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        view = stack

        // Tab order, top to bottom (the pop-ups and buttons only when
        // Keyboard navigation is on in System Settings).
        let order = [radioMenu, newButton, deleteButton] + controls.map(\.1)
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
        Task { [weak self] in
            let models = await RadioModels.load()
            self?.models = models
            self?.refresh()
        }
        refresh()
    }

    // Shows your radios and the one in use.
    func refresh() {
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
        connectionMenu.selectItem(at: radio.usesOwnRigctld ? 0 : 1)
        // Manufacturers, then the chosen one's models.
        makerMenu.removeAllItems()
        makerMenu.addItem(withTitle: "Choose a manufacturer")
        makerMenu.addItems(withTitles: Self.unique(models.map(\.maker)))
        let model = models.first { $0.number == radio.model }
        if let model { makerMenu.selectItem(withTitle: model.maker) } else { makerMenu.selectItem(at: 0) }
        fillModels(selecting: model?.number)
        fillPorts()
        speedMenu.selectItem(at: RadioSettings.speeds.firstIndex(of: radio.baud) ?? 3)
        addressField.stringValue = radio.address
        showRows()
        showStatus()
    }

    // MARK: - Filling the menus

    // The chosen manufacturer's models, after "Choose a model" (so choosing
    // a manufacturer doesn't pick one of its radios for you).
    private func fillModels(selecting number: Int?) {
        modelMenu.removeAllItems()
        modelMenu.addItem(withTitle: "Choose a model")
        let maker = makerMenu.titleOfSelectedItem ?? ""
        for model in models where model.maker == maker {
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

    // The serial ports there now ("usbserial-0567003F3CA0"), plus the saved
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

    // Shows only the rows that apply: the address for your own rigctld;
    // manufacturer, model, port and speed for Solid Copy's.
    private func showRows() {
        let own = connectionMenu.indexOfSelectedItem == 0
        for row in 1...4 { grid.row(at: row).isHidden = !own }
        grid.row(at: 5).isHidden = own
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
        if sender === connectionMenu { showRows() }
        save()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        save()
    }

    // Saves what the controls show to the radio in use. The radio monitor
    // reconnects when Settings say it changed.
    private func save() {
        guard var radio = Settings.currentRadio else { return }
        if connectionMenu.indexOfSelectedItem == 0 {
            radio.address = ""
            // A manufacturer but no model yet: keep the old model until
            // one is chosen.
            if let model = models.first(where: { $0.number == modelMenu.selectedItem?.tag }),
               modelMenu.indexOfSelectedItem > 0 {
                radio.model = model.number
                radio.modelName = "\(model.maker) \(model.name)"
            }
            radio.port = portMenu.selectedItem?.representedObject as? String ?? ""
            radio.baud = RadioSettings.speeds[max(0, speedMenu.indexOfSelectedItem)]
        } else {
            // A rigctld of your own: its address is all that's needed (the
            // rest is kept, for if you switch back).
            let address = addressField.stringValue.trimmingCharacters(in: .whitespaces)
            radio.address = address.isEmpty ? "127.0.0.1:4532" : address
            addressField.stringValue = radio.address
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
