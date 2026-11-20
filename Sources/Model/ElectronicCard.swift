// ElectronicCard.swift
//
// Your electronic QSL card (CLAUDE.md, v1 item 10): a PDF the size of a
// paper card (5.5 by 3.5 inches) that confirms one contact, with real
// text VoiceOver reads, and a picture of your choosing behind it. QSL >
// Send QSL Card (LogTableViewController) makes one and hands it to Mail.
//
// What's on it, top to bottom, which is also the order it's read in:
//   N3BYY                                  your call, large
//   Scott / Anytown, PA / SKCC 12345       your lines (Settings > QSL Card)
//   Grid square: FN20.                     your fields you chose (my_...)
//   To Bob, W1AW                           their name, if chosen, and call
//   Date: 17 November 2026.  Time: 14:32 UTC.  Band: 40m.  ...
//                                          the contact's fields you chose,
//                                          in your order, one paragraph
//   Thanks for the contact.                its QSL message, or your usual one
//   73, N3BYY
//   Picture: a brass straight key.         what the picture shows, if set
//
// Why one column, and the contact as one paragraph: VoiceOver reads a
// PDF line by line across the page, so two columns side by side would be
// read interleaved, a line from each. One column reads in order. The
// paragraph keeps a full set of fields on a card-sized page.
//
// Why it's accessible beyond plain text: the PDF is tagged (headings,
// paragraphs, and the picture as a figure with your description as its
// alternative text), as accessible PDFs are. A reader that uses tags
// finds headings; one that doesn't still reads the text in order. The
// picture is faint (a quarter strength) so the text stays easy to see on
// any picture, and it's shrunk to at most 1600 pixels when chosen, so a
// card stays small enough to email.
//
// If the chosen fields don't fit, the text shrinks (to 70 per cent at
// most), then the card grows taller: nothing is ever cut off.

