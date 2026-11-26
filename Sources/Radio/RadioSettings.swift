// RadioSettings.swift
//
// One of your radios, and how to reach it. You can have several (the
// TS-590SG and the KX3, say), set up in Settings > Radio; one is in use at
// a time, whatever the profile, and you can switch in the middle of a
// session (Settings.swift keeps the list and which is in use).

import Foundation

struct RadioSettings: Codable, Equatable {
    var id = UUID()
    // hamlib's number for the radio model (2037 is the Kenwood TS-590SG,
    // 2045 the Elecraft KX3), and its name, for the screen. For the
    // built-in driver, the maker's own (KenwoodRadio.someKenwood) until the
    // radio has said which model it is. Kept for a
    // Hamlib NET rigctl radio too, where it picks the Elecraft and TS-590
    // commands (see RigctldClient).
    var model: Int
    var modelName: String
    // The radio's serial port, such as /dev/cu.usbserial-XXXX.
    var port: String = ""
    // The port's speed in baud. It must match the radio's own setting.
    var baud: Int = 38_400
    // Solid Copy's own driver for Kenwood and Elecraft radios (KenwoodClient),
    // which talks to the port directly. Off, the radio is reached through
    // Hamlib NET rigctl (below).
    var builtIn: Bool = false
    // Hamlib NET rigctl: the address ("host:port") of a rigctld you run
    // yourself, with the radio's model, port and speed set in that rigctld.
    // Empty means this Mac at rigctld's usual port, 127.0.0.1:4532.
    var address: String = ""

    // Where to connect for Hamlib NET rigctl.
    var hostAndPort: (host: String, port: UInt16) {
        let parts = address.split(separator: ":")
        if parts.count == 2, let port = UInt16(parts[1]) { return (String(parts[0]), port) }
        if address.isEmpty { return ("127.0.0.1", 4532) }
        return (address, 4532)   // a host with no port: rigctld's usual one
    }

    // The speeds offered in Settings.
    static let speeds = [4_800, 9_600, 19_200, 38_400, 57_600, 115_200]

    // Its name in menus and speech: "Kenwood TS-590SG", or just "Kenwood"
    // until the radio has said which model it is, or "rigctld at
    // 127.0.0.1:4532" for a Hamlib NET rigctl radio, or "New radio" until
    // a maker is chosen.
    var name: String {
        if !builtIn {
            let (host, port) = hostAndPort
            return "rigctld at \(host):\(port)"
        }
        return modelName.isEmpty ? "New radio" : modelName
    }

    // Set up enough to try: for the built-in driver, a known model and a
    // port. Hamlib NET rigctl always has enough (its defaults are set).
    var isComplete: Bool {
        guard builtIn else { return true }
        return !port.isEmpty && KenwoodRadio.forModel(model) != nil
    }
}

// What each radio is called in menus and speech. Usually its name, but two
// radios can share one (the same model twice, or a radio added again once
// it has named itself), and then the port is added: "Kenwood TS-590SG on
// usbserial-8410". So they can be told apart by eye and by VoiceOver, and
// a pop-up menu keeps both: it keeps only one item of each title, which
// left Settings > Radio's "Radio in use" showing nothing chosen (found 26
// November 2026). Any still alike get a number: "Kenwood (2)".
extension RadioSettings {
    static func titles(_ radios: [RadioSettings]) -> [String] {
        var counts: [String: Int] = [:]
        radios.forEach { counts[$0.name, default: 0] += 1 }
        let named = radios.map { radio -> String in
            guard counts[radio.name, default: 0] > 1, radio.builtIn, !radio.port.isEmpty else { return radio.name }
            let port = radio.port.hasPrefix("/dev/cu.") ? String(radio.port.dropFirst(8)) : radio.port
            return "\(radio.name) on \(port)"
        }
        var seen: [String: Int] = [:]
        return named.map { title in
            seen[title, default: 0] += 1
            let count = seen[title]!
            return count == 1 ? title : "\(title) (\(count))"
        }
    }

    // This radio's title among `radios` (its name, if it isn't one of them).
    static func title(of radio: RadioSettings, among radios: [RadioSettings]) -> String {
        radios.firstIndex { $0.id == radio.id }.map { titles(radios)[$0] } ?? radio.name
    }
}

// Reading a saved radio. Written by hand (in an extension, so the plain
// RadioSettings(model:...) initialiser is kept) because radios saved
// before they had an identity have none: they get a new one.
extension RadioSettings {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        model = try values.decode(Int.self, forKey: .model)
        modelName = try values.decode(String.self, forKey: .modelName)
        port = try values.decodeIfPresent(String.self, forKey: .port) ?? ""
        baud = try values.decodeIfPresent(Int.self, forKey: .baud) ?? 38_400
        address = try values.decodeIfPresent(String.self, forKey: .address) ?? ""
        builtIn = try values.decodeIfPresent(Bool.self, forKey: .builtIn) ?? false
        // Radios saved for the bundled rigctld (gone now) have no address and
        // a Kenwood or Elecraft model: the built-in driver replaces it, so
        // they move to it.
        if !builtIn, address.isEmpty, KenwoodRadio.forModel(model) != nil { builtIn = true }
    }
}

// The makers Settings > Radio offers for the built-in driver. Only the
// maker is chosen: the radio says which model it is when it connects
// (KenwoodClient.identify), and that model is saved in place of the
// maker's. Any other radio goes through Hamlib NET rigctl, with a
// rigctld you run.
enum RadioModels {
    static let makers: [(name: String, model: Int)] = [
        ("Kenwood", KenwoodRadio.someKenwood),
        ("Elecraft", KenwoodRadio.someElecraft),
    ]

    // A saved model's maker, or nil for one the built-in driver doesn't know.
    static func maker(of model: Int) -> String? {
        KenwoodRadio.forModel(model).map { $0.isElecraft ? "Elecraft" : "Kenwood" }
    }
}
