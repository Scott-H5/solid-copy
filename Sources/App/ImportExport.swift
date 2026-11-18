// ImportExport.swift
//
// File > Import… and File > Export…: the dialogs and summaries. The work of
// reading and writing each format is in Sources/Import and Sources/Export;
// this file only asks which file, and reports what happened.
//
// It's more of the AppDelegate class (an "extension"), kept in its own file
// so AppDelegate.swift stays short.

import AppKit
import UniformTypeIdentifiers

extension AppDelegate {

    // MARK: - Import

    // File > Import…: pick an ADIF or ADX file or a MacLoggerDX log and add its
    // contacts. The file is only read, never changed. The log is backed up
    // first, contacts already in the log are skipped, and Edit > Undo takes
    // the whole import back out.
    @objc func importLog(_ sender: Any?) {
        guard let window, window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Import"
        panel.message = "Choose an ADIF file (.adi or .adif), an ADX file (.adx) or a MacLoggerDX log "
            + "(MacLoggerDX.sql)."
        panel.prompt = "Import"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["adi", "adif", "adx", "sql"].compactMap { UTType(filenameExtension: $0) }
        panel.directoryURL = realDocumentsFolder
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.importLog(from: url)
        }
    }

    private func importLog(from url: URL) {
        guard let logbook else { return }
        let result: LogImport.Result
        let added: [QSO]
        let skipped: Int
        do {
            result = try LogImport.read(from: url)
            try logbook.backUp()
            (added, skipped) = try logbook.importContacts(result.contacts)
        } catch {
            showMessage("The import didn't work.", details: error.localizedDescription)
            return
        }

        registerImportUndo(added)

        // LoTW's confirmation bookmark (Settings.lotwLastQSL) says "I have
        // every confirmation up to here" for the log as it was. Imported
        // contacts may have older confirmations it never applied to them
        // (a fresh log re-imported after a sync, 16 November 2026), so
        // the next sync asks LoTW for all of them again. Matching ones
        // already marked are left as they are, so this only costs a
        // bigger download, once.
        if !added.isEmpty { Settings.lotwLastQSL = "" }

        var details = ["From the \(result.format) \(url.lastPathComponent)."]
        details.append(added.count == 1 ? "1 contact was added." : "\(added.count) contacts were added.")
        if skipped > 0 {
            details.append("\(skipped) already in the log \(skipped == 1 ? "was" : "were") skipped.")
        }
        if result.unreadable > 0 {
            details.append("\(result.unreadable) couldn't be read (no callsign, or no date and time).")
        }
        if !result.repeated.isEmpty {
            details.append("The file has some contacts more than once, with the same call and time. "
                + "They were added as they are, so you can check them: "
                + Self.shortList(result.repeated, separator: "; ") + ".")
        }
        if !result.leftOut.isEmpty {
            details.append("These fields aren't in Solid Copy yet, so they weren't imported: "
                + Self.shortList(result.leftOut, separator: ", ") + ".")
        }
        details.append("The file you imported wasn't changed. Edit > Undo takes this import back out.")
        showMessage("Import finished.", details: details.joined(separator: "\n\n"))
    }

    // Edit > Undo removes everything an import added, and Redo puts it back.
    private func registerImportUndo(_ contacts: [QSO]) {
        guard let undoManager = window?.undoManager, !contacts.isEmpty else { return }
        undoManager.registerUndo(withTarget: self) { delegate in
            do {
                try delegate.logbook?.removeAll(ids: contacts.map(\.id))
                Speaker.announce("Import undone. \(contacts.count) contacts removed.")
            } catch {
                Speaker.announce("Couldn't undo the import. \(error.localizedDescription)")
                return
            }
            undoManager.registerUndo(withTarget: delegate) { delegate in
                _ = try? delegate.logbook?.importContacts(contacts)
                delegate.registerImportUndo(contacts)
                Speaker.announce("Import redone.")
            }
            undoManager.setActionName("Import")
        }
        undoManager.setActionName("Import")
    }

    // MARK: - Export

    // File > Export…: saves the whole log as ADIF, ADX or CSV. The dialog has a
    // Format menu and an Include Notes checkbox (off unless you tick it,
    // because notes are private).
    @objc func exportLog(_ sender: Any?) {
        guard let window, window.attachedSheet == nil, let logbook else { return }
        guard !logbook.contacts.isEmpty else {
            showMessage("There's nothing to export yet.", details: "The log is empty.")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export"
        panel.prompt = "Export"
        panel.directoryURL = realDocumentsFolder
        panel.isExtensionHidden = false
        let options = ExportOptions(panel: panel)

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let format = options.format
            let includeNotes = options.includeNotes
            let contacts = logbook.contacts
            do {
                let data: Data
                if format == .cabrillo {
                    // Only a contest log has a contest to write for.
                    guard let contest = ContestList.named(logbook.info.contest) else {
                        self.showMessage("This isn't a contest log.",
                                         details: "Cabrillo is for a contest entry. Start the log with File > New Contest Log… first.")
                        return
                    }
                    let myCall = Settings.currentProfile.station["station_callsign"] ?? ""
                    data = Data(Contest.cabrillo(contacts, contest: contest, myCall: myCall).utf8)
                } else if format == .dupeSheet {
                    // Headed with the contest's name and your call.
                    let name = ContestList.named(logbook.info.contest)?.name ?? logbook.info.name
                    let myCall = Settings.currentProfile.station["station_callsign"] ?? ""
                    data = Data(Contest.dupeSheet(contacts, contestName: name, myCall: myCall).utf8)
                } else {
                    data = format.data(for: contacts, includeNotes: includeNotes)
                }
                try data.write(to: url, options: .atomic)
            } catch {
                self.showMessage("The export didn't work.", details: error.localizedDescription)
                return
            }
            let count = contacts.count == 1 ? "1 contact" : "\(contacts.count) contacts"
            self.showMessage("Export finished.", details: "\(count) saved as \(url.lastPathComponent), "
                + "in \(url.deletingLastPathComponent().lastPathComponent). "
                + (includeNotes ? "Notes were included." : "Notes were left out."))
        }
    }

    // MARK: - Helpers

    // A list of at most 20 items, then "and 312 more", so a big file can't
    // make a summary too long to read.
    static func shortList(_ items: [String], separator: String) -> String {
        let shown = items.prefix(20).joined(separator: separator)
        return items.count > 20 ? "\(shown), and \(items.count - 20) more" : shown
    }

    // Your real Documents folder. (Inside the sandbox, the usual "home
    // folder" is the app's own container, so ask the system for the real
    // one.)
    var realDocumentsFolder: URL? {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: home)).appendingPathComponent("Documents")
    }
}

