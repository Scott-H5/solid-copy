// tools/backups-check/main.swift
//
// Checks copying backups to a second folder (BackupCopy.swift), in a
// temporary folder, with nothing of yours touched:
//   - the log backup arrives complete, named "Solid Copy log <date>.sqlite";
//   - only the newest 20 are kept there, and nothing else is removed;
//   - no half-written file is left;
//   - scanned cards are copied once, again only if changed, never deleted.
//
// Run it with:  bash tools/check-backups.sh

import Foundation

func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }

let files = FileManager.default
let work = files.temporaryDirectory.appendingPathComponent("backups-check-\(UUID().uuidString)")
defer { try? files.removeItem(at: work) }
let source = work.appendingPathComponent("Backups"), cards = work.appendingPathComponent("QSL Cards")
let target = work.appendingPathComponent("iCloud folder")
for folder in [source, cards, target] { try! files.createDirectory(at: folder, withIntermediateDirectories: true) }
func write(_ text: String, _ url: URL) { try! Data(text.utf8).write(to: url) }
func names(_ folder: URL) -> [String] { ((try? files.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() }

// One backup.
let first = source.appendingPathComponent("Logbook 2026-11-16 120000Z.sqlite")
write("log one", first)
write("card A", cards.appendingPathComponent("A.jpg"))
write("mine", target.appendingPathComponent("my notes.txt"))
var result = try! BackupCopy.copy(first, cards: cards, to: target)
check(result == BackupCopy.Result(logFile: "Solid Copy log 2026-11-16 120000Z.sqlite", cardsCopied: 1),
      "the backup and a new card copied: \(result)")
check((try? String(contentsOf: target.appendingPathComponent(result.logFile), encoding: .utf8)) == "log one",
      "the copy is complete")
check(!names(target).contains { $0.hasSuffix(".partial") }, "no half-written file left")
check(names(target.appendingPathComponent("QSL Cards")) == ["A.jpg"], "cards go in QSL Cards")

// Cards: copied once; again only when changed; never deleted.
result = try! BackupCopy.copy(first, cards: cards, to: target)
check(result.cardsCopied == 0, "an unchanged card isn't copied again")
write("card A, rescanned larger", cards.appendingPathComponent("A.jpg"))
try! files.removeItem(at: cards.appendingPathComponent("A.jpg"))
write("card A, rescanned larger", cards.appendingPathComponent("A.jpg"))
write("card B", cards.appendingPathComponent("B.jpg"))
result = try! BackupCopy.copy(first, cards: cards, to: target)
check(result.cardsCopied == 2, "a changed card and a new one are copied: \(result.cardsCopied)")
try! files.removeItem(at: cards.appendingPathComponent("B.jpg"))
_ = try! BackupCopy.copy(first, cards: cards, to: target)
check(names(target.appendingPathComponent("QSL Cards")) == ["A.jpg", "B.jpg"], "a card deleted from the log stays backed up")
check(try! BackupCopy.copy(first, cards: nil, to: target).cardsCopied == 0, "no cards folder: just the log")

// Only the newest 20 logs are kept; your own files are left alone.
for day in 1...25 {
    let backup = source.appendingPathComponent(String(format: "Logbook 2026-10-%02d 120000Z.sqlite", day))
    write("log \(day)", backup)
    _ = try! BackupCopy.copy(backup, cards: nil, to: target)
}
let logs = names(target).filter { $0.hasPrefix(BackupCopy.prefix) }
check(logs.count == 20, "the newest 20 kept: \(logs.count)")
check(logs.last == "Solid Copy log 2026-11-16 120000Z.sqlite" && logs.first == "Solid Copy log 2026-10-07 120000Z.sqlite",
      "the oldest went first")
check(names(target).contains("my notes.txt"), "other files in the folder are left alone")

// A folder that can't be written: an error, not a crash.
let missing = work.appendingPathComponent("not there")
check((try? BackupCopy.copy(first, cards: nil, to: missing)) == nil, "a missing folder is an error")
print("All backup checks passed.")
