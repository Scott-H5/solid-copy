// Tone.swift
//
// Solid Copy's own sounds, made here as it runs (a few kilobytes of
// audio), rather than borrowed from macOS. They're for events that must
// stand out from every other sound on the Mac, and mean the same on any
// macOS version (CLAUDE.md, v1 item 9):
//   radioLost  two falling notes (880 then 440 Hz): the radio dropped
//   radioBack  two rising notes (440 then 880 Hz): it's back
//   buzz       two short low buzzes: a dupe (the default)
//   bell       two quick bells going up: needed (the default), for a
//              needed DX spot and a needed country typed on the form
//   knock, marimba, doorbell, glide: other choices, in Settings > Speech
// Up for "good", down for "bad", like a question and its answer.
//
// Why these and not plain beeps: Scott works CW, and a plain tone near
// 500 to 900 Hz sounds like sidetone or a signal. The dupe and needed
// sounds are a buzz (odd harmonics, low) and bells (high, ringing), which
// nothing on the air sounds like. Levels were set by Scott's ear, 17
// November 2026: the first ones (0.35 of full scale) were too loud, so
// buzz and bell were cut to about a third of that.
//
// Built as a WAV file in memory and played with NSSound, so there are no
// sound files to ship or license. Soft-edged so they don't click.

import AppKit

enum Tone: String, CaseIterable {
    case radioLost, radioBack
    case buzz, knock, marimba, bell, doorbell, glide

    // The kinds of sound a note can have.
    enum Voice { case sine, buzz, knock, marimba, bell, glide(to: Double) }
    // One note: its pitch in Hz, length and the quiet after it, in ms.
    struct Note { var hertz: Double; var ms: Int; var gap: Int = 20 }

    // Its name in Settings > Speech.
    var title: String {
        switch self {
        case .radioLost: "Two falling notes"
        case .radioBack: "Two rising notes"
        case .buzz: "Buzz (Solid Copy)"
        case .knock: "Knock (Solid Copy)"
        case .marimba: "Falling marimba (Solid Copy)"
        case .bell: "Bells (Solid Copy)"
        case .doorbell: "Doorbell (Solid Copy)"
        case .glide: "Rising glide (Solid Copy)"
        }
    }

    // The sounds offered for alerts (not the radio's own two).
    static let alertChoices: [Tone] = [.buzz, .knock, .marimba, .bell, .doorbell, .glide]

    private var recipe: (voice: Voice, notes: [Note], level: Double) {
        switch self {
        case .radioLost: (.sine, [Note(hertz: 880, ms: 120), Note(hertz: 440, ms: 120)], 0.35)
        case .radioBack: (.sine, [Note(hertz: 440, ms: 120), Note(hertz: 880, ms: 120)], 0.35)
        case .buzz: (.buzz, [Note(hertz: 150, ms: 110, gap: 60), Note(hertz: 150, ms: 110)], 0.11)
        case .knock: (.knock, [Note(hertz: 180, ms: 140), Note(hertz: 180, ms: 140)], 0.2)
        case .marimba:
            (.marimba, [Note(hertz: 392, ms: 130, gap: 0), Note(hertz: 330, ms: 130, gap: 0), Note(hertz: 262, ms: 220)], 0.12)
        // Two notes like the dupe's buzz, but high and ringing (Scott,
        // 17 November 2026: the first, four notes, was too long).
        case .bell: (.bell, [Note(hertz: 1568, ms: 110, gap: 40), Note(hertz: 2093, ms: 150)], 0.105)
        case .doorbell: (.bell, [Note(hertz: 1319, ms: 260, gap: 0), Note(hertz: 1047, ms: 400)], 0.105)
        case .glide: (.glide(to: 2400), [Note(hertz: 1200, ms: 260)], 0.1)
        }
    }

    // Kept, so a sound isn't released while it plays.
    @MainActor private static var playing: [NSSound] = []

