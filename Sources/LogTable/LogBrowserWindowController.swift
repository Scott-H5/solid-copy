// LogBrowserWindowController.swift
//
// Window > Log (Command-3): the open log in a window of its own, for
// looking a contact up without touching the logging window. Browsing
// only. Its table (LogTableViewController with browseOnly set) doesn't
// edit, delete, mark cards, upload or paste, and while this window is in
// front the logging window's log commands are off (the Edit, Delete and
// QSL menus), so none of them can reach the log by mistake.
//
// Search narrows the list as you type, the same search as the logging
// window's, over every field. The count under it says how many match.
//
// The window opens once and is kept (closing only hides it). Switching
// logs points it at the new one (AppDelegate.install).

import AppKit

@MainActor
final class LogBrowserWindowController: NSWindowController, NSWindowDelegate, NSSearchFieldDelegate {
    // True while this window is the key window (see the header above).
    static var isFrontmost = false

    private var logbook: Logbook
    private let table: LogTableViewController
    private let searchField = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")

    init(logbook: Logbook) {
        self.logbook = logbook
        table = LogTableViewController(logbook: logbook)
        table.browseOnly = true
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Log"
        window.contentMinSize = NSSize(width: 480, height: 260)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("LogBrowserWindow")
        super.init(window: window)
        window.delegate = self
        window.contentView = build()
        window.initialFirstResponder = searchField
        if !window.setFrameUsingName("LogBrowserWindow") { window.center() }

        // New contacts (logged in the logging window) change the count.
        logbook.observe { [weak self] in self?.refreshCount() }
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(searchField)
    }

    // Points the window at another log (AppDelegate.install), with the
    // search cleared.
    func use(_ newLogbook: Logbook) {
        logbook = newLogbook
        searchField.stringValue = ""
        table.use(newLogbook)
        refreshCount()
    }

    private func build() -> NSView {
        searchField.placeholderString = "Search this log"
        searchField.setAccessibilityLabel("Search this log")
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.sendsSearchStringImmediately = true
        searchField.translatesAutoresizingMaskIntoConstraints = false

        countLabel.translatesAutoresizingMaskIntoConstraints = false

        let tableView = table.view
        tableView.translatesAutoresizingMaskIntoConstraints = false

        let view = NSView()
        view.addSubview(searchField)
        view.addSubview(countLabel)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            countLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            countLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            countLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tableView.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 6),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])
        return view
    }

    // As the search changes (typing, or the search field's clear button).
    @objc private func searchChanged(_ sender: Any?) { refreshCount() }

    func controlTextDidChange(_ notification: Notification) { refreshCount() }

    // Narrows (or widens) the list to the search, and says how many match.
    private func refreshCount() {
        let text = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            table.showAllContacts()
            countLabel.stringValue = Self.describe(logbook.contacts.count, searching: false)
        } else {
            countLabel.stringValue = Self.describe(table.search(text), searching: true)
        }
    }

    // "12 contacts" or "3 of 12 contacts match" (the count VoiceOver reads).
    private static func describe(_ count: Int, searching: Bool) -> String {
        let noun = count == 1 ? "contact" : "contacts"
        return searching ? "\(count.formatted()) \(noun) match" : "\(count.formatted()) \(noun)"
    }

    func windowDidBecomeKey(_ notification: Notification) { Self.isFrontmost = true }
    func windowDidResignKey(_ notification: Notification) { Self.isFrontmost = false }
}
