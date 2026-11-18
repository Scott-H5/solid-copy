// Speaker.swift
//
// Asks VoiceOver to say something, without moving focus. This is how the
// app reports things that have no visible movement, such as "Logged"
// (accessibility contract, rule 9).
//
// If VoiceOver is off, nothing is said (and a braille display shows
// what VoiceOver says, so this reaches braille too).
//
// How much is said is yours to choose, for three kinds of message that
// come often and can talk over a CW or voice exchange you're copying
// (Settings > Speech; see say(_:full:brief:cue:) below):
//   - lookup:  what the callsign lookup found
//   - logging: "Logged W1AW, 158 in the log"
//   - radio:   what a radio key you pressed changed ("Noise blanker on")
// Each can be said in full, briefly, as a short sound only, or (lookups
// only) not at all. Quiet Mode (Speech menu) turns all three down to
// sounds for a while, say for a pile-up. Everything else (errors,
// warnings, anything you asked to hear) is always said in full: a
// setting should never hide a problem. The Speech menu's "Say" commands
// repeat what was turned down, whenever you want it.

import AppKit

@MainActor
enum Speaker {
    // How long to wait before speaking. Moving focus makes VoiceOver read
    // the newly focused field, and an announcement made at the same moment
    // can be lost. Crystal Set found a similar delay was needed after menu
    // commands. Tune this by ear.
    static let delay: TimeInterval = 0.3

    static func announce(_ text: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // High priority interrupts whatever VoiceOver is saying, so a
            // new announcement replaces a stale one (contract, rule 13).
            NSAccessibility.post(
                element: NSApp.mainWindow ?? NSApp as Any,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: text,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue,
                ]
            )
        }
    }
}

extension Speaker {

    // The kinds of message you can turn down.
    enum Kind: String, CaseIterable {
        case lookup, logging, radio, connection

        // Its name in Settings > Speech.
        var title: String {
            switch self {
            case .lookup: "Callsign lookups"
            case .logging: "Logging a contact"
            case .radio: "Radio changes you make"
            case .connection: "Radio lost or back"
            }
        }

        // The levels it offers. Logging and radio changes always give you
        // something back, at least a sound, so a key press is never met
        // with silence.
        var levels: [Level] {
            switch self {
            case .lookup: [.full, .brief, .sound, .off]
            case .logging: [.full, .brief, .sound]
            case .radio: [.full, .sound]
            // Never silent: a lost radio must always be heard. Its own
            // tones (Tone.swift) play either way; "full" adds the words.
            case .connection: [.full, .sound]
            }
        }

        // What "brief" means for it, for Settings.
        var briefTitle: String {
            switch self {
            case .lookup: "Name only"
            case .logging: "Just \"Logged\""
            case .radio, .connection: "Brief"
            }
        }
    }

    enum Level: String {
        case full, brief, sound, off

        func title(for kind: Kind) -> String {
            switch self {
            case .full: "Say everything"
            case .brief: kind.briefTitle
            case .sound: "Sound only"
            case .off: "Nothing (Option-Command-N says it)"
            }
        }
    }

    // Short sounds, from those every Mac has, chosen to be easy to tell
    // apart under a signal.
    enum Cue: String {
        case logged = "Glass"
        case found = "Pop"
        case notFound = "Bottle"
        case radio = "Tink"
        // A warning (a problem: a band that isn't one, an upload that
        // failed). Always played, whatever the settings. A dupe has its
        // own sound (Alert in Tone.swift).
        case warning = "Basso"

        // The usual sound for a kind (for trying a choice in Settings).
        static func of(_ kind: Kind) -> Cue {
            switch kind {
            case .lookup: .found
            case .logging: .logged
            case .radio, .connection: .radio
            }
        }

        func play() {
            // A new NSSound each time, so quick cues don't cut each other off.
            guard let sound = NSSound(named: NSSound.Name(rawValue))?.copy() as? NSSound else { return }
            sound.play()
        }
    }

    // Quiet Mode: everything adjustable down to its sound, until turned
    // off. Not kept between launches, so Solid Copy never opens quiet.
    static var quiet = false

    // The level in use for a kind: Quiet Mode, or your setting.
    static func level(for kind: Kind) -> Level {
        let chosen = Settings.speechLevel(for: kind)
        return quiet && chosen != .off ? .sound : chosen
    }

    // Says a message of an adjustable kind at the level chosen for it.
    // brief is the short form (the full one is used if there's none).
    static func say(_ kind: Kind, full: String, brief: String? = nil, cue: Cue) {
        switch level(for: kind) {
        case .full: announce(full)
        case .brief: announce(brief ?? full)
        case .sound: cue.play()
        case .off: break
        }
    }
}
