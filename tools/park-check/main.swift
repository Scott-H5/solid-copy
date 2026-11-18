// tools/park-check/main.swift
//
// Checks POTA's park list (ParkList.swift) and park search
// (ParkSearch.swift) with a small sample list, in a folder of its own:
//   - reading POTA's CSV, quotes and all;
//   - finding a park by reference, by part of its name, by state (in
//     words or as a code), and by the start of a reference;
//   - retired parks found by reference but not offered in a search;
//   - Down and Up going through matches, a single match taken on
//     leaving, and Return refusing a search that isn't a park yet.
// Given POTA's real list (a path after the folder), it also times
// building and searching it.
//
// Run it with:  bash tools/check-parks.sh

import AppKit

func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }

let sample = """
"reference","name","active","entityId","locationDesc","latitude","longitude","grid"
"US-1333","Big Pocono State Park","1","291","US-PA","41.0426","-75.3497","FN21hb"
"US-1334","Pocono Lake Preserve","1","291","US-PA","41.1","-75.4","FN21ga"
"US-0015","Chesapeake and Ohio Canal National Historical Park","1","291","US-DC,US-MD,US-WV","39.6","-77.8","FM19co"
"US-9999","Old Closed Park","0","291","US-PA","41","-75","FN21"
"IT-0631","Il ""Quarto"" di Barbarano Romano, Natura 2000","1","248","IT-LZ","42.2","12.0","JN62af"
"""

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let folder = URL(fileURLWithPath: CommandLine.arguments[1])
    let list = ParkList.shared
    list.fileURL = folder.appendingPathComponent("Parks.sqlite")
    check(!list.isAvailable && list.summary == "Not downloaded yet.", "no list to start with")

    let rows = CSV.rows(Data(sample.utf8))
    check(rows.count == 6 && rows[5][1] == "Il \"Quarto\" di Barbarano Romano, Natura 2000",
          "CSV: quoted commas and doubled quotes")
    check((try? ParkList.build(from: Data(sample.utf8), into: list.fileURL)) == 5, "the sample list is built: 5 parks")
    list.reopen()
    check(list.count == 5 && list.updated != nil && !list.isStale, "it's counted and dated")

    check(list.park("us-1333")?.spoken == "US-1333, Big Pocono State Park, Pennsylvania", "a park by its reference")
    check(list.park("US-0015")?.place == "District of Columbia, Maryland, West Virginia", "a park across three states")
    check(list.search("pocono").map(\.reference).sorted() == ["US-1333", "US-1334"], "by part of a name")
    check(list.search("big poc").map(\.reference) == ["US-1333"], "by the starts of two words")
    check(Set(list.search("pennsylvania").map(\.reference)) == ["US-1333", "US-1334"], "by state, in words")
    check(Set(list.search("PA").map(\.reference)) == ["US-1333", "US-1334"], "by state, as a code")
    check(list.search("US-13").map(\.reference) == ["US-1333", "US-1334"], "by the start of a reference")
    check(list.park("US-9999") != nil && list.search("closed").isEmpty, "a retired park: found, but not offered")
    check(list.search("\"; DROP TABLE park; --").isEmpty && list.count == 5, "search text is never taken as SQL")

    // The search field.
    let search = ParkSearch()
    let field = NSTextField(string: "pocono")
    search.textChanged(in: field)
    check(search.key(#selector(NSResponder.moveDown(_:)), in: field) && ["US-1333", "US-1334"].contains(field.stringValue),
          "Down goes to the first match: \(field.stringValue)")
    let first = field.stringValue
    _ = search.key(#selector(NSResponder.moveDown(_:)), in: field)
    check(field.stringValue != first && field.stringValue.hasPrefix("US-133"), "Down again goes to the next")
    _ = search.key(#selector(NSResponder.moveUp(_:)), in: field)
    check(field.stringValue == first, "Up goes back")
    check(!search.key(#selector(NSResponder.moveLeft(_:)), in: field), "other keys do what they usually do")

    field.stringValue = "pocono"
    search.textChanged(in: field)
    check(!search.resolve(field, label: "Their park") && field.stringValue == "pocono",
          "Return with two matches doesn't log, and keeps what's typed")
    field.stringValue = "big poc"
    search.textChanged(in: field)
    search.left(field)
    check(field.stringValue == "US-1333", "leaving with one match takes it")
    field.stringValue = "US-1333,chesapeake"
    check(search.resolve(field, label: "Their park") && field.stringValue == "US-1333,US-0015",
          "a two-fer: each part becomes a park")
    field.stringValue = "nowhere at all"
    check(!search.resolve(field, label: "Their park"), "no match: not logged")

    // POTA's real list, if given: how long it takes.
    if CommandLine.arguments.count > 2, let data = FileManager.default.contents(atPath: CommandLine.arguments[2]) {
        let start = Date()
        let count = (try? ParkList.build(from: data, into: list.fileURL)) ?? 0
        list.reopen()
        let built = Date().timeIntervalSince(start)
        check(count > 100_000, "POTA's list: \(count) parks, built in \(String(format: "%.1f", built)) s")
        let searchStart = Date()
        let found = list.search("big pocono")
        let took = Date().timeIntervalSince(searchStart) * 1_000
        check(found.first?.reference == "US-1333" && took < 50,
              "a search of the whole list: \(found.first?.spoken ?? "nothing"), in \(String(format: "%.1f", took)) ms")
        check(list.search("pennsylvania").count == ParkSearch.limit, "a broad search stops at \(ParkSearch.limit)")
    }
}