// The extra controls at the bottom of the Export dialog: a Format menu and
// an Include Notes checkbox. Changing the format changes the file name's
// ending to match (.adi, .adx or .csv).
@MainActor
final class ExportOptions: NSObject {
    private weak var panel: NSSavePanel?
    private let formatMenu = NSPopUpButton()
    private let notesBox = NSButton(checkboxWithTitle: "Include Notes", target: nil, action: nil)

    var format: ExportFormat { ExportFormat.allCases[max(formatMenu.indexOfSelectedItem, 0)] }
    var includeNotes: Bool { notesBox.state == .on }

    init(panel: NSSavePanel) {
        self.panel = panel
        super.init()
        formatMenu.addItems(withTitles: ExportFormat.allCases.map(\.title))
        formatMenu.setAccessibilityLabel("Format")
        formatMenu.target = self
        formatMenu.action = #selector(formatChanged(_:))
        notesBox.state = .off

        let row = NSStackView(views: [FieldLabel("Format"), formatMenu, notesBox])
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        panel.accessoryView = row
        // The dialog keeps its accessory view, and the view's menu keeps
        // this object as its target, but nothing else does. Tie this
        // object's life to the dialog's.
        objc_setAssociatedObject(panel, &ExportOptions.key, self, .OBJC_ASSOCIATION_RETAIN)

        formatChanged(nil)
    }

    private static var key = 0

    @objc private func formatChanged(_ sender: Any?) {
        guard let panel else { return }
        let format = self.format
        if let type = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        // "Solid Copy log 2026-11-14.adi"
        panel.nameFieldStringValue = "Solid Copy log \(QSO.fileDate.string(from: Date())).\(format.fileExtension)"
    }
}
