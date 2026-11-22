// RotctldClient.swift
//
// Talks to rotctld, hamlib's rotor-control program, over a network
// connection (usually this Mac, 127.0.0.1, port 4533). You run rotctld
// for your rotor's model and port, as with rigctld for a radio; Solid Copy
// has no rotor drivers of its own.
//
// The commands used, in the extended form (HamlibSocket.swift), as
// rotctld 4.7.2 answers them (its dummy rotor, `rotctld -m 1`):
//
//   +p          ->  get_pos:              where it's pointing
//                   Azimuth: 21.80
//                   Elevation: 0.00
//                   RPRT 0
//   +P 120 0    ->  set_pos: 120 0        turn to 120 degrees, elevation 0
//                   RPRT 0
//   +S          ->  stop:                 stop turning
//                   RPRT 0
//
// set_pos returns at once; the rotor then turns at its own speed (the
// dummy, about 6 degrees a second), so RotorControl asks where it is
// until it gets there. The calls wait for the network, so they're made
// from RotorControl's background queue, never the main thread.

import Foundation

// "@unchecked Sendable": used only from RotorControl's one queue.
final class RotctldClient: @unchecked Sendable {
    typealias Failure = RadioFailure

    let host: String
    let port: UInt16
    private let link: HamlibSocket

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
        // A rotor controller answers quickly; it doesn't wait for the turn.
        link = HamlibSocket(host: host, port: port, replySeconds: 5)
    }

    // Where "host:port" (or "", or a host alone) points: rotctld's usual
    // port, 4533, unless another is given.
    static func address(_ text: String) -> (host: String, port: UInt16) {
        let text = text.trimmingCharacters(in: .whitespaces)
        let parts = text.split(separator: ":")
        if parts.count == 2, let port = UInt16(parts[1]), port > 0 { return (String(parts[0]), port) }
        return (text.isEmpty ? "127.0.0.1" : text, 4533)
    }

    func disconnect() { link.disconnect() }

    // The heading it's pointing at, 0 to 359.9 (a rotor that turns past
    // north, to 450, says 400 for 40).
    func azimuth() throws -> Double {
        let values = try ask("+p")
        guard let first = values.first, let degrees = Double(first), degrees.isFinite,
              (-360...720).contains(degrees) else { throw Failure.notAnswering }
        return Rotor.normalized(degrees)
    }

    // Starts turning to a heading (0 to 359.9). It doesn't wait for the turn.
    func turn(to heading: Double) throws {
        _ = try ask("+P \(String(format: "%.1f", Rotor.normalized(heading))) 0")
    }

    func stop() throws { _ = try ask("+S") }

    private func ask(_ command: String) throws -> [String] {
        if !link.isOpen { try link.connect() }
        return try link.values(command)
    }
}

// Headings, worked out apart from any rotor so they can be checked.
enum Rotor {
    // 0 up to (not including) 360: -10 is 350, 400 is 40.
    static func normalized(_ degrees: Double) -> Double {
        let turned = degrees.truncatingRemainder(dividingBy: 360)
        let positive = turned < 0 ? turned + 360 : turned
        // Rounded to a tenth, so 359.96 is 0, not "360".
        let rounded = (positive * 10).rounded() / 10
        return rounded >= 360 ? 0 : rounded
    }

    // The long way round: the opposite heading.
    static func longPath(_ bearing: Double) -> Double { normalized(bearing + 180) }

    // How far apart two headings are, the short way (0 to 180).
    static func apart(_ a: Double, _ b: Double) -> Double {
        let difference = abs(normalized(a) - normalized(b))
        return min(difference, 360 - difference)
    }

    // "285 degrees, west": whole degrees and the compass point.
    static func spoken(_ degrees: Double) -> String {
        let whole = Int(normalized(degrees).rounded()) % 360
        return "\(whole) degrees, \(GreatCircle.compass(Double(whole)))"
    }

    // A heading typed in Turn Rotor To…: whole or decimal degrees, 0 to
    // 360 (360 is north, 0). Nil for anything else.
    static func typed(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "°", with: "")
        guard let degrees = Double(cleaned), degrees.isFinite, (0...360).contains(degrees) else { return nil }
        return normalized(degrees)
    }
}
