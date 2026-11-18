// ParkSearch.swift
//
// Makes a text field a park search: their park on the logging form
// (POTA_REF) and your park in Settings > Profiles (MY_POTA_REF).
//
//   Type           a reference ("US-13"), part of a name ("big poc") or a
//                  state ("pennsylvania state"). After a pause, VoiceOver
//                  says how many parks match, or the park if only one does.
//   Down, Up       go through the matches (plain arrows: in a text field
//                  VoiceOver keeps VO-Up and VO-Down for its own reading). The field gets each one's
//                  reference, and VoiceOver says it in full: "US-1333, Big
//                  Pocono State Park, Pennsylvania. 1 of 3."
//   Leaving        a search with only one match becomes that park.
//   Return         (logging) a search that isn't a park yet stops the
//                  logging and says so, so a half-typed name is never
//                  logged as a park.
//
// A two-fer or more ("US-1333,US-1334") works too: the search is the part
// after the last comma.
//
// The controller that owns the field passes on its typing, keys and
// leaving (see LogEntryViewController and ProfilesViewController), and
// shows the line this gives it, if it has somewhere to.

import AppKit

@MainActor
final class ParkSearch {
    // The fields that hold POTA parks.
    static let fields: Set<String> = ["pota_ref", "my_pota_ref"]

    // Shows a line of text about the park, if the owner has a place for it.
    var show: ((String) -> Void)?

    // Per field: what was typed, and the matches being gone through.
    private struct Search {
        var typed: String
        var matches: [Park]?
        var index: Int?
    }
    private var searches: [ObjectIdentifier: Search] = [:]
    private var pause: Task<Void, Never>?
    // "Getting POTA's park list" is said once, not at each key.
    private var saidFetching = false

    // MARK: - From the owner

    // Typing in the field: a new search, said after a pause.
    func textChanged(in field: NSTextField) {
        let typed = Self.lastPart(of: field.stringValue)
        searches[ObjectIdentifier(field)] = Search(typed: typed)
        pause?.cancel()
        guard !typed.isEmpty else { return }
        guard ensureList(for: field) else { return }
        pause = Task { [weak self, weak field] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self, let field, !Task.isCancelled else { return }
            self.sayMatches(in: field)
        }
    }

