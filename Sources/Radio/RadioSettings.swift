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
    // 2045 the Elecraft KX3), and its name, for the screen.
    var model: Int
    var modelName: String
    // The radio's serial port, such as /dev/cu.usbserial-0567003F3CA0.
    var port: String = ""
    // The port's speed in baud. It must match the radio's own setting.
    var baud: Int = 38_400
    // Empty: Solid Copy starts its own rigctld for this radio. Otherwise
    // the address ("host:port") of a rigctld you run yourself; the model,
    // port and speed are then set in that rigctld, not here.
    var address: String = ""

    var usesOwnRigctld: Bool { address.isEmpty }

    // The rigctld Solid Copy starts listens here. Not 4532, rigctld's
    // usual port: another rigctld there (one started at login, say) would
    // share the port, macOS handing each connection to one or the other,
    // so Solid Copy could find itself talking to the wrong radio. Other
    // programs (WSJT-X, say, set to "Hamlib NET rigctl") can share the
    // radio at 127.0.0.1:45320 while Solid Copy is open.
    // (A variable only so tools/check-radio.sh can use a spare port.)
    static var ownPort: UInt16 = 45320

    // Where to connect: Solid Copy's own rigctld, or yours.
    var hostAndPort: (host: String, port: UInt16) {
        guard !usesOwnRigctld else { return ("127.0.0.1", Self.ownPort) }
        let parts = address.split(separator: ":")
        if parts.count == 2, let port = UInt16(parts[1]) { return (String(parts[0]), port) }
        return (address, 4532)   // rigctld's usual port
    }

    // The speeds offered in Settings.
    static let speeds = [4_800, 9_600, 19_200, 38_400, 57_600, 115_200]

    // Its name in menus and speech: "Kenwood TS-590SG", "rigctld at
    // 127.0.0.1:4532" for one you run yourself, or "New radio" until a
    // model is chosen.
    var name: String {
        if !usesOwnRigctld { return "rigctld at \(address)" }
        return modelName.isEmpty ? "New radio" : modelName
    }

    // Set up enough to try: a model and a port (or your own rigctld).
    var isComplete: Bool { !usesOwnRigctld || (model > 0 && !port.isEmpty) }
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
    }
}

// The radios hamlib knows, read from the bundled rigctld's list
// ("rigctld -l") the first time they're needed.
enum RadioModels {
    struct Model {
        let number: Int
        let maker: String
        let name: String
    }

    // The bundled rigctld (see tools/bundle-rigctld.sh). (A variable only
    // so tools/check-radio.sh can use Homebrew's.)
    static var rigctld = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/rigctld")

    // Runs "rigctld -l" in the background and returns its list, sorted by
    // maker and name. Empty if it can't be run.
    static func load() async -> [Model] {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = rigctld
            process.arguments = ["-l"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [] }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return parse(String(decoding: data, as: UTF8.self))
        }.value
    }

    // Each line is "  2037  Kenwood   TS-590SG   20250515.12  Stable  RIG_MODEL_TS590SG",
    // with columns separated by two or more spaces (names can have one).
    static func parse(_ text: String) -> [Model] {
        var models: [Model] = []
        for line in text.split(separator: "\n") {
            let columns = line.components(separatedBy: "  ").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            // Model 2 is "NET rigctl", which is what "a rigctld you run
            // yourself" already is.
            guard columns.count >= 3, let number = Int(columns[0]), number != 2 else { continue }
            models.append(Model(number: number, maker: columns[1], name: columns[2]))
        }
        return models.sorted { ($0.maker.lowercased(), $0.name.lowercased()) < ($1.maker.lowercased(), $1.name.lowercased()) }
    }
}
