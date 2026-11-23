// WSJTXSettingsViewController.swift
//
// Settings > WSJT-X (WSJTXAlerts.swift; moved here from Settings > Radio,
// 23 November 2026, since they aren't radio settings and Radio had grown
// long to arrow through):
//   - Listen for WSJT-X all the time: from launch, not only while Window >
//     WSJT-X Decodes is open, so every contact WSJT-X logs comes in.
//   - Alert me with the decodes window closed: a station calling you, or a
//     needed one, with the needed sound and (another app in front) a
//     notification.
// Each choice is saved at once. Escape closes Settings.

import AppKit

@MainActor
final class WSJTXSettingsViewController: NSViewController {
    var onEscape: (() -> Void)?

    private let listenBox = NSButton(checkboxWithTitle: "Listen for WSJT-X all the time", target: nil, action: nil)
    private let alertsBox = NSButton(checkboxWithTitle: "Alert me with the decodes window closed",
                                     target: nil, action: nil)

    var firstControl: NSView { listenBox }

    override func loadView() {
        let heading = NSTextField(labelWithString: "WSJT-X")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)

        listenBox.target = self
        listenBox.action = #selector(toggleListen(_:))
        let listenNote = NSTextField(wrappingLabelWithString:
            "With this on, Solid Copy listens for WSJT-X from the moment it opens, not only while Window > "
            + "WSJT-X Decodes is open, so every contact you log in WSJT-X goes into the open log. Only "
            + "contacts WSJT-X logs are added, never its decodes. WSJT-X sends to 127.0.0.1 port 2237 "
            + "(its Settings > Reporting, UDP Server), and only one program can listen there.")
        listenNote.preferredMaxLayoutWidth = 520
        listenNote.isSelectable = true
        listenBox.setAccessibilityLinkedUIElements([listenNote])

        alertsBox.target = self
        alertsBox.action = #selector(toggleAlerts(_:))
        let alertsNote = NSTextField(wrappingLabelWithString:
            "While listening with the decodes window closed: a station calling you, and a needed one (a new "
            + "country, or new on this band or in data modes), with the needed sound. With Solid Copy in "
            + "front VoiceOver says it; with another app in front it's a notification, which VoiceOver "
            + "reads (macOS asks once to allow them). Each needed station is told once per band an hour. "
            + "Window > Activity lists them all.")
        alertsNote.preferredMaxLayoutWidth = 520
        alertsNote.isSelectable = true
        alertsBox.setAccessibilityLinkedUIElements([alertsNote])

        listenBox.nextKeyView = alertsBox
        alertsBox.nextKeyView = listenBox
        let stack = NSStackView(views: [heading, listenBox, listenNote, alertsBox, alertsNote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(20, after: listenNote)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        view = stack
        refresh()
    }

    func refresh() {
        guard isViewLoaded else { return }
        listenBox.state = Settings.wsjtxAlwaysListen ? .on : .off
        alertsBox.state = Settings.wsjtxAlerts ? .on : .off
        alertsBox.isEnabled = Settings.wsjtxAlwaysListen
    }

    @objc private func toggleListen(_ sender: NSButton) {
        Settings.wsjtxAlwaysListen = sender.state == .on
        alertsBox.isEnabled = sender.state == .on
        WSJTXAlerts.shared.apply()
        if sender.state == .on, let problem = WSJTXListener.shared.problem {
            Speaker.announce("Can't listen for WSJT-X. \(problem)")
        } else {
            Speaker.announce(sender.state == .on ? "Listening for WSJT-X all the time."
                             : "Listening for WSJT-X only with the decodes window open.")
        }
    }

    @objc private func toggleAlerts(_ sender: NSButton) {
        Settings.wsjtxAlerts = sender.state == .on
        WSJTXAlerts.shared.apply()
    }

    // Escape closes Settings (checkboxes don't get it otherwise).
    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
