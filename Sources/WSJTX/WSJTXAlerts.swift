// WSJTXAlerts.swift
//
// Listening for WSJT-X in the background (v1.6 item 4; Settings >
// WSJT-X). With "Listen for WSJT-X all the time" on, Solid Copy listens
// from launch, not only while the decodes window is open, so a contact
// you make in WSJT-X is logged whenever you make it (WSJTXLogging.swift).
// Only contacts WSJT-X logs are added: decodes never are.
//
// With the decodes window closed, it also tells you (if "Alert me" is
// on) about two things you'd want to hear while doing something else:
//   - a station calling you: "W1AW is calling you in WSJT-X: R-12";
//   - a needed station: "Needed: VP8XYZ, Falkland Islands, new country,
//     20 meters", by the same rule as the decodes window's "needed" (a
//     new country, or a country new on this band or in data modes, in
//     the log that's open). A decode carries a grid, not a state, so
//     states can't be told from it.
// Each needed station is told once per band an hour, and what one FT8
// period brings comes as one alert, so a busy band doesn't chatter.
//
// How it reaches you: the needed sound, and then VoiceOver's
// announcement if Solid Copy is in front, or a Mac notification (which
// VoiceOver reads) if another app is. macOS asks once to allow Solid
// Copy's notifications. Each alert is listed in Window > Activity too.
// (The author chose sound and notification, 22 November 2026.)

import AppKit
import UserNotifications

@MainActor
final class WSJTXAlerts {
    static let shared = WSJTXAlerts()
    static let neededAgainAfter: TimeInterval = 60 * 60

    // Set by the app: whether the decodes window is showing (it says its
    // own), and the open log, for "needed".
    var windowIsOpen: () -> Bool = { false }
    var log: () -> [QSO] = { [] }
    // How an alert reaches you; the checks listen in.
    var deliver: (String) -> Void = { WSJTXAlerts.sayOrNotify($0) }

    private let worked = WorkedCountries()
    private var seen: Set<String> = []
    private var told: [String: Date] = [:]
    private var observer: NSObjectProtocol?

    // Listening as the settings say, and watching what WSJT-X sends.
    // Called at launch and when the settings change.
    func apply() {
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: WSJTXListener.didChange, object: nil,
                                                              queue: .main) { _ in
                MainActor.assumeIsolated { WSJTXAlerts.shared.listenerChanged() }
            }
        }
        if Settings.wsjtxAlwaysListen {
            WSJTXListener.shared.start()
            if Settings.wsjtxAlerts { Self.askForNotifications() }
        } else if !windowIsOpen() {
            WSJTXListener.shared.stop()
        }
    }

    // The decodes window closing: keep listening if that's the setting.
    var keepsListening: Bool { Settings.wsjtxAlwaysListen }

    func listenerChanged(now: Date = Date()) {
        let decodes = WSJTXListener.shared.decodes
        let fresh = decodes.filter { $0.decode.isNew && !seen.contains(Self.key($0.decode)) }
        for (decode, _) in fresh { seen.insert(Self.key(decode)) }
        if seen.count > 5_000 { seen = Set(decodes.map { Self.key($0.decode) }) }
        guard Settings.wsjtxAlerts, !windowIsOpen(), !fresh.isEmpty else { return }
        let listener = WSJTXListener.shared
        let myCall = (listener.status?.deCall).flatMap { $0.isEmpty ? nil : $0 }
            ?? Settings.currentProfile.station["station_callsign"] ?? ""
        let band = listener.status.flatMap { Bands.name(forHertz: Int($0.dialHertz)) }
        var calling: [String] = [], needed: [String] = []
        var contacts: [QSO]?
        for (decode, _) in fresh.reversed() {
            guard let words = FT8Text(decode.text) else { continue }
            if DecodeLine.isToMe(words, myCall: myCall) {
                calling.append("\(words.from) is calling you in WSJT-X: \(words.exchange)")
                continue
            }
            let call = Callsign.normalized(words.plainFrom)
            let key = "\(call) \(band ?? "")"
            guard Callsign.looksValid(call), told[key].map({ now.timeIntervalSince($0) >= Self.neededAgainAfter }) ?? true,
                  let country = Countries.shared.country(of: call) else { continue }
            if contacts == nil { contacts = log() }
            guard let why = worked.needed(country: country, band: band, modeGroup: "Data", log: contacts ?? []) else { continue }
            told[key] = now
            needed.append("\(call), \(country.name), \(why)" + (band.map { ", \(Bands.spoken($0))" } ?? ""))
        }
        if told.count > 2_000 { told = told.filter { now.timeIntervalSince($0.value) < Self.neededAgainAfter } }
        var parts = calling
        if !needed.isEmpty { parts.append("Needed: " + needed.joined(separator: "; ")) }
        guard !parts.isEmpty else { return }
        let text = parts.joined(separator: ". ") + "."
        Alert.needed.play()
        Activity.shared.record("WSJT-X", "Alerts", ok: true, latest: text)
        deliver(text)
    }

    static func key(_ decode: WSJTXDecode) -> String { "\(decode.milliseconds) \(decode.df) \(decode.text)" }

    // Spoken if Solid Copy is in front (VoiceOver only speaks for the app
    // in front); otherwise a notification, which VoiceOver reads.
    static func sayOrNotify(_ text: String) {
        if NSApp.isActive { return Speaker.announce(text) }
        let content = UNMutableNotificationContent()
        content.title = "WSJT-X"
        content.body = text
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            guard let error else { return }
            Task { @MainActor in
                Activity.shared.record("WSJT-X", "Alerts", ok: false,
                                       latest: "Couldn't show a notification: \(error.localizedDescription). "
                                       + "Allow Solid Copy in System Settings > Notifications.")
            }
        }
    }

    // macOS asks once; after that this does nothing.
    static func askForNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard !granted else { return }
            Task { @MainActor in
                Activity.shared.record("WSJT-X", "Alerts", ok: false,
                                       latest: "Notifications are off for Solid Copy, so alerts with another app in front "
                                       + "are only a sound. System Settings > Notifications > Solid Copy turns them on.")
            }
        }
    }
}
