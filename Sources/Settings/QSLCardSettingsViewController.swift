// QSLCardSettingsViewController.swift
//
// Settings > QSL Card: what your electronic QSL card says and shows
// (ElectronicCard.swift; QSL > Send QSL Card makes one).
//   - Fields on the card: which, and in what order. The same list as
//     Logging Form: Space shows or hides, Option-Command-Up and Down move.
//     Yours ("Your grid square") go at the top with your details; theirs
//     describe the contact.
//   - Your details: up to three lines under your call, such as your name,
//     your town, and your club numbers ("SKCC 12345, FISTS 6789").
//   - Message: said on a card whose contact has no QSL message of its own
//     (the message field must be on the card).
//   - Picture: one picture behind the text (a straight key, your shack),
//     faint so the text stays clear, and a description of it. The
//     description is the picture's alternative text in the PDF and a
//     line at the end of the card, so everyone knows what's there.
//   - Use the J-38 Picture: Solid Copy's own photo of a J-38 straight
//     key (public domain, so no credit line), with its description, for
//     anyone without a picture of their own.
//   - Show Sample Card: a card for a made-up contact, opened in Preview,
//     to hear and see the result without sending anything.
// Text is saved on leaving a field (Escape saves too, then closes
// Settings).

import AppKit
import UniformTypeIdentifiers

@MainActor
final class QSLCardSettingsViewController: NSViewController, NSTextFieldDelegate {
    var onEscape: (() -> Void)?

    private var fieldList: ChoiceListViewController?
    private let listHolder = NSStackView()
    private let detailFields: [NSTextField] = (0..<3).map { _ in NSTextField(string: "") }
    private let messageField = NSTextField(string: "")
    private let descriptionField = NSTextField(string: "")
    private let pictureStatus = NSTextField(labelWithString: "")
    private let chooseButton = NSButton(title: "Choose Picture…", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove Picture", target: nil, action: nil)
    private let j38Button = NSButton(title: "Use the J-38 Picture", target: nil, action: nil)
    private let sampleButton = NSButton(title: "Show Sample Card", target: nil, action: nil)

    private static let detailTitles = ["Your name", "Your town or QTH", "Another line"]

    var firstControl: NSView? { fieldList?.list }

    override func loadView() {
        let heading = NSTextField(labelWithString: "Your QSL card")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        let note = NSTextField(wrappingLabelWithString:
            "QSL > Send QSL Card makes a card for the selected contact, as a PDF the size of a paper card, and "
            + "opens it in a new Mail message, addressed to them if their email is known. You send it. Your call "
            + "is at the top; choose what else the card says here.")
        note.preferredMaxLayoutWidth = 520

        listHolder.orientation = .vertical
        listHolder.alignment = .leading
        reloadList()

        var rows: [[NSView]] = []
        for (field, title) in zip(detailFields, Self.detailTitles) {
            rows.append(row(title, field, placeholder: title == "Another line" ? "SKCC 12345, FISTS 6789" : ""))
        }
        rows.append(row("Message, when the contact has none", messageField, placeholder: "none"))
        let grid = NSGridView(views: rows)
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.rowAlignment = .firstBaseline

        // Wraps like the notes: on one line it was 819 points wide, and
        // made Settings need 1,005 of a small screen's 1,024 (found by
        // tools/screen-size-check, 24 November 2026).
        pictureStatus.lineBreakMode = .byWordWrapping
        pictureStatus.usesSingleLineMode = false
        pictureStatus.cell?.wraps = true
        pictureStatus.maximumNumberOfLines = 0
        pictureStatus.preferredMaxLayoutWidth = 520
        let pictureHeading = NSTextField(labelWithString: "Picture")
        pictureHeading.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        chooseButton.target = self
        chooseButton.action = #selector(choosePicture(_:))
        removeButton.target = self
        removeButton.action = #selector(removePicture(_:))
        j38Button.target = self
        j38Button.action = #selector(useJ38(_:))
        j38Button.isEnabled = ElectronicCard.builtInPicture != nil
        sampleButton.target = self
        sampleButton.action = #selector(showSample(_:))
        let buttons = NSStackView(views: [chooseButton, j38Button, removeButton])
        buttons.spacing = 8
        let descriptionGrid = NSGridView(views: [row("What the picture shows", descriptionField,
                                                     placeholder: "a brass straight key")])
        descriptionGrid.rowAlignment = .firstBaseline

        let stack = NSStackView(views: [heading, note, listHolder, grid, pictureHeading, pictureStatus, buttons,
                                        descriptionGrid, sampleButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(24, after: grid)
        stack.setCustomSpacing(24, after: descriptionGrid)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        view = stack
        refresh()
    }

    private func row(_ title: String, _ field: NSTextField, placeholder: String) -> [NSView] {
        field.setAccessibilityLabel(title)
        field.placeholderString = placeholder
        field.delegate = self
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        return [FieldLabel(title), field]
    }

    // The field list, built again when a club field is named (its
    // choices change).
    func reloadList() {
        let chosen = Settings.cardFields
        let all = ElectronicCard.choices
        var items = chosen.compactMap { id in
            all.first { $0.id == id }.map { ChoiceListViewController.Item(id: $0.id, title: $0.title, shown: true,
                                                                           tabStop: false) }
        }
        items += all.filter { !chosen.contains($0.id) }.map {
            ChoiceListViewController.Item(id: $0.id, title: $0.title, shown: false, tabStop: false)
        }
        let list = ChoiceListViewController(items: items, listName: "Fields on the card",
                                            shownWord: "on the card", hiddenWord: "not on the card",
                                            offersTabStop: false)
        list.onChange = { used in Settings.cardFields = used.map(\.id) }
        list.onEscape = { [weak self] in self?.onEscape?() }
        fieldList?.view.removeFromSuperview()
        fieldList = list
        listHolder.addArrangedSubview(list.view)
        linkKeyViews()
    }

    // Tab order: the list, your lines, the message, the picture's
    // buttons and description, Show Sample Card, then round again.
    private func linkKeyViews() {
        guard let list = fieldList?.list else { return }
        let order: [NSView] = [list] + detailFields + [messageField, chooseButton, j38Button, removeButton, descriptionField,
                                                       sampleButton]
        for (index, view) in order.enumerated() { view.nextKeyView = order[(index + 1) % order.count] }
    }

    // Shows what's saved (when Settings opens).
    func refresh() {
        guard isViewLoaded else { return }
        for (field, line) in zip(detailFields, Settings.cardDetails) { field.stringValue = line }
        messageField.stringValue = Settings.cardMessage
        descriptionField.stringValue = Settings.cardPictureDescription
        showPicture()
    }

    private func showPicture() {
        let has = Settings.cardPictureFile != nil
        pictureStatus.stringValue = has ? "A picture is chosen."
            : "No picture: the card has a plain white background. Use the J-38 Picture puts Solid Copy's photo "
            + "of a J-38 straight key behind the text."
        removeButton.isEnabled = has
    }

    @objc private func choosePicture(_ sender: Any?) {
        guard let window = view.window, window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Picture"
        panel.message = "Choose a picture for the back of your card: a photo or drawing."
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.image]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url, self.savePicture(from: url) else { return }
            // Straight to its description, so the card's readers learn
            // what it shows.
            self.view.window?.makeFirstResponder(self.descriptionField)
            Speaker.announce("Picture chosen. Type what it shows, for everyone reading the card.")
        }
    }

    // Makes a picture ready and keeps it as the card's; false (said) if
    // it couldn't be.
    private func savePicture(from url: URL) -> Bool {
        do {
            let data = try ElectronicCard.preparedPicture(from: url)
            let folder = try LogList.baseFolder()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appendingPathComponent("Card Picture.jpg"), options: .atomic)
        } catch {
            NSSound.beep()
            Speaker.announce("Not chosen. \(error.localizedDescription)")
            return false
        }
        showPicture()
        return true
    }

