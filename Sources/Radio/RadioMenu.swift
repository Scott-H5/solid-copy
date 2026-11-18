// RadioMenu.swift
//
// The menu items for choosing a radio: one per radio, then No Radio, with
// the one in use ticked. Used by the Radio menu (with Control-Command-1
// to 9) and the radio pop-up under the clocks.
//
// The items have no target, so macOS looks along the "responder chain"
// for something that handles the command, and finds the app delegate
// (AppDelegate.chooseRadio and editRadio) at its end. The commands are
// named as text, not #selector(AppDelegate...), so this file doesn't need
// the app delegate's code (the check tools build without it).

import AppKit

@MainActor
enum RadioMenu {
    static let chooseRadio = Selector(("chooseRadio:"))
    static let editRadio = Selector(("editRadio:"))

    static func choices(withShortcuts: Bool) -> [NSMenuItem] {
        let current = Settings.currentRadio?.id
        var items: [NSMenuItem] = []
        for (index, radio) in Settings.radios.enumerated() {
            let item = NSMenuItem(title: radio.name, action: chooseRadio,
                                  keyEquivalent: withShortcuts && index < 9 ? "\(index + 1)" : "")
            item.keyEquivalentModifierMask = [.command, .control]
            item.representedObject = radio.id
            item.state = radio.id == current ? .on : .off
            items.append(item)
        }
        let none = NSMenuItem(title: "No Radio", action: chooseRadio, keyEquivalent: "")
        none.state = current == nil ? .on : .off
        items.append(none)
        return items
    }
}
