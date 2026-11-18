// CW.swift
//
// The CW menu: sending through a WinKeyer (WinKeyer.swift).
//   Connect WinKeyer / Disconnect WinKeyer   opened only on request
//   F1 to F8                                 send messages 1 to 8, filled
//                                            in from the form
//   Stop Sending                             also Escape in the form
//   CW Settings…                             Settings > CW
// The message items show each message, so VO-reading the menu reminds
// you what F1 to F8 send. Sending is silent when it works (you're
// listening to the CW); a problem is said.
// While the WinKeyer is connected, Radio > Keyer Faster and Slower
// (Control-Command-= and -) change its speed instead of the radio's keyer.
//
// More of the AppDelegate class, like ImportExport.swift.

import AppKit

extension AppDelegate {

    func fillCWMenu() {
        cwMenu.removeAllItems()
        let connected = WinKeyer.shared.isConnected
        cwMenu.addItem(withTitle: connected ? "Disconnect WinKeyer" : "Connect WinKeyer",
                       action: #selector(toggleWinKeyer(_:)), keyEquivalent: "").target = self
        cwMenu.addItem(.separator())
        let keys = [NSF1FunctionKey, NSF2FunctionKey, NSF3FunctionKey, NSF4FunctionKey,
                    NSF5FunctionKey, NSF6FunctionKey, NSF7FunctionKey, NSF8FunctionKey]
        for (index, message) in Settings.cwMessages.enumerated() {
            let key = String(Character(UnicodeScalar(keys[index])!))
            let item = cwMenu.addItem(withTitle: "Send \(message)", action: #selector(sendCWMessage(_:)),
                                      keyEquivalent: key)
            item.keyEquivalentModifierMask = []
            item.tag = index
            item.target = self
        }
        cwMenu.addItem(.separator())
        cwMenu.addItem(withTitle: "Stop Sending", action: #selector(stopCW(_:)), keyEquivalent: "").target = self
        cwMenu.addItem(withTitle: "CW Settings…", action: #selector(editCW(_:)), keyEquivalent: "").target = self
    }

    @objc func toggleWinKeyer(_ sender: Any?) {
        if WinKeyer.shared.isConnected {
            WinKeyer.shared.disconnect()
            return Speaker.announce("WinKeyer disconnected.")
        }
        let port = Settings.cwPort
        guard !port.isEmpty else {
            editCW(nil)
            return Speaker.announce("Choose the WinKeyer's port in Settings, CW, first.")
        }
        Speaker.announce("Connecting to the WinKeyer.")
        WinKeyer.shared.connect(to: port, wpm: Settings.cwSpeed) { problem in
            if let problem {
                Speaker.Cue.warning.play()
                return Speaker.announce("WinKeyer not connected. \(problem)")
            }
            Speaker.announce("WinKeyer connected, \(Settings.cwSpeed) words per minute. F1 to F8 send messages.")
        }
    }

    @objc func sendCWMessage(_ sender: NSMenuItem) {
        let messages = Settings.cwMessages
        guard messages.indices.contains(sender.tag) else { return }
        guard WinKeyer.shared.isConnected else {
            NSSound.beep()
            return Speaker.announce("The WinKeyer isn't connected. CW menu, Connect WinKeyer.")
        }
        let values = logEntry?.cwFillIns() ?? [:]
        let text = CWMessages.expand(messages[sender.tag], values: values)
        // A message with {NR} gives this contact its serial number.
        if messages[sender.tag].uppercased().contains("{NR}"), let serial = values["NR"] {
            logEntry?.serialWasSent(serial)
        }
        guard !WinKeyer.sendable(text).isEmpty else {
            NSSound.beep()
            return Speaker.announce("F\(sender.tag + 1) has nothing to send yet.")
        }
        WinKeyer.shared.send(text + " ")
    }

    @objc func stopCW(_ sender: Any?) {
        if WinKeyer.shared.stop() { Speaker.announce("Stopped.") }
    }

    @objc func editCW(_ sender: Any?) {
        showSettings(nil)
        settingsWindow?.showSection(named: "CW")
    }

    // Keyer Faster and Slower: the WinKeyer's speed while it's connected,
    // otherwise the radio's own keyer.
    func changeCWSpeed(by step: Int) -> Bool {
        guard WinKeyer.shared.isConnected else { return false }
        Settings.cwSpeed += step
        WinKeyer.shared.setSpeed(Settings.cwSpeed)
        Speaker.announce("WinKeyer \(Settings.cwSpeed) words per minute.")
        return true
    }
}
