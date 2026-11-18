// ActivityWindowController.swift
//
// Window > Activity (Command-2): the list from Activity.swift, newest
// first. Each row is one sentence, so VoiceOver reads a whole item at a
// time, as Spots does: "Done. LoTW. Upload. Started 2:14 PM. Finished
// 2:15 PM. Latest: 12 contacts sent."
//
// The window opens once and is kept (closing only hides it), and it
// refreshes itself whenever Activity changes, so a running upload's
// latest step is there as it happens.

import AppKit

@MainActor
final class ActivityWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let empty = NSTextField(wrappingLabelWithString: "No sync or upload yet since Solid Copy opened.")
    private let clock: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Activity"
        window.contentMinSize = NSSize(width: 360, height: 200)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ActivityWindow")
        super.init(window: window)
        window.delegate = self
        window.contentView = build()
        window.initialFirstResponder = table
        if !window.setFrameUsingName("ActivityWindow") { window.center() }

        NotificationCenter.default.addObserver(forName: Activity.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    func show() {
        reload()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(table)
    }

    private func build() -> NSView {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("activity"))
        column.title = "Activity"
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.allowsEmptySelection = true
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        // Each row grows to fit its wrapped sentence.
        table.usesAutomaticRowHeights = true
        table.setAccessibilityLabel("Activity")

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        empty.translatesAutoresizingMaskIntoConstraints = false
        empty.setAccessibilityElement(false)

        let view = NSView()
        view.addSubview(scroll)
        view.addSubview(empty)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            empty.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            empty.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            empty.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
        ])
        return view
    }

    private func reload() {
        table.reloadData()
        // The sentence says so when there's nothing to list (the table is
        // empty then, so the two never overlap).
        empty.isHidden = !Activity.shared.items.isEmpty
    }

    // One sentence per item, read whole by VoiceOver.
    private func line(_ item: Activity.Item) -> String {
        var parts = [item.state.rawValue + ".", item.service + ".", item.what + ".",
                     "Started " + clock.string(from: item.started) + "."]
        if let ended = item.ended {
            parts.append("Finished " + clock.string(from: ended) + ".")
        }
        if !item.latest.isEmpty {
            parts.append("Latest: " + item.latest)
        }
        return parts.joined(separator: " ")
    }

    func numberOfRows(in tableView: NSTableView) -> Int { Activity.shared.items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let items = Activity.shared.items
        guard items.indices.contains(row) else { return nil }
        let id = NSUserInterfaceItemIdentifier("activityCell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = id
            let label = NSTextField(wrappingLabelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),
                label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -4),
            ])
            return cell
        }()
        cell.textField?.stringValue = line(items[row])
        return cell
    }
}