    // Solid Copy's J-38 photo, with its description (replacing any
    // description of an earlier picture, which would now be wrong).
    @objc private func useJ38(_ sender: Any?) {
        guard let url = ElectronicCard.builtInPicture, savePicture(from: url) else { return }
        Settings.cardPictureDescription = ElectronicCard.builtInDescription
        descriptionField.stringValue = ElectronicCard.builtInDescription
        Speaker.announce("J-38 picture chosen, described as: \(ElectronicCard.builtInDescription).")
    }

    @objc private func removePicture(_ sender: Any?) {
        guard let url = Settings.cardPictureFile else { return }
        do { try FileManager.default.removeItem(at: url) } catch {
            NSSound.beep()
            return Speaker.announce("Not removed. \(error.localizedDescription)")
        }
        showPicture()
        view.window?.makeFirstResponder(chooseButton)
        Speaker.announce("Picture removed.")
    }

    // A card for a made-up contact, in Preview.
    @objc private func showSample(_ sender: Any?) {
        view.window?.makeFirstResponder(nil)   // saves the field you were in
        var qso = QSO(call: "W1AW", timeOn: Date())
        qso["name"] = "Hiram"
        qso["band"] = "40m"
        qso["freq"] = "7.030"
        qso["mode"] = "CW"
        qso["rst_sent"] = "599"
        qso["rst_rcvd"] = "579"
        qso["tx_pwr"] = "5"
        qso["skcc"] = "1"
        qso["fists"] = "1"
        let station = Settings.currentProfile.station
        qso["my_gridsquare"] = station["my_gridsquare"] ?? ""
        qso["my_cnty"] = station["my_cnty"] ?? ""
        qso["my_state"] = station["my_state"] ?? ""
        qso["my_rig"] = station["my_rig"] ?? ""
        let myCall = station["station_callsign"].flatMap { $0.isEmpty ? nil : $0 } ?? "N0CALL"
        let lines = ElectronicCard.lines(for: qso, design: Settings.cardDesign, myCall: myCall)
        let pdf = ElectronicCard.pdf(lines, picture: Settings.cardPictureFile.flatMap(ElectronicCard.picture(at:)),
                                     pictureDescription: Settings.cardPictureDescription,
                                     title: "Sample QSL card from \(myCall)", author: myCall)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Sample QSL Card.pdf")
        do { try pdf.write(to: url, options: .atomic) } catch {
            NSSound.beep()
            return Speaker.announce("The sample couldn't be made. \(error.localizedDescription)")
        }
        NSWorkspace.shared.open(url)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if let index = detailFields.firstIndex(of: field) {
            var details = Settings.cardDetails
            details[index] = field.stringValue
            Settings.cardDetails = details
        } else if field === messageField {
            Settings.cardMessage = field.stringValue
        } else if field === descriptionField {
            Settings.cardPictureDescription = field.stringValue
        }
    }

    // Escape saves the field you're in, then closes Settings.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        view.window?.makeFirstResponder(nil)
        onEscape?()
        return true
    }
}
