// QSLCards.swift
//
// Scanned QSL cards, kept with the log.
//
// Where they're kept: a "QSL Cards" folder beside the log file
// (Application Support/Solid Copy/QSL Cards), one file per contact, named
// by the contact's permanent ID ("8F3A….pdf"). A copy, so the originals
// can be moved or thrown away and nothing breaks, and not inside the log
// file, so the log stays small and its backups (one each launch) don't
// copy every card each time. Cards never change once scanned, so the
// folder is also easy to sync later.
//
// What the log keeps for a contact with a card (LogField.swift):
//   app_solidcopy_qsl_card   the file's name in the folder
//   app_solidcopy_card_text  the text the scan holds (searchable PDFs
//                            have it), so Command-F finds words on cards
// and the card counts as received (QSL_RCVD Y; its date, if any, is kept).
// What the other operator wrote goes in Their card's message (QSLMSG_RCVD),
// typed by you in Edit Contact.
//
// A folder of cards is matched to contacts by file name: "W1AW.pdf" (or
// "W1AW 2.pdf", "w1aw_1999.jpg") is W1AW's card. See match(_:to:).
//
// Removing a card from a contact leaves its file in the folder, so Undo
// can put it back; attaching a card to that contact again replaces it.

import Foundation
import PDFKit

struct QSLCards {
    let folder: URL

    // The folder beside a log file.
    init(logFile: URL) {
        folder = logFile.deletingLastPathComponent().appendingPathComponent("QSL Cards", isDirectory: true)
    }

    // The kinds of file a card can be: a PDF, or a picture.
    static let kinds: Set<String> = ["pdf", "jpg", "jpeg", "png", "heic", "tif", "tiff"]

    // At most this much of a card's text is kept (a card holds a few
    // hundred characters; this stops a mis-chosen 300-page PDF).
    static let mostText = 4_000

    // The card's file for a contact, if it has one and it's there.
    func file(for qso: QSO) -> URL? {
        let name = qso["app_solidcopy_qsl_card"]
        // Only a plain name in the folder, never a path elsewhere.
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { return nil }
        let url = folder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // Copies a card into the folder for a contact, and returns the contact
    // with the card, its text, and the card counted as received. Safe to
    // run away from the main thread (it touches only files).
    func attach(_ source: URL, to qso: QSO) throws -> QSO {
        let kind = source.pathExtension.lowercased()
        guard Self.kinds.contains(kind) else {
            throw DatabaseError(message: "\(source.lastPathComponent) isn't a PDF or a picture.")
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(qso.id.uuidString).\(kind)"
        let target = folder.appendingPathComponent(name)
        // Copied to a temporary name and then moved into place, so a copy
        // that fails half way never leaves a broken card.
        let partial = folder.appendingPathComponent(".\(name).partial")
        try? FileManager.default.removeItem(at: partial)
        try FileManager.default.copyItem(at: source, to: partial)
        _ = try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: partial, to: target)

        var updated = qso
        updated["app_solidcopy_qsl_card"] = name
        updated["app_solidcopy_card_text"] = kind == "pdf" ? Self.text(ofPDF: target) : ""
        if !["Y", "V"].contains(updated["qsl_rcvd"].uppercased()) { updated["qsl_rcvd"] = "Y" }
        return updated
    }

    // The text a PDF holds (a searchable scan has it), on one line per
    // line of the card, blank lines dropped, at most mostText characters.
    static func text(ofPDF url: URL) -> String {
        guard let document = PDFDocument(url: url), let raw = document.string else { return "" }
        let lines = raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return String(lines.joined(separator: "\n").prefix(mostText))
    }

    // MARK: - Matching a folder of cards to contacts

    struct Match {
        // A card and the contact it's for.
        var cards: [(file: URL, contact: QSO)] = []
        // Cards that weren't matched, each with why, for the summary.
        var unmatched: [String] = []
        // Cards for contacts that already have one (skipped).
        var alreadyAttached = 0
    }

    // The call a card's file name is for: up to the first space,
    // underscore or bracket ("W1AW 2.pdf", "w1aw_1999.pdf"). nil if that
    // isn't a callsign ("Brazil.pdf").
    static func callsign(fromFileName name: String) -> String? {
        let base = (name as NSString).deletingPathExtension
        let call = Callsign.normalized(String(base.prefix { !" _([".contains($0) }))
        return Callsign.looksValid(call) ? call : nil
    }

    // Matches card files to contacts by call. One contact with that call:
    // that one. Several: the one already marked card received, if only
    // one is (in Scott's log, cards entered by hand were marked);
    // otherwise it's left for you to attach from the log, as the file
    // can't say which. A contact that has a card already is skipped.
    static func match(_ files: [URL], to contacts: [QSO]) -> Match {
        var byCall: [String: [QSO]] = [:]
        for qso in contacts { byCall[Callsign.normalized(qso.call), default: []].append(qso) }
        var result = Match()
        var taken: Set<UUID> = []
        let cards = files.filter { kinds.contains($0.pathExtension.lowercased()) }
            // By name without its ending, so "W1AW.pdf" comes before
            // "W1AW 2.pdf" and the plain one is the contact's card.
            .sorted { $0.deletingPathExtension().lastPathComponent
                .localizedStandardCompare($1.deletingPathExtension().lastPathComponent) == .orderedAscending }
        for file in cards {
            let name = file.lastPathComponent
            guard let call = callsign(fromFileName: name) else {
                result.unmatched.append("\(name): the name isn't a callsign")
                continue
            }
            let all = byCall[call] ?? []
            guard !all.isEmpty else {
                result.unmatched.append("\(name): no contact with \(call)")
                continue
            }
            if all.allSatisfy({ !$0["app_solidcopy_qsl_card"].isEmpty }) {
                result.alreadyAttached += 1
                continue
            }
            let open = all.filter { $0["app_solidcopy_qsl_card"].isEmpty && !taken.contains($0.id) }
            if all.count == 1, open.isEmpty {
                result.unmatched.append("\(name): another card for the same contact")
                continue
            }
            // Several contacts: only the "marked received" rule picks one,
            // never "whichever is left", which would be a guess.
            let received = open.filter { ["Y", "V"].contains($0["qsl_rcvd"].uppercased()) }
            let chosen = all.count == 1 ? open.first : received.count == 1 ? received.first : nil
            guard let contact = chosen else {
                result.unmatched.append("\(name): \(call) has \(all.count) contacts; attach it from the log (QSL > Attach Card)")
                continue
            }
            taken.insert(contact.id)
            result.cards.append((file, contact))
        }
        return result
    }
}
