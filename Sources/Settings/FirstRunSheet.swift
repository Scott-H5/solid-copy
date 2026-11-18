// FirstRunSheet.swift
//
// The setup sheet shown the first time Solid Copy opens with no callsign in
// the profile in use (AppDelegate calls offerIfNeeded at launch). It asks
// for three things: your callsign, your name and your grid square.
//
// Save puts the callsign and grid square into the profile in use. Every
// contact you log carries them, and the uploads need them. The name goes to
// the CW messages' {MYNAME}. Skip leaves everything empty, as it was. Either
// way the sheet isn't shown at launch again. Settings > Profiles and
// Settings > CW have the same fields for later changes.
//
// If the profile already has a callsign when the app first opens (an
// existing user), the sheet is never shown, so it doesn't interrupt anyone.

import AppKit

@MainActor
final class FirstRunSheet: NSObject {
    // Kept alive while the sheet is up, since nothing else refers to it.
    private static var showing: FirstRunSheet?

    private let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
                                styleMask: [.titled], backing: .buffered, defer: false)
    private let callField = NSTextField()
    private let nameField = NSTextField()
    private let gridField = NSTextField()
    private let problem = NSTextField(labelWithString: "")
    private weak var host: NSWindow?
    // Runs when the sheet closes, so Settings can show the new values.
    private var onDone: (() -> Void)?

    // Shows the sheet over the main window if this is the first launch with
    // no callsign. An existing user with a callsign is marked as done.
    static func offerIfNeeded(over window: NSWindow) {
        guard !Settings.firstRunDone else { return }
        guard (Settings.currentProfile.station["station_callsign"] ?? "").isEmpty else {
            Settings.firstRunDone = true
            return
        }
        show(over: window)
    }

    // Shows the sheet at any time, from here or from Settings > Profiles,
    // filled in with what's already set.
    static func show(over window: NSWindow, onDone: (() -> Void)? = nil) {
        let made = FirstRunSheet()
        made.onDone = onDone
        showing = made
        made.present(over: window)
    }

    private func present(over window: NSWindow) {
        host = window
        let station = Settings.currentProfile.station
        callField.stringValue = station["station_callsign"] ?? ""
        gridField.stringValue = station["my_gridsquare"] ?? ""
        nameField.stringValue = Settings.cwMyName
        panel.contentView = build()
        window.beginSheet(panel) { _ in }
        panel.makeFirstResponder(callField)
    }

    private func build() -> NSView {
        let heading = NSTextField(wrappingLabelWithString:
            "Set up your station. Each contact you log carries your callsign and grid square, "
            + "and the uploads need them. You can change these later in Settings > Profiles.")
        heading.preferredMaxLayoutWidth = 390

        callField.placeholderString = "For example W1AW"
        nameField.placeholderString = "Optional, for CW messages"
        gridField.placeholderString = "For example FN31"
        callField.setAccessibilityLabel("Your callsign")
        nameField.setAccessibilityLabel("Your name")
        gridField.setAccessibilityLabel("Your grid square")
        for field in [callField, nameField, gridField] { field.translatesAutoresizingMaskIntoConstraints = false }

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Callsign:"), callField],
            [NSTextField(labelWithString: "Name:"), nameField],
            [NSTextField(labelWithString: "Grid square:"), gridField],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 1).width = 260

        let skip = NSButton(title: "Skip", target: self, action: #selector(skip(_:)))
        skip.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "Save", target: self, action: #selector(save(_:)))
        save.keyEquivalent = "\r"
        let buttons = NSStackView(views: [skip, save])
        buttons.orientation = .horizontal
        buttons.spacing = 12

        problem.textColor = .systemRed
        problem.preferredMaxLayoutWidth = 390

        let stack = NSStackView(views: [heading, grid, problem, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let view = NSView()
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.widthAnchor.constraint(equalToConstant: 440),
        ])
        view.layoutSubtreeIfNeeded()
        panel.setContentSize(stack.fittingSize)
        return view
    }

    // Saves what's valid and closes; says what's wrong and stays open otherwise.
    @objc private func save(_ sender: Any?) {
        let call = Callsign.normalized(callField.stringValue)
        guard !call.isEmpty else { return refuse("Enter your callsign, or choose Skip.", in: callField) }
        guard Callsign.looksValid(call) else { return refuse("That doesn't look like a callsign.", in: callField) }
        let grid = gridField.stringValue.trimmingCharacters(in: .whitespaces).uppercased()
        guard grid.isEmpty || GreatCircle.position(grid: grid) != nil else {
            return refuse("That isn't a grid square. It looks like FN31, or FN31ab.", in: gridField)
        }

        var profile = Settings.currentProfile
        profile.station["station_callsign"] = call
        profile.station["my_gridsquare"] = grid.isEmpty ? nil : grid
        Settings.currentProfile = profile

        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { Settings.cwMyName = name }
        finish()
    }

    @objc private func skip(_ sender: Any?) { finish() }

    // Says why in the sheet and aloud, and puts the focus on the field to fix.
    private func refuse(_ message: String, in field: NSTextField) {
        problem.stringValue = message
        Speaker.announce(message)
        panel.makeFirstResponder(field)
    }

    private func finish() {
        Settings.firstRunDone = true
        if let host { host.endSheet(panel) }
        Self.showing = nil
        onDone?()
    }
}
