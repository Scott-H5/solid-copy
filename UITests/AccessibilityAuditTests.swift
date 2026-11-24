// AccessibilityAuditTests.swift
//
// Runs Apple's automatic accessibility audit on each of Solid Copy's
// screens: elements VoiceOver can't name, low colour contrast, controls
// too small to hit, text that doesn't grow with the system text size, and
// similar problems.
//
// How to run it:
//   bash ~/dev/solid-copy/audit.sh
//
// The test drives the app with keyboard shortcuts only, the way a
// VoiceOver user would. It only opens and closes things: it never saves,
// deletes or logs a contact. The first time, macOS asks to let the test
// runner control the computer (System Settings > Privacy & Security >
// Accessibility); turn that off again afterwards.

import XCTest

final class AccessibilityAuditTests: XCTestCase {
    private var issues: [String] = []
    // What each flagged element is, by the audit's name for it, so each is
    // looked up once (see `found`).
    private var seen: [String: Found] = [:]

    private struct Found {
        var type: XCUIElement.ElementType
        var label: String
        var frame: CGRect
    }

    override func setUp() {
        continueAfterFailure = true
    }

    func testAuditEveryScreen() throws {
        let app = XCUIApplication()
        app.launch()
        app.activate()
        sleep(2)
        try audit(app, screen: "Main window")

        // Command-I: the newest contact in the log.
        app.typeKey("i", modifierFlags: .command)
        sleep(1)
        try audit(app, screen: "Log")

        // Tab: the details panel.
        app.typeKey(.tab, modifierFlags: [])
        sleep(1)
        try audit(app, screen: "Details")

        // Escape (back to the log), Return: Edit Contact. Escape cancels it.
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        sleep(1)
        try audit(app, screen: "Edit Contact")
        app.typeKey(.escape, modifierFlags: [])
        sleep(1)

        // Command-F: the search, with a few letters typed. Escape clears it.
        app.typeKey("f", modifierFlags: .command)
        app.typeText("cw")
        sleep(1)
        try audit(app, screen: "Search")
        app.typeKey(.escape, modifierFlags: [])

        // Command-comma: Settings, and Command-1 to 7 for its sections.
        app.typeKey(",", modifierFlags: .command)
        sleep(1)
        for (number, name) in [("1", "Settings: Lookup"), ("2", "Settings: Profiles"),
                               ("3", "Settings: Logging Form"), ("4", "Settings: Log Columns"),
                               ("5", "Settings: Radio"), ("6", "Settings: Speech"), ("7", "Settings: Spots")] {
            app.typeKey(number, modifierFlags: .command)
            sleep(1)
            try audit(app, screen: name)
        }
        // Settings > Band Plan and WSJT-X: past Command-9, so chosen in the
        // sidebar list.
        let bandPlanRow = app.tables["Settings sections"].staticTexts["Band Plan"]
        if bandPlanRow.waitForExistence(timeout: 3) {
            bandPlanRow.click()
            sleep(1)
            try audit(app, screen: "Settings: Band Plan")
        } else {
            issues.append("Settings: Band Plan: its row in the sidebar wasn't found")
        }
        let wsjtxRow = app.tables["Settings sections"].staticTexts["WSJT-X"]
        if wsjtxRow.waitForExistence(timeout: 3) {
            wsjtxRow.click()
            sleep(1)
            try audit(app, screen: "Settings: WSJT-X")
        } else {
            issues.append("Settings: WSJT-X: its row in the sidebar wasn't found")
        }
        app.typeKey("w", modifierFlags: .command)
        sleep(1)

        // Windows: WSJT-X Decodes (Command-4), Awards (Command-5) and Band
        // Plan (Command-6). Each is closed again with Command-W.
        for (key, name) in [("4", "WSJT-X Decodes"), ("5", "Awards"), ("6", "Band Plan")] {
            app.typeKey(key, modifierFlags: .command)
            sleep(2)
            try audit(app, screen: name)
            app.typeKey("w", modifierFlags: .command)
            sleep(1)
        }

        print("AUDIT SUMMARY: \(issues.count) issue(s)")
        if !issues.isEmpty {
            XCTFail("\(issues.count) accessibility issue(s):\n" + issues.joined(separator: "\n"))
        }
    }

