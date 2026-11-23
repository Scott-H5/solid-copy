// ProfilesViewController.swift
//
// Settings > Profiles: your operating profiles, such as Home and Portable.
// A profile is a logging form (chosen in the Logging Form tab) and your
// station's details, which are added to every contact logged with it.
//
// From top to bottom:
//   - Profile in use: a pop-up menu. Choosing one switches to it, here and
//     in the main window (the Profile menu does the same).
//   - Profile name, to rename it.
//   - New Profile, a menu: a copy of the profile in use, or a new one
//     from a template (Home, Portable, POTA, SOTA, Field Day, State QSO
//     Party; see Settings.templates), keeping your station but not its
//     park or summit. Then Delete Profile.
//   - Your station for this profile: every "My station" field (callsign,
//     grid, state, county, radio, park, summit, ...). Empty ones are left
//     off contacts.
//
// Everything is saved as soon as you leave a field.

import AppKit

@MainActor
final class ProfilesViewController: NSViewController, NSTextFieldDelegate {

    // Called when the profile in use changes, so the Logging Form tab can
    // show the new one's form.
    var onProfileChange: (() -> Void)?
    var onEscape: (() -> Void)?

    private let profileMenu = NSPopUpButton()
    private var newMenuButton: NSPopUpButton?
    private let nameField = NSTextField(string: "")
    private var stationFields: [String: NSTextField] = [:]
    // Your park (MY_POTA_REF) searches POTA's park list.
    private let parkSearch = ParkSearch()
    private var parkField: NSTextField? { stationFields["my_pota_ref"] }

    // The first control, for focus when the tab is chosen.
    var firstControl: NSView { profileMenu }
    // The profile this page shows (in the pop-up and the name field).
    private var shownID: UUID?
    private var observer: NSObjectProtocol?

