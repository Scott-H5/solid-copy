// QSLCardFolder.swift
//
// QSL > Attach Cards from a Folder…: choose a folder of scanned cards,
// each named by callsign ("W1AW.pdf"), and Solid Copy attaches each to its
// contact (QSLCards.swift has the rules), copying it into the log's QSL
// Cards folder. The folder you chose isn't changed. Then a summary says
// how many were attached, how many newly counted as received, and which
// cards weren't matched, and why, so you can attach those from the log
// (QSL > Attach Card…). Edit > Undo takes the whole lot back off.
//
// More of the AppDelegate class, like ImportExport.swift.

import AppKit

extension AppDelegate {

    @objc func attachCardFolder(_ sender: Any?) {
        guard let window, window.attachedSheet == nil, logbook != nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Attach QSL Cards"
        panel.message = "Choose a folder of scanned cards, each named by callsign, such as W1AW.pdf."
        panel.prompt = "Attach"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = realDocumentsFolder?.deletingLastPathComponent().appendingPathComponent("Downloads")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.attachCards(in: url)
        }
    }

    private func attachCards(in folder: URL) {
        guard let logbook else { return }
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                options: [.skipsHiddenFiles])
        } catch {
            return showMessage("Couldn't read that folder.", details: error.localizedDescription)
        }
        let match = QSLCards.match(files, to: logbook.contacts)
        guard !match.cards.isEmpty else {
            return showMessage("No cards were attached.", details: summary(match, attached: [], newlyReceived: 0))
        }
        do { try logbook.backUp() } catch {
            return showMessage("No cards were attached.", details: "The log couldn't be backed up first. "
                + error.localizedDescription)
        }
        Speaker.announce("Attaching \(match.cards.count) cards…")
        // Copying and reading the cards is file work, so it's done away
        // from the main thread; the log is changed back on it, in one step.
        let cards = QSLCards(logFile: logbook.fileURL)
        let work = match.cards
        Task { [weak self] in
            let (updated, failed) = await Task.detached { () -> ([QSO], [String]) in
                var updated: [QSO] = []
                var failed: [String] = []
                for (file, contact) in work {
                    do { updated.append(try cards.attach(file, to: contact)) } catch {
                        failed.append("\(file.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                return (updated, failed)
            }.value
            var finished = match
            finished.unmatched += failed
            self?.finishAttaching(updated, match: finished)
        }
    }

    private func finishAttaching(_ updated: [QSO], match: QSLCards.Match) {
        guard let logbook else { return }
        let before = Dictionary(uniqueKeysWithValues: match.cards.map { ($0.contact.id, $0.contact) })
        let newlyReceived = updated.filter { !["Y", "V"].contains(before[$0.id]?["qsl_rcvd"].uppercased() ?? "") }.count
        let old: [QSO]
        do { old = try logbook.updateAll(updated) } catch {
            return showMessage("The cards weren't attached.", details: error.localizedDescription)
        }
        registerCardUndo(old: old, new: updated)
        showMessage("Cards attached.", details: summary(match, attached: updated, newlyReceived: newlyReceived)
            + "\n\nThe folder you chose wasn't changed. Edit > Undo takes the cards back off.")
    }

    // Undo puts the contacts back as they were; Redo attaches again. The
    // card files stay in the folder either way.
    private func registerCardUndo(old: [QSO], new: [QSO]) {
        guard let undoManager = window?.undoManager else { return }
        undoManager.registerUndo(withTarget: self) { delegate in
            guard (try? delegate.logbook?.updateAll(old)) != nil else {
                return Speaker.announce("Couldn't undo attaching the cards.")
            }
            delegate.registerCardUndo(old: new, new: old)
            Speaker.announce("\(undoManager.isUndoing ? "Undone" : "Redone"): \(new.count) cards.")
        }
        undoManager.setActionName("Attach Cards")
    }

    private func summary(_ match: QSLCards.Match, attached: [QSO], newlyReceived: Int) -> String {
        var lines: [String] = []
        lines.append(attached.count == 1 ? "1 card was attached." : "\(attached.count) cards were attached.")
        if newlyReceived > 0 {
            lines.append("\(newlyReceived) of those contacts weren't marked card received before; now they are.")
        }
        if match.alreadyAttached > 0 {
            lines.append("\(match.alreadyAttached) already had a card, so were skipped.")
        }
        if !match.unmatched.isEmpty {
            lines.append("\(match.unmatched.count) weren't attached:\n"
                + match.unmatched.prefix(40).joined(separator: "\n")
                + (match.unmatched.count > 40 ? "\nand \(match.unmatched.count - 40) more." : ""))
        }
        return lines.joined(separator: "\n\n")
    }
}
