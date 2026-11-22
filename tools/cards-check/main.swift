// tools/cards-check/main.swift
//
// Checks scanned QSL cards (QSLCards.swift):
//   - the call in a card's file name, and names that aren't calls;
//   - matching cards to contacts: one contact, none, several (the one
//     marked received, or left for you), already attached, two cards for
//     one contact;
//   - attaching: the copy, its name, the card's text, counted received;
//   - a card's file name can't point outside the QSL Cards folder;
//   - a search finds words on a card;
//   - your electronic card (ElectronicCard.swift): what it says, in what
//     order, that the PDF's text reads back whole and in that order,
//     the picture, a card too full for its size, and the Card sent mark;
//   - with the author's card folder and SQL log file (both only read): how
//     many attach, which don't, and why.
//
// Run it with:  bash tools/check-cards.sh

import AppKit
import PDFKit

func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }

MainActor.assumeIsolated {
    let work = URL(fileURLWithPath: CommandLine.arguments[1])
    let realCards = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let realLog = URL(fileURLWithPath: CommandLine.arguments[3])
    let fm = FileManager.default

    check(QSLCards.callsign(fromFileName: "w1aw.pdf") == "W1AW" && QSLCards.callsign(fromFileName: "W1AW 2.pdf") == "W1AW"
          && QSLCards.callsign(fromFileName: "VE3OXQ_1999.jpg") == "VE3OXQ", "calls from file names")
    check(QSLCards.callsign(fromFileName: "BRAZIL.pdf") == nil && QSLCards.callsign(fromFileName: "notes.pdf") == nil,
          "a name that isn't a call")

    // A small searchable PDF, made the way a scan with text is.
    let scans = work.appendingPathComponent("scans", isDirectory: true)
    try! fm.createDirectory(at: scans, withIntermediateDirectories: true)
    func makeCard(_ name: String, _ text: String) {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.string = text
        try! view.dataWithPDF(inside: view.bounds).write(to: scans.appendingPathComponent(name))
    }
    makeCard("W1AW.pdf", "W1AW Newington\nTnx QSO 73 Hiram")
    makeCard("K9ONE.pdf", "K9ONE")
    makeCard("K9TWO.pdf", "K9TWO")
    makeCard("K9TWO 2.pdf", "K9TWO again")
    makeCard("W1AW 2.pdf", "W1AW again")
    makeCard("K9MANY.pdf", "K9MANY")
    makeCard("N0NE.pdf", "nobody")
    makeCard("Brazil.pdf", "a country")
    try! Data("not a card".utf8).write(to: scans.appendingPathComponent("readme.txt"))

    func contact(_ call: String, _ offset: Double, received: Bool = false) -> QSO {
        var qso = QSO(call: call, timeOn: Date(timeIntervalSince1970: 1_000_000_000 + offset))
        if received { qso["qsl_rcvd"] = "Y"; qso["qslrdate"] = "20251217" }
        return qso
    }
    var attached = contact("K9ONE", 1)
    attached["app_solidcopy_qsl_card"] = "somefile.pdf"
    let contacts = [contact("W1AW", 0), attached, contact("K9TWO", 2), contact("K9TWO", 3, received: true),
                    contact("K9MANY", 4), contact("K9MANY", 5)]
    let files = try! fm.contentsOfDirectory(at: scans, includingPropertiesForKeys: nil)
    let match = QSLCards.match(files, to: contacts)
    check(match.cards.map { $0.file.lastPathComponent } == ["K9TWO.pdf", "W1AW.pdf"],
          "matched: one contact, and the one of two marked received (\(match.cards.map { $0.file.lastPathComponent }))")
    check(match.alreadyAttached == 1, "a contact with a card already is skipped")
    let why = match.unmatched.joined(separator: " | ")
    check(match.unmatched.count == 5 && why.contains("Brazil.pdf: the name isn't a callsign")
          && why.contains("N0NE.pdf: no contact with N0NE") && why.contains("K9MANY.pdf: K9MANY has 2 contacts")
          && why.contains("K9TWO 2.pdf: K9TWO has 2 contacts") && why.contains("W1AW 2.pdf: another card for the same contact"),
          "unmatched, each with why (no guessing between contacts): \(why)")

    // Attaching: copied in, named by the contact, its text, received.
    let logFile = work.appendingPathComponent("Logbook.sqlite")
    let cards = QSLCards(logFile: logFile)
    let w1aw = match.cards.first { $0.contact.call == "W1AW" }!
    let done = try! cards.attach(w1aw.file, to: w1aw.contact)
    check(done["app_solidcopy_qsl_card"] == "\(w1aw.contact.id.uuidString).pdf" && cards.file(for: done) != nil
          && fm.fileExists(atPath: w1aw.file.path), "the card is copied beside the log; the original stays")
    check(done["app_solidcopy_card_text"].contains("Tnx QSO 73 Hiram"), "the card's text is kept: \(done["app_solidcopy_card_text"])")
    check(done["qsl_rcvd"] == "Y" && done["qslrdate"].isEmpty, "counted received, with no made-up date")
    let k9two = match.cards.first { $0.contact.call == "K9TWO" }!
    check(try! cards.attach(k9two.file, to: k9two.contact)["qslrdate"] == "20251217", "an existing received date is kept")
    var sneaky = done
    sneaky["app_solidcopy_qsl_card"] = "../Logbook.sqlite"
    check(cards.file(for: sneaky) == nil, "a card name can't point outside the folder")
    check((try? cards.attach(scans.appendingPathComponent("readme.txt"), to: done)) == nil, "a text file isn't a card")
    check(LogTableViewController.searchableText(for: done).contains("hiram"), "a search finds words on the card")
    check(QSL.summary(done).contains("Scanned card attached"), "the QSL line says so: \(QSL.summary(done))")

    // Your electronic card (ElectronicCard.swift).
    var contact = QSO(call: "W1AW/P", timeOn: Date(timeIntervalSince1970: 1794666725))  // 14 Nov 2026 14:32 UTC
    for (field, value) in ["name": "Hiram", "band": "40m", "freq": "7.030", "mode": "CW", "rst_sent": "599",
                           "tx_pwr": "5", "my_gridsquare": "FN20", "skcc": "1", "email": "w1aw@example.org"] {
        contact[field] = value
    }
    let design = ElectronicCard.Design(fields: ["my_gridsquare", "name", "qso_date", "time_on", "band", "freq",
                                                "mode", "rst_sent", "rst_rcvd", "tx_pwr", "skcc", "qslmsg"],
                                       details: ["Sam", "", "SKCC 12345, FISTS 6789"],
                                       message: "Thanks for the contact.", pictureDescription: "a brass straight key",
                                       hasPicture: false)
    let lines = ElectronicCard.lines(for: contact, design: design, myCall: "N0CALL")
    let expected = ["N0CALL", "Sam", "SKCC 12345, FISTS 6789", "Grid square: FN20.", "To Hiram, W1AW/P",
                    "Date: 14 November 2026.  Time: 14:32 UTC.  Band: 40m.  Frequency: 7.030 MHz.  Mode: CW.  "
                    + "Your signal: 599.  My power: 5 W.  Your SKCC number: 1.",
                    "Thanks for the contact.", "73, N0CALL"]
    lines.map(\.text).filter { !expected.contains($0) }.forEach { print("       got: " + $0) }
    check(lines.map(\.text) == expected,
          "card: your call and lines, your fields, To with their name, the contact in order, the message, 73")
    check(!lines.contains { $0.text.contains("My signal") }, "card: an empty field (no report received) is left out")
    var ownMessage = contact
    ownMessage["qslmsg"] = "See you on 30m"
    check(ElectronicCard.lines(for: ownMessage, design: design, myCall: "N0CALL").contains { $0.text == "See you on 30m" },
          "card: the contact's own QSL message wins over the usual one")
    var noName = design
    noName.fields.removeAll { $0 == "name" || $0 == "qslmsg" }
    let plain = ElectronicCard.lines(for: contact, design: noName, myCall: "N0CALL").map(\.text)
    check(plain.contains("To W1AW/P") && !plain.contains("Thanks for the contact."),
          "card: name and message off leave them out")
    check(ElectronicCard.fileName(for: contact) == "W1AW-P 2026-11-14 1432.pdf", "card: file name, with no slash")

    // The PDF reads back as the same text, in the same order, on a
    // card-sized page.
    func pdfText(_ data: Data) -> (text: String, size: CGSize)? {
        guard let document = PDFDocument(data: data), document.pageCount == 1, let page = document.page(at: 0)
        else { return nil }
        return (page.string ?? "", page.bounds(for: .mediaBox).size)
    }
    func inOrder(_ text: String, _ lines: [String]) -> Bool {
        // Spaces and line breaks count alike: the text wraps on the card.
        func plain(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        var rest = Substring(plain(text))
        for line in lines {
            let want = plain(line)
            guard let found = rest.range(of: want) else {
                let common = zip(rest.split(separator: " "), want.split(separator: " ")).prefix { $0 == $1 }.count
                print("       not found in order: " + want.prefix(60) + "… (the text has: "
                      + rest.split(separator: " ").dropFirst(max(0, common - 3)).prefix(8).joined(separator: " ") + ")")
                return false
            }
            rest = rest[found.upperBound...]
        }
        return true
    }
    let pdf = ElectronicCard.pdf(lines, picture: nil, pictureDescription: "", title: "QSL card", author: "N0CALL")
    let read = pdfText(pdf)
    check(read?.size == ElectronicCard.cardSize, "card: one page, 5.5 by 3.5 inches")
    check(read.map { inOrder($0.text, expected) } == true, "card: the PDF's text reads back whole, in order")
    check(PDFDocument(data: pdf)?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "QSL card",
          "card: the PDF has a title")

    // A picture: made ready (shrunk, JPEG), drawn, and described.
    let big = NSImage(size: NSSize(width: 3000, height: 2000), flipped: false) { rect in
        NSColor.brown.setFill(); rect.fill(); return true
    }
    let pictureFile = work.appendingPathComponent("key.png")
    try! NSBitmapImageRep(data: big.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: pictureFile)
    let prepared = try! ElectronicCard.preparedPicture(from: pictureFile)
    let preparedFile = work.appendingPathComponent("Card Picture.jpg")
    try! prepared.write(to: preparedFile)
    let picture = ElectronicCard.picture(at: preparedFile)
    check(picture.map { max($0.width, $0.height) } == ElectronicCard.mostPixels, "card: a big picture is shrunk to 1600 pixels")
    let notPicture = work.appendingPathComponent("notes.png")
    try! Data("not a picture".utf8).write(to: notPicture)
    check((try? ElectronicCard.preparedPicture(from: notPicture)) == nil, "card: a file that isn't a picture is refused")
    var withPicture = design
    withPicture.hasPicture = true
    let pictureLines = ElectronicCard.lines(for: contact, design: withPicture, myCall: "N0CALL")
    let picturePDF = ElectronicCard.pdf(pictureLines, picture: picture, pictureDescription: "a brass straight key",
                                        title: "QSL card", author: "N0CALL")
    check(pictureLines.last?.text == "Picture: a brass straight key."
          && pdfText(picturePDF).map { inOrder($0.text, pictureLines.map(\.text)) } == true,
          "card: with a picture, the text still reads whole, ending with what the picture shows")
    check(picturePDF.count < 600_000, "card: with a picture, small enough to email (\(picturePDF.count / 1000) KB)")
    check(picturePDF.range(of: Data("StructTreeRoot".utf8)) != nil, "card: the PDF is tagged")

    // Solid Copy's own J-38 picture (macOS/J38Key.jpg, public domain:
    // docs/CREDITS.md): the very file checked when downloaded, ready to use.
    let j38 = URL(fileURLWithPath: "macOS/J38Key.jpg")
    check((try? Data(contentsOf: j38))?.count == 55_510, "card: the J-38 picture is the downloaded file")
    let j38Ready = (try? ElectronicCard.preparedPicture(from: j38)).flatMap { NSBitmapImageRep(data: $0) }
    check(j38Ready?.pixelsWide == 320 && j38Ready?.pixelsHigh == 240, "card: the J-38 picture is made ready, not enlarged")

    // Too much to fit: the text shrinks, then the card grows; nothing is lost.
    var full = design
    full.details = [String(repeating: "A long line about my station. ", count: 8), "Anytown", "SKCC 12345"]
    contact["qslmsg"] = String(repeating: "Thanks for a fine contact. ", count: 60)
    let fullLines = ElectronicCard.lines(for: contact, design: full, myCall: "N0CALL")
    let fullRead = pdfText(ElectronicCard.pdf(fullLines, picture: nil, pictureDescription: "", title: "", author: ""))
    check((fullRead?.size.height ?? 0) > ElectronicCard.cardSize.height
          && fullRead.map { inOrder($0.text, fullLines.map(\.text)) } == true,
          "card: too full for its size, it grows taller and keeps every word")

    // Marked sent, by electronic means; a paper card already sent stays.
    let sent = ElectronicCard.markedSent(contact, today: "20261117")
    check(sent["qsl_sent"] == "Y" && sent["qslsdate"] == "20261117" && sent["qsl_sent_via"] == "E",
          "card: marked Card sent, electronic, today")
    var paper = contact
    paper["qsl_sent"] = "Y"; paper["qslsdate"] = "20250101"; paper["qsl_sent_via"] = "B"
    check(ElectronicCard.markedSent(paper, today: "20261117") == paper, "card: a card already sent keeps its mark")
    var requested = contact
    requested["qsl_sent"] = "R"
    check(ElectronicCard.markedSent(requested, today: "20261117")["qsl_sent"] == "Y", "card: a request becomes sent")

    // The author's own cards and log, if they're here.
    guard fm.fileExists(atPath: realCards.path), fm.fileExists(atPath: realLog.path) else {
        return print("     (No card folder or SQL log file here: the real-cards checks were skipped.)")
    }
    let imported = try! LogImport.read(from: realLog).contacts
    let realFiles = try! fm.contentsOfDirectory(at: realCards, includingPropertiesForKeys: [.contentModificationDateKey],
                                                options: [.skipsHiddenFiles])
    let stamps = realFiles.map { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
    let real = QSLCards.match(realFiles, to: imported)
    print("     Real cards: \(realFiles.count) files, \(real.cards.count) matched, \(real.unmatched.count) not:")
    real.unmatched.forEach { print("       " + $0) }
    let realStore = QSLCards(logFile: work.appendingPathComponent("real").appendingPathComponent("Logbook.sqlite"))
    var newly = 0
    var withText = 0
    for (file, qso) in real.cards {
        let after = try! realStore.attach(file, to: qso)
        if qso["qsl_rcvd"] != "Y" { newly += 1 }
        if !after["app_solidcopy_card_text"].isEmpty { withText += 1 }
    }
    print("     \(newly) newly counted received; \(withText) with text")
    check(real.cards.count == 91 && real.unmatched.count == 6, "91 of the author's cards attach; 6 are left to sort by hand")
    check(newly == 34, "34 contacts newly counted as card received")
    let after = realFiles.map { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
    check(stamps == after, "the author's card folder wasn't changed")
}
