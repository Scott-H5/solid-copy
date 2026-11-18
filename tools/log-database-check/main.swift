// tools/log-database-check/main.swift (named main.swift because Swift
// only runs top-level code from a file with that name)
//
// Checks the log file code (Database, LogDatabase, QSO) on its own,
// without opening the app, using a throwaway log in a temporary folder.
// Run it with:  bash tools/check-log-database.sh
// Every line should start with PASS. It takes about 25 seconds, because
// it makes 23 backups a second apart to check that only 20 are kept.

import Foundation
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let url = dir.appendingPathComponent("Logbook.sqlite")
func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }
do {
  // A log file in the first layout (version 1), as saved before the extra
  // fields existed, must upgrade without losing anything.
  let oldURL = dir.appendingPathComponent("Old.sqlite")
  do {
    let old = try Database(url: oldURL)
    try old.execute("""
      CREATE TABLE qso (id TEXT PRIMARY KEY, call TEXT NOT NULL, qso_date TEXT NOT NULL, time_on TEXT NOT NULL,
        rst_sent TEXT NOT NULL DEFAULT '', rst_rcvd TEXT NOT NULL DEFAULT '', comment TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
      PRAGMA user_version = 1;
      INSERT INTO qso VALUES ('\(UUID().uuidString)', 'N3OLD', '20261114', '120000', '59', '58', 'old', 'old notes', 'x', 'x');
      """)
  }
  let upgraded = try LogDatabase(fileURL: oldURL)
  let oldContacts = try upgraded.loadAll()
  check(oldContacts.count == 1 && oldContacts[0].call == "N3OLD" && oldContacts[0].notes == "old notes"
        && oldContacts[0].rstReceived == "58", "a version 1 log upgrades and keeps its contacts")
  let columns = Set(try upgraded.columnNames())
  check(LogField.all.allSatisfy { columns.contains($0.adif) }, "every field in LogField.swift has a column after upgrading")

  var db: LogDatabase? = try LogDatabase(fileURL: url)
  check(try db!.count() == 0, "new log is empty")
  let t = Date(timeIntervalSince1970: 1794666725) // fixed moment
  let a = QSO(call: "W1AW", timeOn: t, rstSent: "59", rstReceived: "57", comment: "It's a \"quote\" test", notes: "private\nline two")
  let b = QSO(call: "K1ABC", timeOn: t.addingTimeInterval(60), rstSent: "599", rstReceived: "599", comment: "")
  var withFields = QSO(call: "VE3XYZ", timeOn: t.addingTimeInterval(30))
  for field in LogField.all { withFields[field.adif] = "value of \(field.adif)" }
  withFields["address"] = "1 Main St\nToronto"
  try db!.insert(a); try db!.insert(b)
  try db!.insert(withFields)
  let reloaded = try db!.loadAll().first { $0.id == withFields.id }
  check(reloaded == withFields, "all \(LogField.all.count) fields save and load, multi-line address included")
  try db!.delete(id: withFields.id)
  db = nil  // close, then reopen like a relaunch
  db = try LogDatabase(fileURL: url)
  let all = try db!.loadAll()
  check(all.count == 2, "both contacts survive reopening")
  check(all[0].id == a.id && all[0].call == "W1AW", "order and id kept")
  check(all[0].comment == a.comment && all[0].notes == a.notes, "comment with quotes and multi-line notes kept")
  check(all[0].timeOn == t && all[0].adifDate.count == 8 && all[0].adifTime.count == 6, "UTC time round-trips: \(all[0].adifDate) \(all[0].adifTime)")
  try db!.delete(id: a.id)
  check(try db!.loadAll().map(\.call) == ["K1ABC"], "delete removes only that contact")
  try db!.insert(all[0])
  check(try db!.count() == 2, "undo re-insert with same id works")
  var edited = all[0]
  edited.call = "W1AW/P"; edited.comment = "edited"; edited.notes = ""
  var b2 = try db!.loadAll()[1]; b2.notes = "kept in backups"; try db!.update(b2)
  edited.timeOn = t.addingTimeInterval(3600)
  try db!.update(edited)
  db = nil
  db = try LogDatabase(fileURL: url)
  let afterEdit = try db!.loadAll()
  check(afterEdit.count == 2, "edit doesn't add or remove contacts")
  check(afterEdit.last?.id == a.id && afterEdit.last?.call == "W1AW/P" && afterEdit.last?.comment == "edited",
        "edit is saved, and a later time moves the contact to the end")
  check(afterEdit.last?.notes == "", "notes can be cleared")
  for _ in 0..<23 { try db!.backUp(); Thread.sleep(forTimeInterval: 1.01) }
  let backups = try FileManager.default.contentsOfDirectory(atPath: db!.backupsFolder.path)
  check(backups.count == LogDatabase.backupsToKeep, "keeps \(backups.count) newest backups")
  let copy = try LogDatabase(fileURL: db!.backupsFolder.appendingPathComponent(backups.sorted().last!))
  check(try copy.loadAll() == db!.loadAll(), "backup is a full copy of every contact and field")
  check(QSO.date(adifDate: "20261114", adifTime: "1432") != nil, "ADIF 4-digit time accepted")
  // Integrity: a good backup passes SQLite's own check; a damaged file
  // doesn't, and isn't left behind by a backup.
  let newest = db!.backupsFolder.appendingPathComponent(backups.sorted().last!)
  check(LogDatabase.isIntact(newest), "a good backup passes SQLite's integrity check")
  let damaged = dir.appendingPathComponent("Damaged.sqlite")
  let bytes = try Data(contentsOf: newest)
  var broken = bytes
  for i in stride(from: 4096, to: broken.count, by: 97) { broken[i] = broken[i] ^ 0xFF }
  try broken.write(to: damaged)
  check(!LogDatabase.isIntact(damaged), "a damaged file fails the integrity check")
  check(!LogDatabase.isIntact(dir.appendingPathComponent("Missing.sqlite")), "a missing file fails the check")
} catch { print("FAIL error:", error); exit(1) }
