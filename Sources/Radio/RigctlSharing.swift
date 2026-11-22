// RigctlSharing.swift
//
// Joins the rigctl server (RigctlServer.swift) to Solid Copy's own radio
// connection. Kept apart from the server so the server's check
// (tools/check-rigctl.sh) can build it without the rest of the app.

import Foundation

extension RigctlServer {
    static let shared = RigctlServer(radio: RadioMonitor.shared)
}

// The real radio: Solid Copy's own connection to it.
extension RadioMonitor: RigctlRadio {
    var model: Int { settingsInUse?.model ?? 1 }
    var maxWatts: Double {
        settingsInUse.flatMap { KenwoodRadio.forModel($0.model)?.maxWatts } ?? 100
    }
    var lastAnswered: Date { lastAnswerTime }
    func send(_ command: String, done: @escaping @MainActor (Bool) -> Void) {
        change(command) { reading in done(reading != nil) }
    }
}
