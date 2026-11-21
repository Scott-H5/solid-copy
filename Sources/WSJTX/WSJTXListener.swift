// WSJTXListener.swift
//
// Listens for WSJT-X's UDP messages (WSJTXMessage.swift) at 127.0.0.1
// port 2237, WSJT-X's own default (Settings > Reporting, UDP Server), and
// keeps what the decodes window shows: the latest decodes, newest first,
// and what WSJT-X is doing (its Status).
//
// It listens only while the decodes window is open (Window > WSJT-X
// Decodes), as the Spots window fetches only while open. Only this Mac
// can send to it.
//
// Only one program can listen at port 2237. If another has it (a
// program that shows WSJT-X's decodes on a map, say), Solid Copy says so,
// and WSJT-X can be set to send to both through its multicast setting.
//
// Each WSJT-X sending to it is kept (by its address) so stage 2 can answer
// a station through it (Reply).

import Foundation
import Network

@MainActor
final class WSJTXListener {
    static let shared = WSJTXListener()
    static let didChange = Notification.Name("SolidCopyWSJTXDidChange")
    nonisolated static let standardPort: UInt16 = 2237

    // How many decodes are kept, and for how long. FT8 is about 20 a
    // period on a busy band; 15 minutes is plenty to look back over.
    static let mostKept = 400
    static let keptFor: TimeInterval = 15 * 60

    // Newest first.
    private(set) var decodes: [(decode: WSJTXDecode, heard: Date)] = []
    private(set) var status: WSJTXStatus?
    private(set) var lastHeard: Date?
    // The WSJT-X version from its Heartbeat ("3.0.1").
    private(set) var version: String?
    // Why it isn't listening, if it isn't (the port is taken, say).
    private(set) var problem: String?

    private var listener: NWListener?
    private var listeningPort: UInt16?
    private var senders: [String: NWConnection] = [:]

    var isListening: Bool { listener != nil }

    func start(port: UInt16 = standardPort) {
        if listener != nil, listeningPort == port { return }
        stop()
        problem = nil
        let parameters = NWParameters.udp
        // This Mac only.
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do { listener = try NWListener(using: parameters) } catch {
            problem = "Solid Copy couldn't listen for WSJT-X: \(error.localizedDescription)"
            return changed()
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, case .failed(let error) = state else { return }
                self.stop()
                self.problem = error.errorCode == Int(EADDRINUSE)
                    ? "Another program has port \(port), so Solid Copy can't hear WSJT-X. Quit it, or have WSJT-X "
                        + "send to a multicast address both can hear."
                    : "Solid Copy stopped listening for WSJT-X: \(error.localizedDescription)"
                self.changed()
            }
        }
        self.listener = listener
        listeningPort = port
        listener.start(queue: .main)
        changed()
    }

    func stop() {
        listener?.cancel()
        listener = nil
        listeningPort = nil
        for connection in senders.values { connection.cancel() }
        senders = [:]
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let data, let message = WSJTXMessage.parse(data) { self.handle(message, from: connection) }
                if error == nil, self.listener != nil { self.receive(on: connection) } else { connection.cancel() }
            }
        }
    }

    // What each message changes. Public so the check can feed it messages.
    func handle(_ message: WSJTXMessage, from connection: NWConnection? = nil, now: Date = Date()) {
        lastHeard = now
        switch message {
        case .heartbeat(let id, let version):
            remember(connection, for: id)
            self.version = version.isEmpty ? self.version : version
        case .status(let status):
            remember(connection, for: status.id)
            self.status = status
        case .decode(let decode):
            remember(connection, for: decode.id)
            // A replay of old decodes (WSJT-X sends them again when a
            // program connects) isn't added twice.
            guard !decodes.contains(where: { $0.decode == decode }) else { return }
            decodes.insert((decode, now), at: 0)
            decodes.removeAll { now.timeIntervalSince($0.heard) > Self.keptFor }
            if decodes.count > Self.mostKept { decodes.removeLast(decodes.count - Self.mostKept) }
        case .clear:
            // WSJT-X's Erase: its band activity is cleared, so the list is too.
            decodes = []
        case .close(let id):
            senders[id]?.cancel()
            senders[id] = nil
            if status?.id == id { status = nil }
        case .loggedADIF, .other:
            break
        }
        changed()
    }

    private func remember(_ connection: NWConnection?, for id: String) {
        guard let connection, senders[id] !== connection else { return }
        senders[id] = connection
    }

    private func changed() {
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    // For the check: start empty.
    func reset() {
        decodes = []
        status = nil
        lastHeard = nil
        version = nil
    }
}