    // Down and Up Arrow. Returns true if handled.
    func key(_ selector: Selector, in field: NSTextField) -> Bool {
        let down = selector == #selector(NSResponder.moveDown(_:))
        guard down || selector == #selector(NSResponder.moveUp(_:)) else { return false }
        let id = ObjectIdentifier(field)
        var search = searches[id] ?? Search(typed: Self.lastPart(of: field.stringValue))
        guard !search.typed.isEmpty else { return false }
        guard ensureList(for: field) else { return true }
        pause?.cancel()
        let matches = search.matches ?? ParkList.shared.search(search.typed)
        search.matches = matches
        guard !matches.isEmpty else {
            searches[id] = search
            NSSound.beep()
            Speaker.announce("No parks match \(search.typed).")
            return true
        }
        let next = (search.index ?? (down ? -1 : matches.count)) + (down ? 1 : -1)
        guard matches.indices.contains(next) else {
            NSSound.beep()
            Speaker.announce(down ? "Last match." : "First match.")
            return true
        }
        search.index = next
        searches[id] = search
        let park = matches[next]
        field.stringValue = Self.replacingLastPart(of: field.stringValue, with: park.reference)
        // The cursor at the end, so typing goes on from there.
        field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.utf16.count, length: 0)
        let more = matches.count == ParkSearch.limit ? " or more" : ""
        show?("Park: \(park.spoken). \(next + 1) of \(matches.count)\(more).")
        Speaker.announce("\(park.spoken). \(next + 1) of \(matches.count)\(more).")
        return true
    }

    // Leaving the field: a search with one match becomes that park, and
    // a park is said. Quietly does nothing without a list.
    func left(_ field: NSTextField) {
        pause?.cancel()
        guard ParkList.shared.isAvailable else { return }
        let parts = Self.parts(of: field.stringValue)
        guard let last = parts.last, ParkList.shared.park(last) == nil else {
            searches[ObjectIdentifier(field)] = nil
            return
        }
        let matches = ParkList.shared.search(last, limit: 2)
        guard matches.count == 1 else { return }
        field.stringValue = Self.replacingLastPart(of: field.stringValue, with: matches[0].reference)
        searches[ObjectIdentifier(field)] = nil
        show?("Park: \(matches[0].spoken).")
        Speaker.announce("Park \(matches[0].spoken).")
    }

    // Before logging (or saving): every part of the field must be a park.
    // One that's a search with a single match becomes it; otherwise this
    // says what's wrong and returns false. Without a list, anything goes.
    func resolve(_ field: NSTextField, label: String) -> Bool {
        guard ParkList.shared.isAvailable else { return true }
        var parts = Self.parts(of: field.stringValue)
        // A whole reference ("US-1333") is taken even if it's not in the
        // list: a park newer than the list, say.
        for (index, part) in parts.enumerated()
        where ParkList.shared.park(part) == nil && !Self.isReference(part) {
            let matches = ParkList.shared.search(part, limit: Self.limit)
            if matches.count == 1 {
                parts[index] = matches[0].reference
                continue
            }
            NSSound.beep()
            Speaker.announce(matches.isEmpty
                ? "\(label): no park matches \(part)."
                : "\(label): \(Self.countText(matches.count)) match \(part). Down Arrow goes through them.")
            return false
        }
        let joined = parts.joined(separator: ",")
        if joined != field.stringValue { field.stringValue = joined }
        return true
    }

    // MARK: - Helpers

    static let limit = 50

    // Without a list: fetch it, and say so once. Returns true if there's
    // a list to search now.
    private func ensureList(for field: NSTextField) -> Bool {
        let list = ParkList.shared
        if list.isAvailable { return true }
        if !saidFetching {
            saidFetching = true
            Speaker.announce("Getting POTA's park list. It takes a moment, once.")
        }
        list.update { [weak self, weak field] result in
            guard let self else { return }
            switch result {
            case .success(let count):
                Speaker.announce("Park list ready: \(count.formatted()) parks.")
                if let field, field.currentEditor() != nil { self.sayMatches(in: field) }
            case .failure(let error):
                self.saidFetching = false
                Speaker.announce("Couldn't get POTA's park list. \(error.localizedDescription)")
            }
        }
        return false
    }

    private func sayMatches(in field: NSTextField) {
        let id = ObjectIdentifier(field)
        guard var search = searches[id], !search.typed.isEmpty else { return }
        let matches = ParkList.shared.search(search.typed)
        search.matches = matches
        search.index = nil
        searches[id] = search
        if matches.count == 1 {
            show?("Park: \(matches[0].spoken).")
            return Speaker.announce("\(matches[0].spoken). Only match.")
        }
        let text = matches.isEmpty ? "No parks match." : "\(Self.countText(matches.count)) match. Down Arrow goes through them."
        show?(text)
        Speaker.announce(text)
    }

    // "1 park", "12 parks", "50 or more parks".
    private static func countText(_ count: Int) -> String {
        count >= limit ? "\(limit) or more parks" : count == 1 ? "1 park" : "\(count) parks"
    }

    // "US-1333", "K-12345": letters or digits, a dash, then 4 or 5 digits.
    nonisolated static func isReference(_ text: String) -> Bool {
        text.uppercased().range(of: #"^[A-Z0-9]{1,4}-[0-9]{4,5}$"#, options: .regularExpression) != nil
    }

    // The parts of a field, split at commas: "US-1333, US-1334".
    nonisolated static func parts(of text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func lastPart(of text: String) -> String {
        text.split(separator: ",", omittingEmptySubsequences: false).last
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    private static func replacingLastPart(of text: String, with value: String) -> String {
        var parts = text.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        if parts.isEmpty { return value }
        parts[parts.count - 1] = value
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ",")
    }
}