    override func loadView() {
        profileMenu.setAccessibilityLabel("Profile in use")
        profileMenu.target = self
        profileMenu.action = #selector(chooseProfile(_:))

        nameField.setAccessibilityLabel("Profile name")
        nameField.delegate = self
        // Solid Copy changes the profile in use by itself too: opening a
        // log brings back its profile (a contest log's, say). The page
        // follows, so the pop-up and the name always show the same one
        // (the author found them showing two, 23 November 2026).
        observer = NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let current = Settings.currentProfile
                guard current.id != self.shownID || current.name != self.profileMenu.titleOfSelectedItem else { return }
                self.refresh()
            }
        }
        nameField.widthAnchor.constraint(equalToConstant: 260).isActive = true

        // A pull-down menu: its first item is the button's title.
        let newButton = NSPopUpButton(frame: .zero, pullsDown: true)
        newButton.setAccessibilityLabel("New Profile")
        newMenuButton = newButton
        let deleteButton = NSButton(title: "Delete Profile", target: self, action: #selector(deleteProfile(_:)))
        let setUpButton = NSButton(title: "Set Up Station…", target: self, action: #selector(setUpStation(_:)))
        setUpButton.setAccessibilityLabel("Set Up Station")
        let buttons = NSStackView(views: [newButton, deleteButton, setUpButton])
        buttons.spacing = 8

        let top = NSGridView(views: [[FieldLabel("Profile in use"), profileMenu],
                                     [FieldLabel("Profile name"), nameField]])
        top.column(at: 0).xPlacement = .trailing
        top.rowSpacing = 8
        top.rowAlignment = .firstBaseline

        let heading = NSTextField(labelWithString: "Your station, for this profile")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        let note = NSTextField(wrappingLabelWithString:
            "Added to every contact logged with this profile. Leave a field empty to leave it off.")
        note.preferredMaxLayoutWidth = 520

        var rows: [[NSView]] = []
        var order: [NSView] = [profileMenu, nameField, newButton, deleteButton, setUpButton]
        for field in LogField.all where field.group == .myStation {
            let textField = NSTextField(string: "")
            textField.setAccessibilityLabel(field.label)
            textField.delegate = self
            textField.widthAnchor.constraint(equalToConstant: 260).isActive = true
            stationFields[field.adif] = textField
            rows.append([FieldLabel(field.label), textField])
            order.append(textField)
        }
        let stationGrid = NSGridView(views: rows)
        stationGrid.column(at: 0).xPlacement = .trailing
        stationGrid.rowSpacing = 8
        stationGrid.rowAlignment = .firstBaseline

        let stack = NSStackView(views: [top, buttons, heading, note, stationGrid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(24, after: buttons)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        view = stack

        // Tab order, top to bottom (the pop-up and buttons only when
        // Keyboard navigation is on in System Settings).
        for (index, item) in order.enumerated() {
            item.nextKeyView = order[(index + 1) % order.count]
        }
        refresh()
    }

    // Shows the profile in use.
    func refresh() {
        let profiles = Settings.profiles
        let current = Settings.currentProfile
        profileMenu.removeAllItems()
        profileMenu.addItems(withTitles: profiles.map(\.name))
        if let index = profiles.firstIndex(where: { $0.id == current.id }) {
            profileMenu.selectItem(at: index)
        }
        nameField.stringValue = current.name
        shownID = current.id
        if let newButton = newMenuButton {
            newButton.removeAllItems()
            newButton.addItem(withTitle: "New Profile")
            let copy = NSMenuItem(title: "Copy of \(current.name)", action: #selector(newProfile(_:)), keyEquivalent: "")
            copy.target = self
            newButton.menu?.addItem(copy)
            newButton.menu?.addItem(.separator())
            for (index, template) in Settings.templates.enumerated() {
                let item = NSMenuItem(title: "From \(template.name) template: \(template.about)",
                                      action: #selector(newFromTemplate(_:)), keyEquivalent: "")
                item.tag = index
                item.target = self
                newButton.menu?.addItem(item)
            }
        }
        for (adif, field) in stationFields {
            field.stringValue = current.station[adif] ?? ""
        }
    }

    // MARK: - Commands

    @objc private func chooseProfile(_ sender: Any?) {
        let profiles = Settings.profiles
        guard profiles.indices.contains(profileMenu.indexOfSelectedItem) else { return }
        let chosen = profiles[profileMenu.indexOfSelectedItem]
        Settings.useProfile(chosen.id)
        refresh()
        onProfileChange?()
        Speaker.announce("\(chosen.name) profile.")
    }

    // A copy of the profile in use, named "Portable 2" (say), which becomes
    // the profile in use. Focus goes to its name, ready to rename.
    @objc private func newProfile(_ sender: Any?) {
        var copy = Settings.currentProfile
        copy.id = UUID()
        copy.name = Self.unusedName(copy.name)
        add(copy, said: "New profile, \(copy.name). Type a name for it.")
    }

    // A new profile with a template's form and your station from the
    // profile in use, less where you're operating from (park, summit,
    // special event), which belongs to one outing.
    @objc private func newFromTemplate(_ sender: NSMenuItem) {
        guard Settings.templates.indices.contains(sender.tag) else { return }
        let template = Settings.templates[sender.tag]
        var station = Settings.currentProfile.station
        for adif in ["my_pota_ref", "my_sota_ref", "my_wwff_ref", "my_sig", "my_sig_info"] { station[adif] = nil }
        let profile = Profile(name: Self.unusedName(template.name), formFields: template.formFields, station: station,
                              cwMessages: template.cwMessages)
        add(profile, said: "New profile, \(profile.name), from the \(template.name) template. "
            + "Type a name for it, or press Tab to keep it.")
    }

    // A name no profile has yet: the one given, or "Portable 2" (say).
    private static func unusedName(_ name: String) -> String {
        let names = Set(Settings.profiles.map(\.name))
        guard names.contains(name) else { return name }
        var number = 2
        while names.contains("\(name) \(number)") { number += 1 }
        return "\(name) \(number)"
    }

    // Makes it the profile in use, and puts focus on its name to rename.
    private func add(_ profile: Profile, said: String) {
        Settings.currentProfile = profile
        refresh()
        onProfileChange?()
        view.window?.makeFirstResponder(nameField)
        Speaker.announce(said)
    }

    // The setup sheet (FirstRunSheet.swift) for the profile in use.
    @objc private func setUpStation(_ sender: Any?) {
        FirstRunSheet.show { [weak self] in self?.refresh() }
    }

    // Deletes the profile in use, after asking (there's no Undo here), and
    // switches to the first one left. The last profile can't be deleted.
    @objc private func deleteProfile(_ sender: Any?) {
        let profiles = Settings.profiles
        let current = Settings.currentProfile
        guard profiles.count > 1, let window = view.window else {
            Speaker.announce("This is the only profile, so it can't be deleted.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Delete the \(current.name) profile?"
        alert.informativeText = "Its form and station details will be gone. Contacts already logged with it aren't changed."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let remaining = profiles.filter { $0.id != current.id }
            Settings.profiles = remaining
            Settings.useProfile(remaining[0].id)
            self?.refresh()
            self?.onProfileChange?()
            Speaker.announce("Deleted. Now using \(remaining[0].name).")
        }
    }

    // MARK: - Saving

    // Saves a field as soon as you leave it.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        // The profile this page shows: the one the name and fields belong to.
        var profile = Settings.profiles.first { $0.id == shownID } ?? Settings.currentProfile
        if field === nameField {
            let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name != profile.name else {
                nameField.stringValue = profile.name
                return
            }
            profile.name = name
        } else if let adif = stationFields.first(where: { $0.value === field })?.key {
            // Your park: one search match becomes that park; anything
            // that's still not a park isn't saved (and says why).
            if field === parkField {
                parkSearch.left(field)
                guard parkSearch.resolve(field, label: "My POTA park") else { return }
            }
            var value = field.stringValue.trimmingCharacters(in: .whitespaces)
            if adif == "station_callsign" { value = Callsign.normalized(value) }
            field.stringValue = value
            guard (profile.station[adif] ?? "") != value else { return }
            profile.station[adif] = value.isEmpty ? nil : value
        } else {
            return
        }
        Settings.currentProfile = profile
        // A new name: the pop-up and the Logging Form heading show it.
        if field === nameField {
            refresh()
            onProfileChange?()
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        if let field = notification.object as? NSTextField, field === parkField { parkSearch.textChanged(in: field) }
    }

    // Escape closes Settings from any field here. Down and Up go through
    // park matches in Your park.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if let field = control as? NSTextField, field === parkField, parkSearch.key(selector, in: field) { return true }
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        view.window?.makeFirstResponder(nil)
        onEscape?()
        return true
    }
}