    @MainActor func play() {
        let recipe = recipe
        guard let sound = NSSound(data: Self.wav(Self.samples(recipe.voice, recipe.notes, level: recipe.level))) else { return }
        Self.playing = Self.playing.filter(\.isPlaying) + [sound]
        sound.play()
    }

    static let rate = 22_050

    // The notes as 16-bit samples, each faded in and out over 5 ms.
    static func samples(_ voice: Voice, _ notes: [Note], level: Double) -> [Int16] {
        var out: [Int16] = []
        for note in notes {
            let count = rate * note.ms / 1000, fade = rate * 5 / 1000
            let length = Double(count) / Double(rate), f = note.hertz
            for i in 0..<count {
                let t = Double(i) / Double(rate)
                let edge = min(1, Double(min(i, count - 1 - i)) / Double(fade))
                func wave(_ multiple: Double) -> Double { sin(2 * .pi * f * multiple * t) }
                let value: Double
                switch voice {
                case .sine: value = wave(1)
                case .buzz:
                    // Odd harmonics, softer as they go up: reedy, not a note.
                    value = [1.0, 3, 5, 7, 9].reduce(0) { $0 + wave($1) / $1 } / 1.3
                case .knock:
                    value = (wave(1) + 0.4 * wave(2.3)) / 1.4 * exp(-t * 35)
                case .marimba:
                    value = (wave(1) + 0.3 * wave(4) * exp(-t * 30)) / 1.3 * exp(-t * 12)
                case .bell:
                    // A small bell's partials (not whole multiples), dying away.
                    value = (wave(1) + 0.5 * wave(2.76) * exp(-t * 10) + 0.25 * wave(5.4) * exp(-t * 16))
                        / 1.75 * exp(-t * 6)
                case .glide(let to):
                    let phase = 2 * .pi * (f * t + (to - f) * t * t / (2 * length))
                    value = (sin(phase) + 0.3 * sin(2 * phase)) / 1.3
                }
                out.append(Int16(value * edge * level * Double(Int16.max)))
            }
            out += Array(repeating: 0, count: rate * note.gap / 1000)
        }
        return out
    }

    // A 16-bit mono WAV file around the samples.
    static func wav(_ samples: [Int16]) -> Data {
        var data = Data()
        func add<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); add(UInt32(36 + bytes))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); add(UInt32(16)); add(UInt16(1)); add(UInt16(1))
        add(UInt32(rate)); add(UInt32(rate * 2)); add(UInt16(2)); add(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); add(UInt32(bytes))
        for sample in samples { add(sample) }
        return data
    }
}

// The two alerts with sounds of their own (Settings > Speech, Sounds).
// Each plays a Solid Copy sound, a Mac sound, or nothing, as chosen.
enum Alert: String, CaseIterable {
    case dupe, needed

    var title: String {
        switch self {
        case .dupe: "Dupe sound"
        case .needed: "Needed sound"
        }
    }

    var standard: String {
        switch self {
        case .dupe: Tone.buzz.rawValue
        case .needed: Tone.bell.rawValue
        }
    }

    // The Mac's own sounds, offered after Solid Copy's.
    static let macSounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping",
                            "Pop", "Purr", "Sosumi", "Submarine", "Tink"]

    // Every choice: (saved name, title). Solid Copy's by their Tone name,
    // the Mac's as "mac:Basso", and "none".
    static var choices: [(id: String, title: String)] {
        Tone.alertChoices.map { ($0.rawValue, $0.title) }
            + macSounds.map { ("mac:" + $0, $0 + " (Mac)") } + [("none", "No sound")]
    }

    @MainActor static func play(_ id: String) {
        if let tone = Tone(rawValue: id) {
            tone.play()
        } else if id.hasPrefix("mac:"), let sound = NSSound(named: NSSound.Name(String(id.dropFirst(4))))?.copy() as? NSSound {
            sound.play()
        }
    }

    @MainActor func play() { Self.play(Settings.alertSound(for: self)) }
}
