// tools/profiles-check/main.swift
//
// Checks operating profiles, using this test program's own settings (never
// the app's):
//   - settings saved before profiles existed become the Home profile, and
//     a Portable profile is added;
//   - switching profiles changes the logging form's fields, Tab order and
//     starting values;
//   - a logged contact gets the profile's station details;
//   - Up Arrow in an empty Callsign corrects the last contact, and
//     Command-Z undoes the correction;
//   - a park activation warns of a dupe (same call, band, park and day).
//
// Run it with:  bash tools/check-profiles.sh

import AppKit

func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let defaults = UserDefaults.standard
    let keys = ["profiles", "currentProfile", "formFields", "myCallsign", "myGrid", "logColumns", "lookupEnabled"]
    keys.forEach(defaults.removeObject(forKey:))
    defer { keys.forEach(defaults.removeObject(forKey:)) }

    // Settings as they were saved before profiles: a callsign, a grid, and a
    // form whose fields have no starting values.
    defaults.set("N3BYY", forKey: "myCallsign")
    defaults.set("EM10", forKey: "myGrid")
    defaults.set(Data(#"[{"adif":"name","tabStop":true},{"adif":"rst_sent","tabStop":true},{"adif":"comment","tabStop":true}]"#.utf8),
                 forKey: "formFields")
    defaults.set(false, forKey: "lookupEnabled")

    let profiles = Settings.profiles
    check(profiles.map(\.name) == ["Home", "Portable"], "old settings become Home, and Portable is added")
    let home = profiles[0]
    check(home.station["station_callsign"] == "N3BYY" && home.station["my_gridsquare"] == "EM10",
          "Home keeps your callsign and grid")
    check(home.formFields.map(\.adif) == ["name", "rst_sent", "comment"] && home.formFields[1].startingValue == "",
          "Home keeps your form; signal reports start blank")
    check(Settings.profiles.map(\.id) == profiles.map(\.id) && Settings.currentProfile.id == home.id,
          "profiles keep their identities between reads; Home is in use")

    // Profiles saved when reports started at 59 are blanked once, at launch;
    // a 59 set afterwards stays.
    var old = Settings.profiles
    old[0].formFields[1].startingValue = "59"
    Settings.profiles = old
    defaults.removeObject(forKey: "reportsBlanked")
    Settings.registerDefaults()
    check(Settings.profiles[0].formFields[1].startingValue == "", "an old 59 is cleared once")
    Settings.profiles = old
    Settings.registerDefaults()
    check(Settings.profiles[0].formFields[1].startingValue == "59", "a 59 you set later stays")
    Settings.profiles = profiles

    // The logging form, with Home.
    let logbook = try! Logbook(database: LogDatabase(fileURL: URL(fileURLWithPath: CommandLine.arguments[1])
        .appendingPathComponent("Logbook.sqlite")))
    let form = LogEntryViewController(logbook: logbook)
    let window = NSWindow(contentViewController: form)
    window.layoutIfNeeded()
    // No event loop here to close undo groups, so each step makes its own.
    window.undoManager?.groupsByEvent = false
    func step(_ action: () -> Void) {
        window.undoManager?.beginUndoGrouping()
        action()
        window.undoManager?.endUndoGrouping()
    }
    func tabOrder() -> [String] {
        var names: [String] = []
        var view: NSView? = form.callsignField
        repeat {
            names.append((view as? NSTextField)?.accessibilityLabel() ?? "?")
            view = view?.nextKeyView
        } while view !== form.callsignField && names.count < 20
        return names
    }
    func field(_ label: String) -> NSTextField? {
        var found: NSTextField?
        func walk(_ v: NSView) {
            if let t = v as? NSTextField, t.accessibilityLabel() == label, t.isEditable { found = t }
            v.subviews.forEach(walk)
        }
        walk(form.view)
        return found
    }
    check(tabOrder() == ["Callsign", "Name", "RST sent", "Comment"], "Home's Tab order: \(tabOrder())")

    // Switch to Portable.
    Settings.useProfile(profiles[1].id)
    // Name is on Portable's form but not a Tab stop (lookups fill it).
    check(tabOrder() == ["Callsign", "Band", "Mode", "Frequency (MHz)", "Power (watts)",
                         "RST sent", "RST received"], "Portable's Tab order: \(tabOrder())")
    check(field("Power (watts)")?.stringValue == "5", "Power starts at 5 on Portable")

    // Log a contact with Portable; it gets Portable's station details.
    var portable = Settings.currentProfile
    portable.station["my_pota_ref"] = "US-1234"
    Settings.currentProfile = portable
    form.callsignField.stringValue = "K1ABC"
    field("Band")?.stringValue = "20m"
    // A mode too: with no mode known, nothing is ever a dupe (17 November 2026).
    field("Mode")?.stringValue = "CW"
    step { form.logContact(nil) }
    let logged = logbook.contacts.last
    check(logged?.call == "K1ABC" && logged?["band"] == "20m" && logged?["tx_pwr"] == "5",
          "the contact has the form's band and power")
    check(logged?["station_callsign"] == "N3BYY" && logged?["my_pota_ref"] == "US-1234" && logged?["my_gridsquare"] == "",
          "the contact has Portable's station details (callsign and park, no grid)")
    check(field("Power (watts)")?.stringValue == "5" && field("Band")?.stringValue == "",
          "after logging, the form goes back to its starting values")

    // Correcting the last contact from the form.
    func key(_ selector: Selector) -> Bool {
        form.control(form.callsignField, textView: NSTextView(), doCommandBy: selector)
    }
    let count = logbook.contacts.count
    check(key(#selector(NSResponder.moveUp(_:))) && form.callsignField.stringValue == "K1ABC"
          && field("Band")?.stringValue == "20m", "Up Arrow in an empty Callsign brings the last contact back")
    form.callsignField.stringValue = "K1ABD"
    field("Band")?.stringValue = "40m"
    check(key(#selector(NSResponder.moveUp(_:))) && form.callsignField.stringValue == "K1ABD",
          "Up Arrow with changes doesn't throw them away")
    let id = logbook.contacts.last?.id
    step { form.logContact(nil) }
    let fixed = logbook.contacts.last
    check(logbook.contacts.count == count && fixed?.id == id && fixed?.call == "K1ABD" && fixed?["band"] == "40m"
          && fixed?.timeOn == logged?.timeOn && fixed?["my_pota_ref"] == "US-1234",
          "Return saves the correction to the same contact, its time and station kept")
    check(form.callsignField.stringValue.isEmpty, "after correcting, the form is empty for the next contact")
    window.undoManager?.undo()
    check(logbook.contacts.last?.call == "K1ABC" && logbook.contacts.last?["band"] == "20m",
          "Command-Z undoes the correction")
    _ = key(#selector(NSResponder.moveUp(_:)))
    step { form.clearForm(nil) }
    check(logbook.contacts.last?.call == "K1ABC" && form.callsignField.stringValue.isEmpty,
          "Escape leaves the contact as it was")
    check(!key(#selector(NSResponder.moveDown(_:))), "Down Arrow on a new contact does what it usually does")

    // A dupe on the park activation: K1ABC on 20m today, same park.
    func lineText() -> String {
        var text = ""
        func walk(_ v: NSView) {
            if let t = v as? NSTextField, !t.isEditable, t.stringValue.contains("Dupe") { text = t.stringValue }
            v.subviews.forEach(walk)
        }
        walk(form.view)
        return text
    }
    form.callsignField.stringValue = "K1ABC"
    field("Band")?.stringValue = "20m"
    field("Mode")?.stringValue = "CW"
    form.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: form.callsignField))
    check(lineText().hasPrefix("Dupe: K1ABC worked on 20 meters"), "a dupe is warned of: \(lineText())")
    step { form.clearForm(nil) }
    form.callsignField.stringValue = "K1ABC"
    field("Band")?.stringValue = "40m"
    field("Mode")?.stringValue = "CW"
    form.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: form.callsignField))
    check(lineText().isEmpty, "another band isn't a dupe")

    // Signal reports: a sign and up to 3 digits, nothing else.
    let allowed = ["", "-", "+", "5", "59", "599", "-12", "+05"]
    let refused = ["5o9", "S9", "5NN", "5999", "59+20", "--1", "1-"]
    check(allowed.allSatisfy(SignalReportFormatter.isAllowed) && !refused.contains(where: SignalReportFormatter.isAllowed),
          "signal reports take a sign and up to 3 digits")
    check(field("RST sent")?.formatter is SignalReportFormatter, "RST sent on the form checks what's typed")

    // No band (the radio dropped unnoticed): warned once, then logged.
    step { form.clearForm(nil) }
    let before = logbook.contacts.count
    form.callsignField.stringValue = "K9NOB"
    step { form.logContact(nil) }
    check(logbook.contacts.count == before && form.callsignField.stringValue == "K9NOB",
          "no band: not logged the first time, the form kept")
    step { form.logContact(nil) }
    check(logbook.contacts.count == before + 1 && logbook.contacts.last?["band"] == "",
          "Return again logs it without a band")
}
