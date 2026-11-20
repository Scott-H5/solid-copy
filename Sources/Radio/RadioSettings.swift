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
    // 2045 the Elecraft KX3), and its name, for the screen. Kept for a
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

    // Its name in menus and speech: "Kenwood TS-590SG", or "rigctld at
    // 127.0.0.1:4532" for a Hamlib NET rigctl radio, or "New radio" until
    // a model is chosen.
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

// The radios the Settings menus offer. Only the built-in driver's five
// (KenwoodRadio), by hamlib's model number, which saved radios are keyed on.
// Any other radio goes through Hamlib NET rigctl, with a rigctld you run.
enum RadioModels {
    struct Model {
        let number: Int
        let maker: String
        let name: String
    }

    static let builtIn: [Model] = [
        Model(number: 2031, maker: "Kenwood", name: "TS-590S"),
        Model(number: 2037, maker: "Kenwood", name: "TS-590SG"),
        Model(number: 2029, maker: "Elecraft", name: "K3"),
        Model(number: 2044, maker: "Elecraft", name: "KX2"),
        Model(number: 2045, maker: "Elecraft", name: "KX3"),
    ]
}
