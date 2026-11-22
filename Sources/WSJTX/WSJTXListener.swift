// WSJTXListener.swift
//
// Listens for WSJT-X's UDP messages (WSJTXMessage.swift) at 127.0.0.1
// port 2237, WSJT-X's own default (Settings > Reporting, UDP Server), and
// keeps what the decodes window shows: the latest decodes, newest first,
// and what WSJT-X is doing (its Status).
//
// It listens while the decodes window is open (Window > WSJT-X
// Decodes), or all the time if Settings > Radio says so
// (WSJTXAlerts.swift). Only this Mac can send to it.
//
// Only one program can listen at port 2237. If another has it (a
// program that shows WSJT-X's decodes on a map, say), Solid Copy says so,
// and WSJT-X can be set to send to both through its multicast setting.
//
// Each WSJT-X sending to it is kept (by its address), so Solid Copy can
// answer through it: Reply (call a station) and Halt Tx (stop
// transmitting) go back the way its messages came.

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
    // Told the ADIF of each contact WSJT-X logs (WSJTXLogging.swift), so
    // the app can add it to the log.
    var onLoggedADIF: ((String) -> Void)?
    // Why it isn't listening, if it isn't (the port is taken, say).
    private(set) var problem: String?

    private var listener: NWListener?
    private var listeningPort: UInt16?
    private var senders: [String: NWConnection] = [:]
    // Where each WSJT-X last sent from (its address and port). Kept when
    // listening stops, so a WSJT-X sending from somewhere new is known to
    // be a new run of it (quit and opened again), whose Band Activity
    // starts empty: Solid Copy's older decodes are cleared then, since
    // WSJT-X can't answer a station it no longer has.
    private var lastEndpoint: [String: String] = [:]

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
                if let data, let message = WSJTXMessage.parse(data) {
                    self.handle(message, from: connection, endpoint: "\(connection.endpoint)")
                }
                if error == nil, self.listener != nil { self.receive(on: connection) } else { connection.cancel() }
            }
        }
    }

    // What each message changes. Public so the check can feed it messages.
    func handle(_ message: WSJTXMessage, from connection: NWConnection? = nil, endpoint: String? = nil,
                now: Date = Date()) {
        lastHeard = now
        if let endpoint { noteEndpoint(endpoint, for: messageID(message)) }
        switch message {
        case .heartbeat(let id, let version):
            remember(connection, for: id)
            // Still running: its mode stays good (Status only comes on a change).
            if let mode = RadioReading.digitalMode, status != nil {
                RadioReading.digitalMode = (mode.mode, mode.submode, now)
            }
            self.version = version.isEmpty ? self.version : version
        case .status(let status):
            remember(connection, for: status.id)
            self.status = status
            // So a contact logged with the radio in a data mode gets
            // WSJT-X's mode (RadioReading.digitalMode).
            if let adif = WSJTXStatus.adifMode(status.mode) {
                RadioReading.digitalMode = (adif.mode, adif.submode, now)
            }
            // WSJT-X took a Reply: its DX call is now that station.
            if let watch = answerWatch, Callsign.normalized(status.dxCall) == watch.call { finishAnswer(.sent) }
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
            // WSJT-X quit: its decodes go with it (a new run won't know them).
            senders[id]?.cancel()
            senders[id] = nil
            lastEndpoint[id] = nil
            if status?.id == id { status = nil }
            decodes.removeAll { $0.decode.id == id }
        case .loggedADIF(let id, let adif):
            remember(connection, for: id)
            onLoggedADIF?(adif)
        case .other:
            break
        }
        changed()
    }

    // Sends a message to the WSJT-X with this id (or the only one, if
    // there's one). false if no WSJT-X has been heard to send it to.
    // `sent` is told once it's gone; the check swaps in its own.
    var sendHook: ((Data) -> Void)?
    @discardableResult
    func send(_ data: Data, to id: String? = nil) -> Bool {
        if let sendHook { sendHook(data); return true }
        let connection = id.flatMap { senders[$0] } ?? (senders.count == 1 ? senders.values.first : nil)
        guard let connection else { return false }
        connection.send(content: data, completion: .contentProcessed { _ in })
        return true
    }

    // Asks WSJT-X to call the station that sent `decode` (Reply), then
    // watches its Status for that call as its DX call, so Solid Copy can
    // say whether WSJT-X took it. `done` gets: "sent" (WSJT-X is calling
    // it), "ignored" (no sign within `wait` seconds: most likely Accept
    // UDP requests is off), or "unheard" (no WSJT-X to send to).
    enum Answer { case sent, ignored, unheard }
    private var answerWatch: (call: String, done: (Answer) -> Void, timer: Timer)?

    func answer(_ decode: WSJTXDecode, call: String, wait: TimeInterval = 4,
                done: @escaping (Answer) -> Void) {
        finishAnswer(nil)
        // Already calling that station: WSJT-X's DX call won't change, so no
        // Status would come to confirm it; it's calling it now.
        let alreadyCalling = status.map { Callsign.normalized($0.dxCall) == Callsign.normalized(call) } ?? false
        guard send(WSJTXMessage.reply(to: decode), to: decode.id) else { return done(.unheard) }
        if alreadyCalling { return done(.sent) }
        let timer = Timer(timeInterval: wait, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishAnswer(.ignored) }
        }
        RunLoop.main.add(timer, forMode: .common)
        answerWatch = (Callsign.normalized(call), done, timer)
    }

    private func finishAnswer(_ result: Answer?) {
        guard let watch = answerWatch else { return }
        answerWatch = nil
        watch.timer.invalidate()
        if let result { watch.done(result) }
    }

    // Stop transmitting now (Halt Tx). false if no WSJT-X has been heard.
    @discardableResult
    func haltTransmitting() -> Bool {
        send(WSJTXMessage.haltTx(id: status?.id ?? "WSJT-X"), to: status?.id)
    }

    private func messageID(_ message: WSJTXMessage) -> String {
        switch message {
        case .heartbeat(let id, _), .clear(let id), .loggedADIF(let id, _), .close(let id), .other(let id, _): id
        case .status(let status): status.id
        case .decode(let decode): decode.id
        }
    }

    // A WSJT-X sending from a new address is a new run of it: clear the
    // decodes the old one had (see lastEndpoint).
    private func noteEndpoint(_ endpoint: String, for id: String) {
        if let last = lastEndpoint[id], last != endpoint {
            decodes.removeAll { $0.decode.id == id }
        }
        lastEndpoint[id] = endpoint
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
        lastEndpoint = [:]
    }
}
