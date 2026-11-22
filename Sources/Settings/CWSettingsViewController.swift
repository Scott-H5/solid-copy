// CWSettingsViewController.swift
//
// Settings > CW (the 11th section): sending CW through a WinKeyer
// (WinKeyer.swift) and the messages F1 to F8 send (CWMessages.swift).
//   - WinKeyer port: a menu of the Mac's serial ports. The author's WinKeyer
//     Mini is /dev/cu.usbserial-XXXX (not the radios' ports).
//   - Speed (words per minute, 5 to 99). Control-Command-= and - change it
//     too while the WinKeyer is connected.
//   - Your name, for the {MYNAME} fill-in.
//   - Messages F1 to F8, with a note listing the fill-ins.
// Saved on leaving each field. Escape saves the field, then closes.
// Connecting is in the CW menu, never here, so opening Settings never
// takes the WinKeyer from another app.

import AppKit

@MainActor
final class CWSettingsViewController: NSViewController, NSTextFieldDelegate {
    var onEscape: (() -> Void)?

    private let portMenu = NSPopUpButton()
    private let speedField = NSTextField(string: "")
    private let nameField = NSTextField(string: "")
    private let messageFields: [NSTextField] = (0..<CWMessages.count).map { _ in NSTextField(string: "") }
    private var ports: [String] = []
    private let messagesHeading = NSTextField(labelWithString: "")
    // The profile whose messages are showing, to notice a switch.
    private var shownProfile: UUID?

    var firstControl: NSView { portMenu }

    override func loadView() {
        let heading = NSTextField(labelWithString: "CW through a WinKeyer")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        let note = NSTextField(wrappingLabelWithString:
            "CW > Connect WinKeyer opens it (quit any other app using the WinKeyer first: only one app can have "
            + "it at a time). Then F1 to F8 "
            + "send these messages, and Escape stops sending. Each profile has its own messages (a Field Day "
            + "profile starts with Field Day's). Fill-ins: {MYCALL}, {MYNAME}, {MYSTATE} are yours; "
            + "{SENT} is your exchange (Exchange sent); {CALL}, {NAME}, {STATE}, {SKCC} are theirs, from the form; "
            + "{RST} is the report you send, or 599. One with nothing to fill it is left out.")
        note.preferredMaxLayoutWidth = 520
        portMenu.setAccessibilityLabel("WinKeyer port")
        portMenu.target = self
        portMenu.action = #selector(portChosen(_:))
        speedField.setAccessibilityLabel("Speed, words per minute")
        nameField.setAccessibilityLabel("Your name")
        var rows: [[NSView]] = [[FieldLabel("WinKeyer port"), portMenu],
                                [FieldLabel("Speed, words per minute"), speedField],
                                [FieldLabel("Your name"), nameField]]
        for (index, field) in messageFields.enumerated() {
            let title = "F\(index + 1) message"
            field.setAccessibilityLabel(title)
            rows.append([FieldLabel(title), field])
        }
        for field in [speedField, nameField] + messageFields {
            field.delegate = self
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        }
        let grid = NSGridView(views: rows)
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.rowAlignment = .firstBaseline
        let order: [NSView] = [portMenu, speedField, nameField] + messageFields
        for (index, view) in order.enumerated() { view.nextKeyView = order[(index + 1) % order.count] }
        messagesHeading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let stack = NSStackView(views: [heading, note, messagesHeading, grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        view = stack
        refresh()
        // Another profile chosen while Settings is open: its messages.
        NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.shownProfile != Settings.currentProfile.id else { return }
                self.refresh()
            }
        }
    }

    // Shows what's saved (when Settings opens), with the ports there now.
    func refresh() {
        guard isViewLoaded else { return }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        ports = names.filter { $0.hasPrefix("cu.") && !$0.contains("Bluetooth") && $0 != "cu.debug-console" }
            .sorted().map { "/dev/" + $0 }
        let current = Settings.cwPort
        if !current.isEmpty, !ports.contains(current) { ports.append(current) }
        portMenu.removeAllItems()
        portMenu.addItem(withTitle: "None chosen")
        portMenu.addItems(withTitles: ports.map { $0 == current && !FileManager.default.fileExists(atPath: $0)
            ? "\($0) (not plugged in)" : $0 })
        portMenu.selectItem(at: ports.firstIndex(of: current).map { $0 + 1 } ?? 0)
        speedField.stringValue = String(Settings.cwSpeed)
        nameField.stringValue = Settings.cwMyName
        for (field, message) in zip(messageFields, Settings.cwMessages) { field.stringValue = message }
        shownProfile = Settings.currentProfile.id
        messagesHeading.stringValue = "Messages for the \(Settings.currentProfile.name) profile"
    }

    @objc private func portChosen(_ sender: Any?) {
        let index = portMenu.indexOfSelectedItem - 1
        Settings.cwPort = ports.indices.contains(index) ? ports[index] : ""
        Speaker.announce(Settings.cwPort.isEmpty ? "No WinKeyer port." : "WinKeyer port \(Settings.cwPort).")
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        switch field {
        case speedField:
            guard let wpm = Int(text), (5...99).contains(wpm) else {
                NSSound.beep()
                Speaker.announce("Speed is words per minute, 5 to 99.")
                field.stringValue = String(Settings.cwSpeed)
                return
            }
            guard wpm != Settings.cwSpeed else { return }
            Settings.cwSpeed = wpm
            // The WinKeyer, if connected, takes the new speed (AppDelegate).
            NotificationCenter.default.post(name: Settings.didChange, object: nil)
        case nameField: Settings.cwMyName = text
        default:
            guard let index = messageFields.firstIndex(of: field) else { return }
            var messages = Settings.cwMessages
            // An emptied message goes back to its starting text, so F-keys
            // never send nothing by surprise.
            messages[index] = text.isEmpty ? CWMessages.defaults[index] : text
            Settings.cwMessages = messages
            field.stringValue = messages[index]
            // The CW menu shows each message; it's refilled from Settings.
            NotificationCenter.default.post(name: Settings.didChange, object: nil)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        view.window?.makeFirstResponder(nil)
        onEscape?()
        return true
    }
}
