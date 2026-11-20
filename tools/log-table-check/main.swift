// tools/log-table-check/main.swift
//
// Checks the log table on its own, with a throwaway log:
//   - contacts already in the log show when the table first opens (this
//     once failed: the table drew itself before it had the contacts);
//   - narrowing to one call (Option-Command-F), deleting inside it, and
//     showing everything again;
//   - selecting several, deleting them together, Undo and Redo;
//   - searching (Command-F);
//   - QSL: the summary line and words (QSL.swift), marking cards on a
//     selection (on, off, Undo, Redo) and the QSL filters;
//   - the Settings list for choosing form fields and columns: showing or
//     hiding leaves an item in place; moving swaps with the next in use;
//     QSL statuses can't go on the logging form.
//
// Run it with:  bash tools/check-log-table.sh

import AppKit
func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }
MainActor.assumeIsolated {
  _ = NSApplication.shared
  let book = try! Logbook(database: LogDatabase(fileURL: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("L.sqlite")))
  for i in 0..<3 { try! book.add(QSO(call: "K\(i)ABC", timeOn: Date(timeIntervalSince1970: 1794666725 + Double(i)))) }
  // A log that already has contacts when the window opens, as at launch.
  let table = LogTableViewController(logbook: book)
  let w = NSWindow(contentViewController: table); w.orderFrontRegardless(); w.layoutIfNeeded(); w.display()
  let tv = (table.view as! NSScrollView).documentView as! NSTableView
  check(tv.numberOfRows == 3, "contacts already in the log show when it opens (rows: \(tv.numberOfRows))")

  // Narrowing to one call.
  try! book.add(QSO(call: "K0ABC", timeOn: Date(timeIntervalSince1970: 1794666800)))
  check(table.showContacts(with: "K0ABC") == 2 && tv.numberOfRows == 2, "narrowed to K0ABC's 2 contacts")
  try! book.remove(at: book.index(of: table.selectedContact!.id)!)
  check(tv.numberOfRows == 1 && table.callFilter == "K0ABC", "deleting inside the narrowed log keeps it narrowed")
  table.showAllContacts()
  check(tv.numberOfRows == 3 && table.callFilter == nil, "showing everything again")

  // Deleting several at once, then Undo and Redo. Two of them are exact
  // repeats (same call and time), like some imported entries.
  let repeatTime = Date(timeIntervalSince1970: 1794667000)
  try! book.add(QSO(call: "VE3OXQ", timeOn: repeatTime))
  try! book.add(QSO(call: "VE3OXQ", timeOn: repeatTime))
  check(tv.numberOfRows == 5, "five contacts before deleting")
  w.makeFirstResponder(tv)
  tv.selectRowIndexes(IndexSet([0, 1, 2]), byExtendingSelection: false)
  check(table.selectionCount == 3 && table.selectedContact == nil, "three selected; no single contact")
  table.deleteContact(nil)
  check(tv.numberOfRows == 2 && book.contacts.count == 2, "Delete removes all three")
  w.undoManager?.undo()
  check(tv.numberOfRows == 5 && book.contacts.filter { $0.call == "VE3OXQ" }.count == 2 && table.selectionCount == 3,
        "Undo puts all three back, repeats included, and selects them")
  w.undoManager?.redo()
  check(book.contacts.count == 2, "Redo deletes them again")

  // Search (Command-F): every word, any field, not case-sensitive, with
  // states spelled out.
  var md = QSO(call: "N1SG", timeOn: Date(timeIntervalSince1970: 1794668000)); md.name = "Steve"; md["state"] = "MD"
  md["skcc"] = "27757S"
  var ct = QSO(call: "W1AW", timeOn: Date(timeIntervalSince1970: 1794668100)); ct.name = "Hiram"; ct["state"] = "CT"
  ct.notes = "Club station"
  try! book.add(md); try! book.add(ct)
  check(table.search("maryland") == 1 && table.selectedContact?.call == "N1SG", "a state's name finds its code")
  check(table.search("n1 steve") == 1, "every word must match")
  check(table.search("CLUB") == 1 && table.selectedContact?.call == "W1AW", "notes are searched, any case")
  check(table.search("27757") == 1, "club numbers are searched")
  check(table.search("zzz") == 0 && tv.numberOfRows == 0 && table.searchFilter == "zzz", "no matches: the search stays, so it can be changed")
  check(table.search("") == book.contacts.count && table.filter == nil, "an empty search shows everything")

  // QSL: the summary line, in words.
  var q = QSO(call: "VE3OXQ", timeOn: Date(timeIntervalSince1970: 1794669000))
  check(QSL.summary(q) == "Not confirmed." && !QSL.isConfirmed(q), "nothing yet: not confirmed")
  q["qsl_rcvd"] = "Y"; q["qslrdate"] = "20251217"; q["lotw_qsl_rcvd"] = "Y"; q["lotw_qslrdate"] = "20220423"
  q["qsl_sent"] = "Y"; q["qslsdate"] = "20261112"; q["qsl_sent_via"] = "B"
  q["lotw_qsl_sent"] = "Y"; q["qrzcom_qso_upload_status"] = "Y"
  check(QSL.summary(q) == "Confirmed: card 17 December 2025, LoTW 23 April 2022. Card sent 12 November 2026 by bureau. "
        + "Uploaded to QRZ Logbook.", "a full summary: \(QSL.summary(q))")
  check(QSL.display(field: "qsl_rcvd", value: "Y") == "Yes" && QSL.display(field: "qsl_sent_via", value: "d") == "Direct"
        && QSL.display(field: "qslrdate", value: "20251217") == "17 December 2025"
        && QSL.display(field: "qslrdate", value: "soon") == "soon" && QSL.display(field: "name", value: "Y") == "Y",
        "QSL fields in words; anything else as it is")
  let details = ContactDetailsViewController.lines(for: q)
  check(details[3].label == "QSL" && details.contains { $0 == ("Card received", "Yes") }, "the details panel has the QSL line")

  // Marking from the log: three selected, Card Sent, then again (off),
  // then Undo and Redo.
  table.showAllContacts()
  w.makeFirstResponder(tv)
  tv.selectRowIndexes(IndexSet([0, 1, 2]), byExtendingSelection: false)
  check(table.selectionCount == 3, "three selected for marking")
  let today = QSL.today()
  w.undoManager?.groupsByEvent = false
  w.undoManager?.beginUndoGrouping(); table.markCardSent(nil); w.undoManager?.endUndoGrouping()
  let sent = book.contacts.filter { $0["qsl_sent"] == "Y" && $0["qslsdate"] == today }
  check(sent.count == 3 && table.selectionCount == 3, "Card Sent marks all three, dated today, still selected")
  w.undoManager?.beginUndoGrouping(); table.markCardSent(nil); w.undoManager?.endUndoGrouping()
  check(book.contacts.allSatisfy { $0["qsl_sent"].isEmpty && $0["qslsdate"].isEmpty }, "again on all three takes it off")
  w.undoManager?.undo()
  check(book.contacts.filter { $0["qsl_sent"] == "Y" }.count == 3, "Undo puts the marks back")
  w.undoManager?.redo()
  check(book.contacts.allSatisfy { $0["qsl_sent"].isEmpty }, "Redo takes them off again")
  // Back to the usual undo grouping, as in the app.
  w.undoManager?.groupsByEvent = true

  // Card Requested on one, then the filter; Card Sent on it empties the
  // filter, so the whole log shows again.
  tv.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  guard let asker = table.selectedContact?.call else {
    return check(false, "one contact selected (\(table.selectionCount) selected, \(tv.numberOfRows) rows)")
  }
  table.markCardRequested(nil)
  check(table.showContacts(.cardRequested) == 1 && tv.numberOfRows == 1 && table.qslFilter == .cardRequested,
        "Show Card Requests: just \(asker)")
  table.markCardSent(nil)
  check(table.qslFilter == nil && tv.numberOfRows == book.contacts.count, "the last request sent: the whole log again")
  check(book.contacts.first { $0.call == asker }?["qsl_sent"] == "Y", "the request became a card sent")

  // Confirmed and not confirmed.
  tv.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
  table.markCardReceived(nil)
  check(table.showContacts(.confirmed) == 1 && table.showContacts(.notConfirmed) == book.contacts.count - 1,
        "Show Confirmed and Show Not Confirmed")
  table.showAllContacts()
  check(table.showContacts(.confirmed) == 1, "a filter with matches")
  book.contacts.filter(QSL.Filter.confirmed.matches).forEach { var c = $0; c["qsl_rcvd"] = ""; c["qslrdate"] = ""; _ = try? book.updateAll([c]) }
  check(table.showContacts(.confirmed) == 0, "no matches: nothing changes")

  // The choice list (Settings > Logging Form and Log Columns).
  typealias Item = ChoiceListViewController.Item
  let choices = ChoiceListViewController(items: [
    Item(id: "name", title: "Name", shown: true, tabStop: true), Item(id: "rst_sent", title: "RST sent", shown: true, tabStop: true),
    Item(id: "grid", title: "Grid", shown: false, tabStop: true), Item(id: "state", title: "State", shown: false, tabStop: true),
  ], listName: "Fields", shownWord: "on the form", hiddenWord: "not on the form", offersTabStop: true)
  var used: [String] = []
  choices.onChange = { used = $0.map(\.id) }
  let cw = NSWindow(contentViewController: choices); cw.layoutIfNeeded()
  let ctv = choices.list as! NSTableView
  ctv.selectRowIndexes(IndexSet(integer: 3), byExtendingSelection: false)
  choices.toggleShown(nil)
  check(used == ["name", "rst_sent", "state"] && ctv.selectedRow == 3 && choices.selectedItem?.id == "state",
        "showing an item leaves it where it is (row \(ctv.selectedRow)), last on the form")
  choices.moveItemUp(nil)
  check(used == ["name", "state", "rst_sent"] && choices.selectedItem?.id == "state",
        "Move Up swaps with the next item in use above, past hidden ones: \(used)")
  ctv.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  choices.toggleShown(nil)
  check(used == ["state", "rst_sent"] && ctv.selectedRow == 0 && choices.selectedItem?.id == "name",
        "hiding an item leaves it where it is too")
  check(LogField.named("name")!.canGoOnForm && !LogField.named("lotw_qsl_rcvd")!.canGoOnForm
        && !LogField.named("qslrdate")!.canGoOnForm && !LogField.named("app_solidcopy_qsl_card")!.canGoOnForm
        && LogField.named("qsl_via")!.canGoOnForm && !LogField.named("address")!.canGoOnForm,
        "QSL statuses, dates and the card file can't go on the logging form; QSL via can")
  check(LogField.named("notes")!.canGoOnForm && LogField.named("notes")!.label == "QSO notes"
        && LogField.named("notes")!.multiline,
        "QSO notes go on the logging form (one line there), named QSO notes; Address stays off")
  // Edit Contact's QSL menus and dates (16 November 2026).
  check(QSL.choices(for: "lotw_qsl_rcvd")?.map(\.value) == ["", "Y", "N", "R", "Q", "I", "V"]
        && QSL.choices(for: "qsl_rcvd_via")?.first?.title == "Not set"
        && QSL.choices(for: "qsl_sent_via")?.map(\.title).contains("Bureau") == true
        && QSL.choices(for: "name") == nil, "QSL statuses and via have menu choices in words; other fields don't")
  check(QSL.readableDate("20251217") == "2025-12-17" && QSL.readableDate("") == "" && QSL.readableDate("soon") == "soon",
        "QSL dates shown as 2025-12-17")
  check(QSL.adifDate(typed: "2025-12-17") == "20251217" && QSL.adifDate(typed: "2025/12/17") == "20251217"
        && QSL.adifDate(typed: " 20251217 ") == "20251217" && QSL.adifDate(typed: "") == "",
        "typed QSL dates back to ADIF's form")
  check(QSL.adifDate(typed: "2025-02-30") == nil && QSL.adifDate(typed: "17 Dec 2025") == nil
        && QSL.adifDate(typed: "2025-12-1") == nil, "not real days are refused")
}