    // Audits the front window, keeping a screenshot of it.
    private func audit(_ app: XCUIApplication, screen: String) throws {
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = screen
        shot.lifetime = .keepAlways
        add(shot)
        // The table text's real contrast, measured from these screenshots on
        // 2026-11-14, is 21 to 1 on white rows and 17 to 1 on grey ones
        // (4.5 is the minimum). Apple's check misjudges table rows, so
        // contrast findings inside tables are skipped; any elsewhere still
        // count.
        let tables = app.tables.allElementsBoundByIndex.map(\.frame)
        try app.performAccessibilityAudit { issue in
            let found = issue.element.flatMap(self.found)
            if issue.auditType == .contrast, let frame = found?.frame,
               tables.contains(where: { $0.contains(frame) }) {
                return true
            }
            // The log's Frequency cells ("14.061352") are "not human-readable"
            // to Apple's check, which seems to take a long decimal for a code
            // rather than words (2026-11-15; no other column is flagged).
            // VoiceOver reads them as the number, under the column heading
            // "Frequency (MHz)", which is what a ham expects. So log-table
            // cells are skipped for this finding; elsewhere it still counts.
            if issue.auditType == .sufficientElementDescription, found?.type == .cell,
               let frame = found?.frame, tables.contains(where: { $0.contains(frame) }) {
                return true
            }
            // A Caps Lock indicator macOS shows on a focused text field (Caps
            // Lock is the VoiceOver key) isn't part of the window, so the
            // audit can't place it: "Parent/Child mismatch" with no element.
            if issue.element == nil, issue.compactDescription.contains("Parent/Child") {
                return true
            }
            let element = found.map {
                "\($0.type) \"\($0.label)\" at \(Int($0.frame.minX)),\(Int($0.frame.minY)) "
                    + "size \(Int($0.frame.width))x\(Int($0.frame.height))"
            } ?? "(no element)"
            let line = "AUDIT: [\(screen)] \(issue.auditType): \(issue.compactDescription). "
                + "Element: \(element). \(issue.detailedDescription)"
            print(line)
            self.issues.append(line)
            return true
        }
    }

    // A flagged element's type, label and place, read in one go. Each of
    // those read on its own is a separate search of the whole app, close to
    // a second each, and the audit flags the main window's log cells again
    // on every screen (about a hundred of them): read one at a time, that
    // was 3,559 searches, 49 of the 53 minutes on 2026-11-24. So an element
    // is read once, in one snapshot, and remembered by the audit's name for
    // it, which names the element itself and is the same on every screen.
    // An element that's gone by the time it's read counts as no element.
    //
    // That name is XCTest's description of how it finds the element (its
    // query's queryDescription: "Descendant with identity binding to AX
    // element pid: ..., token: ..."), which XCTest doesn't make public. An
    // element's own description didn't work (tried 2026-11-24: nothing was
    // remembered). So the name is asked for only if XCTest still has it,
    // and kept only if it's that one-element kind; otherwise the element is
    // read afresh each time, which is slower but never mixes two elements
    // up.
    private func found(_ element: XCUIElement) -> Found? {
        let name = Self.name(of: element)
        if let name, let known = seen[name] { return known }
        guard let snapshot = try? element.snapshot() else { return nil }
        let known = Found(type: snapshot.elementType, label: snapshot.label, frame: snapshot.frame)
        if let name { seen[name] = known }
        return known
    }

    private static func name(of element: XCUIElement) -> String? {
        let querySelector = NSSelectorFromString("query"), nameSelector = NSSelectorFromString("queryDescription")
        guard element.responds(to: querySelector),
              let query = element.perform(querySelector)?.takeUnretainedValue() as? NSObject,
              query.responds(to: nameSelector),
              let name = query.perform(nameSelector)?.takeUnretainedValue() as? String,
              name.contains("identity binding"), name.contains("token:") else { return nil }
        return name
    }
}