import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ElectronicCard {

    // A field that can go on the card: its id (an ADIF name), its name in
    // Settings > QSL Card, and its label on the card.
    struct Choice {
        let id: String
        let title: String
        let label: String
    }

    // Every field offered, in the order they start in. Yours ("My ...")
    // go with your details at the top; the rest describe the contact.
    static var choices: [Choice] {
        var list = [
            Choice(id: "name", title: "Their name, in the To line", label: ""),
            Choice(id: "qso_date", title: "Date", label: "Date"),
            Choice(id: "time_on", title: "Time (UTC)", label: "Time"),
            Choice(id: "band", title: "Band", label: "Band"),
            Choice(id: "freq", title: "Frequency", label: "Frequency"),
            Choice(id: "mode", title: "Mode", label: "Mode"),
            Choice(id: "rst_sent", title: "Signal report you gave them", label: "Your signal"),
            Choice(id: "rst_rcvd", title: "Signal report they gave you", label: "My signal"),
            Choice(id: "tx_pwr", title: "Your power", label: "My power"),
            Choice(id: "my_rig", title: "Your radio", label: "My radio"),
            Choice(id: "qslmsg", title: "Message", label: ""),
            Choice(id: "my_gridsquare", title: "Your grid square", label: "Grid square"),
            Choice(id: "my_cnty", title: "Your county", label: "County"),
            Choice(id: "my_state", title: "Your state", label: "State"),
            Choice(id: "my_pota_ref", title: "Your POTA park", label: "POTA park"),
            Choice(id: "my_sota_ref", title: "Your SOTA summit", label: "SOTA summit"),
            Choice(id: "my_wwff_ref", title: "Your WWFF reference", label: "WWFF"),
            Choice(id: "skcc", title: "Their SKCC number", label: "Your SKCC number"),
            Choice(id: "fists", title: "Their FISTS number", label: "Your FISTS number"),
            Choice(id: "app_solidcopy_licw", title: "Their LICW number", label: "Your LICW number"),
            Choice(id: "app_solidcopy_cwops", title: "Their CWops number", label: "Your CWops number"),
            Choice(id: "pota_ref", title: "Their POTA park", label: "Your POTA park"),
            Choice(id: "sota_ref", title: "Their SOTA summit", label: "Your SOTA summit"),
            Choice(id: "contest_id", title: "Contest", label: "Contest"),
        ]
        // Your own club fields, once named (Settings > Clubs).
        for slot in 1...LogField.clubSlots {
            let name = ClubNames.name(slot)
            if !name.isEmpty {
                list.append(Choice(id: "app_solidcopy_club\(slot)", title: "Their \(name)", label: "Your \(name)"))
            }
        }
        return list
    }

    static func choice(_ id: String) -> Choice? { choices.first { $0.id == id } }

    // On the card until you change it: what a paper card usually says.
    static let standardFields = ["name", "qso_date", "time_on", "band", "freq", "mode", "rst_sent", "tx_pwr",
                                 "qslmsg", "my_gridsquare"]

    struct Design: Equatable {
        var fields: [String]          // ids, in order
        var details: [String]         // your lines under your call
        var message: String           // when the contact has no QSL message
        var pictureDescription: String
        var hasPicture: Bool
    }

    enum Style { case call, detail, to, body, message, caption }

    struct Line: Equatable {
        var text: String
        var style: Style
    }

    // MARK: - What it says

    // The card's lines for a contact. `myCall` is the contact's station
    // callsign or, without one, your profile's.
    static func lines(for qso: QSO, design: Design, myCall: String) -> [Line] {
        let chosen = design.fields.compactMap(choice)
        let mine = chosen.filter { $0.id.hasPrefix("my_") && $0.id != "my_rig" }
        let theirs = chosen.filter { !$0.id.hasPrefix("my_") || $0.id == "my_rig" }
            .filter { $0.id != "name" && $0.id != "qslmsg" }

        var lines = [Line(text: myCall, style: .call)]
        for detail in design.details {
            let text = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { lines.append(Line(text: text, style: .detail)) }
        }
        let myFields = mine.compactMap(labelled(qso))
        if !myFields.isEmpty { lines.append(Line(text: myFields.joined(separator: "  "), style: .detail)) }

        let name = design.fields.contains("name") ? qso.name.trimmingCharacters(in: .whitespaces) : ""
        lines.append(Line(text: name.isEmpty ? "To \(qso.call)" : "To \(name), \(qso.call)", style: .to))
        let contact = theirs.compactMap(labelled(qso))
        if !contact.isEmpty { lines.append(Line(text: contact.joined(separator: "  "), style: .body)) }
        if design.fields.contains("qslmsg") {
            let own = qso["qslmsg"].trimmingCharacters(in: .whitespacesAndNewlines)
            let message = own.isEmpty ? design.message.trimmingCharacters(in: .whitespacesAndNewlines) : own
            if !message.isEmpty { lines.append(Line(text: message, style: .message)) }
        }
        lines.append(Line(text: "73, \(myCall)", style: .body))
        let picture = design.pictureDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if design.hasPicture, !picture.isEmpty {
            lines.append(Line(text: "Picture: " + picture + (picture.hasSuffix(".") ? "" : "."), style: .caption))
        }
        return lines
    }

    // "Band: 40m." for a field with a value; nil for an empty one.
    private static func labelled(_ qso: QSO) -> (Choice) -> String? {
        { choice in
            let value = Self.value(choice.id, of: qso)
            return value.isEmpty ? nil : "\(choice.label): \(value)" + (value.hasSuffix(".") ? "" : ".")
        }
    }

    // A field as a person writes it: "17 November 2026", "14:32 UTC",
    // "7.030 MHz", "5 W", "CW".
    static func value(_ id: String, of qso: QSO) -> String {
        switch id {
        case "qso_date": return QSL.spokenDate(qso.adifDate)
        case "time_on":
            let time = qso.utcTimeText
            return time.count == 4 ? "\(time.prefix(2)):\(time.suffix(2)) UTC" : time
        default: break
        }
        let value = qso[id].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        switch id {
        case "freq": return Double(value) == nil ? value : "\(value) MHz"
        case "tx_pwr": return Double(value) == nil ? value : "\(value) W"
        case "mode":
            let sub = qso["submode"].trimmingCharacters(in: .whitespaces)
            return sub.isEmpty || sub == value ? value : "\(value) (\(sub))"
        default: return value
        }
    }

    // The card as plain text, a line each: the email's own words, for
    // anyone whose mail can't show the PDF.
    static func text(_ lines: [Line]) -> String {
        lines.map(\.text).joined(separator: "\n")
    }

    // "W1AW 2026-11-14 1432.pdf". A "/" in a call (W1AW/P) would make a
    // folder, so it becomes "-".
    static func fileName(for qso: QSO) -> String {
        let call = qso.call.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "\(call) \(qso.utcDateText) \(qso.utcTimeText).pdf"
    }

    // The contact marked Card sent, by electronic means, dated today. A
    // contact already marked sent (a paper card, say) is left as it is.
    static func markedSent(_ qso: QSO, today: String) -> QSO {
        guard qso["qsl_sent"].uppercased() != "Y" else { return qso }
        var qso = qso
        qso["qsl_sent"] = "Y"
        qso["qslsdate"] = today
        qso["qsl_sent_via"] = "E"
        return qso
    }

    // MARK: - The picture

    static let mostPixels = 1600

    // Solid Copy's own picture, for anyone without one: a photo of a
    // J-38, the U.S. Army Signal Corps straight key of World War II that
    // many hams still use. Lou Sander released it into the public domain
    // (Wikimedia Commons, File:J38TelegraphKey.jpg; docs/CREDITS.md), so
    // it can go on any card with no credit line. It's 320 by 240 pixels:
    // fine faint behind the text, a little soft if printed large.
    static var builtInPicture: URL? { Bundle.main.url(forResource: "J38Key", withExtension: "jpg") }
    static let builtInDescription = "A J-38 straight key: a black base, a brass and steel lever, and a round "
        + "black knob"

    // A chosen picture, made ready for cards: at most 1600 pixels across,
    // as a JPEG. Throws, saying why, if the file isn't a picture.
    static func preparedPicture(from source: URL) throws -> Data {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: mostPixels]
        guard let image = CGImageSourceCreateWithURL(source as CFURL, nil),
              let picture = CGImageSourceCreateThumbnailAtIndex(image, 0, options as CFDictionary) else {
            throw DatabaseError(message: "\(source.lastPathComponent) isn't a picture Solid Copy can read.")
        }
        let data = NSMutableData()
        guard let out = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw DatabaseError(message: "The picture couldn't be made ready.")
        }
        CGImageDestinationAddImage(out, picture, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(out) else { throw DatabaseError(message: "The picture couldn't be made ready.") }
        return data as Data
    }

    static func picture(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - The PDF

    static let cardSize = CGSize(width: 396, height: 252)   // 5.5 by 3.5 inches
    private static let margin: CGFloat = 18

    static func pdf(_ lines: [Line], picture: CGImage?, pictureDescription: String, title: String,
                    author: String) -> Data {
        // The text, at the largest size (100 down to 70 per cent) that
        // fits; at 70 per cent the card grows taller instead.
        let width = cardSize.width - 2 * margin
        var scale: CGFloat = 1
        var blocks = layout(lines, scale: scale, width: width)
        while blocks.height > cardSize.height - 2 * margin, scale > 0.71 {
            scale -= 0.05
            blocks = layout(lines, scale: scale, width: width)
        }
        var box = CGRect(origin: .zero, size: CGSize(width: cardSize.width,
                                                     height: max(cardSize.height, blocks.height + 2 * margin)))

        let data = NSMutableData()
        let info: [CFString: Any] = [kCGPDFContextTitle: title, kCGPDFContextAuthor: author,
                                     kCGPDFContextCreator: "Solid Copy",
                                     kCGPDFContextSubject: text(lines)]
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary) else { return Data() }
        context.beginPDFPage(nil)
        CGPDFContextBeginTag(context, .document, [:] as CFDictionary)

        if let picture {
            // Fills the card, cropped to it, faint.
            let ratio = max(box.width / CGFloat(picture.width), box.height / CGFloat(picture.height))
            let size = CGSize(width: CGFloat(picture.width) * ratio, height: CGFloat(picture.height) * ratio)
            let rect = CGRect(x: (box.width - size.width) / 2, y: (box.height - size.height) / 2,
                              width: size.width, height: size.height)
            let description = pictureDescription.isEmpty ? "A picture" : pictureDescription
            CGPDFContextBeginTag(context, .figure,
                                 [CGPDFTagProperty.alternativeText: description as CFString] as CFDictionary)
            context.saveGState()
            context.clip(to: box)
            context.setAlpha(0.25)
            context.draw(picture, in: rect)
            context.restoreGState()
            CGPDFContextEndTag(context)
        } else {
            // A thin edge, so a printed card has a line to cut along.
            context.setStrokeColor(NSColor.gray.cgColor)
            context.setLineWidth(0.5)
            context.stroke(box.insetBy(dx: 4, dy: 4))
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        var top = box.height - margin
        for block in blocks.items {
            let tag: CGPDFTagType = switch block.style {
            case .call: .header1
            case .to: .header2
            default: .paragraph
            }
            CGPDFContextBeginTag(context, tag, [:] as CFDictionary)
            top -= block.height
            // Drawn with room to spare below, so a rounding difference
            // can never cut off its last line; the next block's place
            // comes from the measured height.
            block.text.draw(with: CGRect(x: margin, y: top - 40, width: width, height: block.height + 40),
                            options: [.usesLineFragmentOrigin, .usesFontLeading])
            top -= block.spaceAfter
            CGPDFContextEndTag(context)
        }
        NSGraphicsContext.restoreGraphicsState()

        CGPDFContextEndTag(context)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private struct Block {
        let text: NSAttributedString
        let style: Style
        let height: CGFloat
        let spaceAfter: CGFloat
    }

    // How tall text is at this width, measured by the same layout that
    // draws it (a quicker estimate came out a line short for long
    // italic text, and the last line was cut off).
    private static func measuredHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        return ceil(layout.usedRect(for: container).height)
    }

    // Each line set in its style and measured at this width.
    private static func layout(_ lines: [Line], scale: CGFloat, width: CGFloat) -> (items: [Block], height: CGFloat) {
        var items: [Block] = []
        var total: CGFloat = 0
        for (index, line) in lines.enumerated() {
            let font: NSFont = switch line.style {
            case .call: .boldSystemFont(ofSize: 26 * scale)
            case .detail: .systemFont(ofSize: 10 * scale)
            case .to: .boldSystemFont(ofSize: 13 * scale)
            case .body: .systemFont(ofSize: 10 * scale)
            case .message: NSFontManager.shared.convert(.systemFont(ofSize: 10 * scale), toHaveTrait: .italicFontMask)
            case .caption: .systemFont(ofSize: 7 * scale)
            }
            let text = NSAttributedString(string: line.text, attributes: [.font: font, .foregroundColor: NSColor.black])
            let height = measuredHeight(text, width: width)
            // A little room after your details and after the contact.
            let next = index + 1 < lines.count ? lines[index + 1].style : nil
            let space: CGFloat = next == nil ? 0 : (line.style != next && line.style != .call ? 6 : 2) * scale
            items.append(Block(text: text, style: line.style, height: height, spaceAfter: space))
            total += height + space
        }
        return (items, total)
    }
}
