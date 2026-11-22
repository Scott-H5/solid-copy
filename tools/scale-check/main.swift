// tools/scale-check/main.swift
//
// How Solid Copy copes with a very big log. Fills a throwaway log with N
// made-up contacts (about 20 fields each, like a real logged contact),
// then times the things that matter and reports memory use:
//   saving them all, opening the log, a "worked before" check, a search
//   (first and second time), logging one more contact, and a backup.
//
// Run it with:  bash tools/scale-check.sh 100000

import Foundation

func residentMegabytes() -> Int {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Int(info.resident_size) / 1_048_576 : -1
}

func time(_ label: String, _ work: () throws -> Void) rethrows {
    let start = Date()
    try work()
    print(String(format: "%-38@ %8.2f s   memory %5d MB", label as NSString, Date().timeIntervalSince(start), residentMegabytes()))
}

MainActor.assumeIsolated {
    let count = Int(CommandLine.arguments[1]) ?? 100_000
    let url = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("Logbook.sqlite")
    print("\(count) contacts")
    do {
        let states = ["MD", "VA", "CT", "TX", "CA", "OH", "NY", "FL"]
        let bands = ["20m", "40m", "15m", "10m", "80m"]
        try time("make and save them all") {
            let database = try LogDatabase(fileURL: url)
            var batch: [QSO] = []
            for i in 0..<count {
                var q = QSO(call: "K\(i % 10)\(String(UnicodeScalar(65 + (i / 10) % 26)!))\(i % 997)",
                            timeOn: Date(timeIntervalSince1970: 900_000_000 + Double(i) * 60))
                q.name = "Operator \(i % 5000)"; q.rstSent = "599"; q.rstReceived = "599"
                q["band"] = bands[i % bands.count]; q["mode"] = "CW"; q["freq"] = "14.0\(i % 99)"
                q["state"] = states[i % states.count]; q["country"] = "United States"; q["dxcc"] = "291"
                q["gridsquare"] = "FM19\(i % 10)\(i % 7)"; q["qth"] = "Town \(i % 3000)"; q["cqz"] = "5"; q["ituz"] = "8"
                q["tx_pwr"] = "100"; q["station_callsign"] = "N0CALL"; q["my_gridsquare"] = "EM10"
                q["email"] = "op\(i)@example.org"; q.comment = i % 10 == 0 ? "nice signal" : ""
                q["skcc"] = i % 4 == 0 ? "\(i % 30000)S" : ""
                batch.append(q)
                if batch.count == 10_000 { try database.insertAll(batch); batch.removeAll(keepingCapacity: true) }
            }
            try database.insertAll(batch)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        print("log file size \(size / 1_048_576) MB")

        var logbook: Logbook!
        try time("open the log (load every contact)") { logbook = try Logbook(database: LogDatabase(fileURL: url)) }
        time("worked-before check for one call") { _ = logbook.contacts.filter { $0.call == "K5F123" }.count }
        // The same search as the log table: bytes, with memmem.
        func has(_ text: [UInt8], _ word: [UInt8]) -> Bool {
            text.withUnsafeBytes { h in word.withUnsafeBytes { n in memmem(h.baseAddress, h.count, n.baseAddress, n.count) != nil } }
        }
        let words = [Array("maryland".utf8), Array("town 12".utf8)]
        var texts: [[UInt8]] = []
        var matches = 0
        time("search, first time (builds search text)") {
            texts = logbook.contacts.map { Array(LogTableViewController_searchableText($0).utf8) }
            matches = texts.filter { t in words.allSatisfy { has(t, $0) } }.count
        }
        time("search, after that (cached text)") { matches = texts.filter { t in words.allSatisfy { has(t, $0) } }.count }
        print("  (\(matches) matches)")
        try time("log one more contact") { try logbook.add(QSO(call: "W1AW", timeOn: Date())) }
        time("reverse the list for the table (each change)") { _ = Array(logbook.contacts.reversed()) }
        try time("back up the log") { try LogDatabase(fileURL: url).backUp() }
    } catch {
        print("FAIL:", error)
        exit(1)
    }
}
