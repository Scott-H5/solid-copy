// BackupsSettingsViewController.swift
//
// Settings > Backups: a second folder for backups (Backups.swift).
//   - A note on what Solid Copy keeps beside the log (the newest 20
//     backups) and why a second folder helps (losing the Mac or its drive).
//   - The folder in use, or "none", and when the last copy went there.
//   - While Solid Copy is open, back up: Never, Every hour, Every 4 hours
//     (the starting choice), Once a day; only if the log changed.
//   - Choose Backup Folder… (an Open dialog; New Folder makes one; iCloud
//     Drive is in its sidebar), Stop Using This Folder, Back Up Now.
// A copy goes there when Solid Copy opens, on the schedule, when it quits
// (if the log changed), and with Back Up Now. Escape closes Settings.

import AppKit

@MainActor
final class BackupsSettingsViewController: NSViewController {
    var onEscape: (() -> Void)?
    // Back Up Now goes through the app (File > Back Up Now).
    var onBackUpNow: (() -> Void)?

    private let status = NSTextField(wrappingLabelWithString: "")
    private let scheduleMenu = NSPopUpButton()
    private let chooseButton = NSButton(title: "Choose Backup Folder…", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop Using This Folder", target: nil, action: nil)
    private let nowButton = NSButton(title: "Back Up Now", target: nil, action: nil)

    var firstControl: NSView { scheduleMenu }

    override func loadView() {
        let heading = NSTextField(labelWithString: "Backups")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        let note = NSTextField(wrappingLabelWithString:
            "Solid Copy backs up the log each time it opens, and before imports, keeping the newest 20 beside "
            + "the log. Those are lost with this Mac or its drive, so choose a second folder too, such as one in "
            + "iCloud Drive or on another disk. A copy goes there when Solid Copy opens, on the schedule below "
            + "while it's open, when it quits, and with File > Back Up Now; the newest 20 are kept, with your "
            + "scanned cards. The schedule and quitting only back up if the log changed. Nothing is said when "
            + "it works.")
        note.preferredMaxLayoutWidth = 520
        status.preferredMaxLayoutWidth = 520
        scheduleMenu.addItems(withTitles: Settings.backupScheduleChoices.map(\.title))
        scheduleMenu.setAccessibilityLabel("While Solid Copy is open, back up")
        scheduleMenu.target = self
        scheduleMenu.action = #selector(scheduleChanged(_:))
        let scheduleRow = NSStackView(views: [FieldLabel("While Solid Copy is open, back up"), scheduleMenu])
        scheduleRow.spacing = 8
        chooseButton.target = self
        chooseButton.action = #selector(choose(_:))
        stopButton.target = self
        stopButton.action = #selector(stop(_:))
        nowButton.target = self
        nowButton.action = #selector(backUpNow(_:))
        let order: [NSView] = [scheduleMenu, chooseButton, stopButton, nowButton]
        for (index, view) in order.enumerated() { view.nextKeyView = order[(index + 1) % order.count] }
        let stack = NSStackView(views: [heading, note, scheduleRow, status, chooseButton, stopButton, nowButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        view = stack
        refresh()
    }

    func refresh() {
        guard isViewLoaded else { return }
        scheduleMenu.selectItem(at: Settings.backupScheduleChoices.firstIndex { $0.hours == Settings.backupEveryHours } ?? 2)
        guard let name = Backups.folderName else {
            status.stringValue = "Backup folder: none chosen. Backups are only beside the log."
            stopButton.isEnabled = false
            return
        }
        let last = Settings.backupLast.map { " Last copy: \($0.formatted(date: .long, time: .shortened))." } ?? ""
        status.stringValue = "Backup folder: \(name).\(last)"
        stopButton.isEnabled = true
    }

    @objc private func choose(_ sender: Any?) {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.title = "Backup Folder"
        panel.message = "Choose a folder for copies of your log, such as one in iCloud Drive. New Folder makes one."
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try Backups.setFolder(url)
                Speaker.announce("Backup folder: \(url.lastPathComponent). Backing up there now.")
                self?.onBackUpNow?()
            } catch {
                Speaker.announce("Couldn't keep that folder. \(error.localizedDescription)")
            }
            self?.refresh()
        }
    }

    @objc private func scheduleChanged(_ sender: Any?) {
        let choice = Settings.backupScheduleChoices[max(0, scheduleMenu.indexOfSelectedItem)]
        Settings.backupEveryHours = choice.hours
        Speaker.announce(choice.hours == 0 ? "No backups while open; still on opening and quitting."
                         : "Backups \(choice.title.lowercased()) while open, if the log changed.")
    }

    @objc private func stop(_ sender: Any?) {
        try? Backups.setFolder(nil)
        Settings.backupLast = nil
        Speaker.announce("No backup folder. The copies already there are left as they are.")
        refresh()
    }

    @objc private func backUpNow(_ sender: Any?) {
        onBackUpNow?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.refresh() }
    }

    // Escape closes Settings (buttons don't get it from a text field).
    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
