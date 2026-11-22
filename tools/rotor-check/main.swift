// Checks rotor control (Sources/Rotor) against a pretend rotctld of its
// own, answering as hamlib's rotctld 4.7.2 does: no rotor, network or
// hamlib needed. With --live, also against a real rotctld at the port
// given (check-rotor.sh starts hamlib's dummy rotor, rotctld -m 1).

import Foundation
import Network

func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }

// A pretend rotctld: turns at `speed` degrees a second towards the last
// set_pos, and can be told to stall (stop moving) at a heading.
final class PretendRotor: @unchecked Sendable {
    let listener: NWListener
    let queue = DispatchQueue(label: "pretend rotor")
    var azimuth = 0.0, target = 0.0, speed = 60.0, stallAt: Double?, refuseAbove = 450.0
    var lastStep = Date()
    var commands: [String] = []

    init(port: UInt16) {
        listener = try! NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [unowned self] connection in
            connection.start(queue: self.queue)
            self.receive(connection, pending: "")
        }
        listener.start(queue: queue)
    }

    func step() {
        let now = Date()
        let move = speed * now.timeIntervalSince(lastStep)
        lastStep = now
        var next = abs(target - azimuth) <= move ? target : azimuth + (target > azimuth ? move : -move)
        if let stallAt, (min(azimuth, next)...max(azimuth, next)).contains(stallAt) { next = stallAt }
        azimuth = next
    }

    func receive(_ connection: NWConnection, pending: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [unowned self] data, _, done, _ in
            var text = pending + String(decoding: data ?? Data(), as: UTF8.self)
            while let end = text.firstIndex(of: "\n") {
                let line = String(text[..<end]).trimmingCharacters(in: .whitespaces)
                text = String(text[text.index(after: end)...])
                commands.append(line)
                connection.send(content: Data(answer(line).utf8), completion: .contentProcessed { _ in })
            }
            if !done { receive(connection, pending: text) }
        }
    }

    func answer(_ line: String) -> String {
        step()
        let parts = line.split(separator: " ")
        switch parts.first {
        case "+p": return "get_pos:\nAzimuth: \(String(format: "%.2f", azimuth))\nElevation: 0.00\nRPRT 0\n"
        case "+P":
            guard parts.count == 3, let az = Double(parts[1]), az <= refuseAbove else { return "set_pos:\nRPRT -1\n" }
            target = az
            return "set_pos: \(parts[1]) \(parts[2])\nRPRT 0\n"
        case "+S": target = azimuth; return "stop:\nRPRT 0\n"
        default: return "RPRT -4\n"
        }
    }
}

MainActor.assumeIsolated {
    // Headings.
    check(Rotor.normalized(-10) == 350 && Rotor.normalized(400) == 40 && Rotor.normalized(359.96) == 0,
          "headings: -10 is 350, 400 is 40, 359.96 is north")
    check(Rotor.longPath(285) == 105 && Rotor.longPath(10) == 190, "long path: the opposite way")
    check(Rotor.apart(350, 10) == 20 && Rotor.apart(10, 350) == 20 && Rotor.apart(0, 180) == 180, "how far apart, the short way")
    check(Rotor.spoken(285.4) == "285 degrees, west" && Rotor.spoken(359.8) == "0 degrees, north", "spoken: \(Rotor.spoken(285.4))")
    check(Rotor.typed("90") == 90 && Rotor.typed(" 360 ") == 0 && Rotor.typed("45.5°") == 45.5
          && Rotor.typed("400") == nil && Rotor.typed("east") == nil && Rotor.typed("-5") == nil, "typed headings")
    check(RotctldClient.address("") == ("127.0.0.1", 4533) && RotctldClient.address("shack.local") == ("shack.local", 4533)
          && RotctldClient.address("10.0.1.5:4600") == ("10.0.1.5", 4600), "addresses, with rotctld's usual port")

    // The client, against the pretend rotctld.
    let rotor = PretendRotor(port: 45_533)
    Thread.sleep(forTimeInterval: 0.3)
    let client = RotctldClient(host: "127.0.0.1", port: 45_533)
    check((try? client.azimuth()) == 0, "where it points")
    check((try? client.turn(to: 400)) != nil && rotor.commands.last == "+P 40.0 0", "a turn is sent as 0 to 359.9: \(rotor.commands.last ?? "")")
    rotor.refuseAbove = 30
    do { try client.turn(to: 90); check(false, "a refused heading throws") } catch {
        check(error as? RadioFailure == .rejected, "a refused heading is a refusal")
    }
    rotor.refuseAbove = 450
    check((try? client.stop()) != nil, "stop")
    let nobody = RotctldClient(host: "127.0.0.1", port: 45_599)
    do { _ = try nobody.azimuth(); check(false, "nobody there throws") } catch {
        check(error as? RadioFailure == .notRunning, "no rotctld: not running")
    }

    // RotorControl: a turn, said as it starts and when it arrives.
    var said: [String] = []
    let control = RotorControl.shared
    control.say = { said.append($0) }
    RotorControl.pollSeconds = 0.2
    RotorControl.stalledAfter = 1
    Settings.rotorEnabled = false
    control.turn(to: 90)
    check(said.last == "No rotor is set up. Turn it on in Settings > Radio, Rotor.", "off: it says so")
    Settings.rotorEnabled = true
    Settings.rotorAddress = "127.0.0.1:45533"
    control.settingsChanged()
    rotor.azimuth = 0; rotor.target = 0; rotor.stallAt = nil
    func wait(until done: () -> Bool, seconds: TimeInterval = 10) {
        let end = Date().addingTimeInterval(seconds)
        while !done(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }
    control.turn(to: 90, toward: "to W1AW")
    wait { said.contains { $0.hasPrefix("Rotor at") } }
    check(said.contains("Turning from 0 to 90 degrees, east."), "the turn is said: \(said)")
    check(said.last == "Rotor at 90 degrees, east.", "and its end: \(said.last ?? "")")
    check(control.recentHeading == 90, "the heading is kept, for logging")
    let entry = Activity.shared.items.first
    check(entry?.what == "Turn to 90 degrees, east to W1AW" && entry?.latest == "Rotor at 90 degrees, east.",
          "the turn is in Activity: \(entry?.what ?? "") / \(entry?.latest ?? "")")

    // Already there.
    control.turn(to: 91)
    wait { said.last?.hasPrefix("Rotor already") == true }
    check(said.last == "Rotor already at 90 degrees, east.", "already there: \(said.last ?? "")")

    // A stall, short of the heading.
    rotor.stallAt = 150
    control.turn(to: 200)
    wait { said.last?.hasPrefix("The rotor stopped") == true }
    check(said.last == "The rotor stopped at 150 degrees, south-east, short of 200.", "a stall: \(said.last ?? "")")
    rotor.stallAt = nil

    // Stop.
    rotor.speed = 20
    control.turn(to: 300)
    wait { said.last?.hasPrefix("Turning") == true }
    control.stop()
    wait { said.last?.hasPrefix("Rotor stopped") == true }
    check(said.last?.hasPrefix("Rotor stopped at 15") == true && rotor.target == rotor.azimuth, "stop: \(said.last ?? "")")
    control.sayHeading()
    wait { said.last?.hasPrefix("Rotor at") == true }
    check(said.last?.hasPrefix("Rotor at 15") == true && said.last?.hasSuffix(".") == true, "heading: \(said.last ?? "")")

    // Refused, and nobody there.
    rotor.refuseAbove = 100
    control.turn(to: 250)
    wait { said.last?.contains("refused") == true }
    check(said.last == "rotctld refused that. The rotor may not turn that far, or can't do it.", "refused: \(said.last ?? "")")
    Settings.rotorAddress = "127.0.0.1:45599"
    control.sayHeading()
    wait { said.last?.hasPrefix("No rotctld") == true }
    check(said.last == "No rotctld is answering at 127.0.0.1 port 45599. Start rotctld for your rotor, then try again.",
          "not running: \(said.last ?? "")")

    // A real rotctld (hamlib's dummy rotor), if asked.
    if let index = CommandLine.arguments.firstIndex(of: "--live"), CommandLine.arguments.count > index + 1 {
        Settings.rotorAddress = "127.0.0.1:" + CommandLine.arguments[index + 1]
        RotorControl.pollSeconds = 1
        RotorControl.stalledAfter = 5
        control.turn(to: 30)
        wait(until: { said.last?.hasPrefix("Rotor at") == true || said.last?.hasPrefix("The rotor") == true }, seconds: 30)
        check(said.last == "Rotor at 30 degrees, north-east.", "live: hamlib's dummy rotor turned to 30: \(said.suffix(2))")
    }
    Settings.rotorEnabled = false
    Settings.rotorAddress = ""
    print("All rotor checks passed.")
}
