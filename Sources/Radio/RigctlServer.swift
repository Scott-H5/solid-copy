// RigctlServer.swift
//
// Lets other programs (iDigi, WSJT-X, anything with "Hamlib NET rigctl")
// use the radio through Solid Copy, while you keep logging: Solid Copy
// answers the network commands hamlib's rigctld would, at 127.0.0.1 port
// 4532, and passes them to the radio through the built-in driver. So
// there's no rigctld to run, and no switching drivers to share the radio.
// Turned on in Settings > Radio ("Share the radio with other programs").
//
// Only this Mac can connect (127.0.0.1): nothing on the network can tune
// your radio.
//
// Programs can read and set frequency, mode, VFO and split. Transmit
// (PTT, "T 1") only when "Let them transmit" is also on (allowTransmit);
// otherwise it's refused and nothing is sent. When it is on, these keep
// the radio from being left transmitting:
//   - only one program keys it at a time, and any "T 0" unkeys it;
//   - the program that keyed it going (closing, crashing, a lost
//     connection) unkeys it;
//   - sharing turned off, the radio changed, or Solid Copy quitting unkeys
//     it (at quit, waiting for the radio: unkeyNow);
//   - after transmitLimit (5 minutes, longer than any digital-mode
//     transmission a program makes in one go) it's unkeyed anyway, and
//     that's said.
// The first transmission from each program is said, so the radio never
// goes on the air without you knowing; later ones aren't, since FT8 keys
// every 15 seconds.
//
// The protocol, as hamlib 4.7's network client (netrigctl) speaks it,
// recorded on 20 November 2026 between rigctl -m 2 and rigctld -m 1:
//   - One command per line. A question is answered with its values, one
//     per line ("f" -> "7074000"); a change with "RPRT 0" when it worked,
//     or "RPRT -n" (a hamlib error number) when it didn't.
//   - On connecting, the client asks \get_powerstat (1: on), \chk_vfo (0:
//     no VFO argument in commands) and \dump_state: what the radio can do,
//     in a fixed order of lines, then key=value lines ending in "done".
//   - Then it polls: f (frequency), m (mode and filter width), v (VFO),
//     s (split), t (transmitting), and sets with F, M, V, S, T.
// Commands also have long names (\get_freq is f); both are understood.
//
// Questions are answered from the reading Solid Copy already has (it reads
// the radio every second), so a program polling quickly doesn't load the
// radio's serial port. Changes go to the radio one at a time, through the
// same queue as Solid Copy's own (RadioMonitor.change), and are read back,
// so the next question has the radio's real answer.

import Foundation
import Network

// What the server needs from the radio. RadioMonitor is the real one
// (RigctlSharing.swift); the check (tools/rigctl-check) uses a pretend one.
@MainActor
protocol RigctlRadio: AnyObject {
    var reading: RadioReading? { get }
    var status: RadioStatus? { get }
    // hamlib's model number, for \dump_state.
    var model: Int { get }
    // The radio's most power, in watts (for \dump_state's transmit range).
    var maxWatts: Double { get }
    // Sends one change ("F 7074000", "M PKTUSB 0", "T 1"); `done` says if
    // it worked.
    func send(_ command: String, done: @escaping @MainActor (Bool) -> Void)
    // Back to receive now, waiting for the radio: for quitting.
    func receiveNow()
}

@MainActor
final class RigctlServer {
    // rigctld's usual port, what programs offer by default.
    nonisolated static let standardPort: UInt16 = 4532

    private let radio: RigctlRadio
    private var listener: NWListener?
    private var listeningPort: UInt16?
    private var connections: [ObjectIdentifier: Client] = [:]
    // Told when listening fails (another program has the port, say), and
    // when it starts and stops; the app speaks and lists these.
    var onEvent: (String, Bool) -> Void = { _, _ in }
    // Told when a program connects (true) or goes (false), with how many
    // are connected now, so you can tell iDigi has really reached the
    // radio.
    var onConnection: (Bool, Int) -> Void = { _, _ in }
    // Told about transmitting: what to say, and whether to speak it (the
    // first transmission from a program, and every unkeying Solid Copy did
    // itself) or only list it.
    var onTransmit: (String, Bool) -> Void = { _, _ in }
    // Told about a command Solid Copy refused or didn't know, once per
    // program and kind of command (not every poll): what to say, and
    // whether to speak it (a refused transmit) or only list it. For
    // finding out what a program wants that isn't here yet.
    var onRefused: (String, Bool) -> Void = { _, _ in }

    // Settings > Radio, "Let them transmit". Checked on each "T 1", so a
    // change takes effect at once, with no reconnecting; turning it off
    // also unkeys at once.
    var allowTransmit = false {
        didSet {
            guard !allowTransmit else { return }
            keying = nil
            unkey(saying: "Transmitting stopped: other programs may no longer transmit.")
        }
    }
    // The longest one transmission may last before Solid Copy unkeys.
    var transmitLimit: TimeInterval = 300
    // The program that keyed the radio, while it's transmitting.
    private var keyedBy: ObjectIdentifier?
    // The program whose "T 1" is on its way to the radio. Cleared if it
    // goes (or sharing stops) meanwhile, so the radio is then unkeyed.
    private var keying: ObjectIdentifier?
    private var limitTimer: Timer?
    // Programs whose first transmission has been said.
    private var announced: Set<ObjectIdentifier> = []

    var isTransmitting: Bool { keyedBy != nil }

    init(radio: RigctlRadio) { self.radio = radio }

    var isRunning: Bool { listener != nil }

    // Starts or stops listening, to match what's wanted. Nothing happens if
    // it's already that way.
    func run(_ wanted: Bool, port: UInt16 = standardPort) {
        if wanted, listener != nil, listeningPort == port { return }
        stop()
        guard wanted else { return }
        let parameters = NWParameters.tcp
        // This Mac only.
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do { listener = try NWListener(using: parameters) } catch {
            return onEvent("The radio couldn't be shared: \(error.localizedDescription)", false)
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.listenerChanged(state, port: port) }
        }
        self.listener = listener
        listeningPort = port
        listener.start(queue: .main)
    }

    private func stop() {
        keying = nil
        unkey(saying: "Transmitting stopped: the radio isn't shared now.")
        listener?.cancel()
        listener = nil
        listeningPort = nil
        for client in connections.values { client.close() }
        connections = [:]
    }

    private func listenerChanged(_ state: NWListener.State, port: UInt16) {
        switch state {
        case .ready:
            onEvent("Sharing the radio at 127.0.0.1 port \(port).", true)
        case .failed(let error):
            // Most likely another program (a rigctld) already has the port.
            stop()
            let inUse = (error.errorCode == Int(EADDRINUSE))
            onEvent(inUse ? "The radio isn't shared: another program, perhaps a rigctld, has port \(port)."
                          : "The radio isn't shared: \(error.localizedDescription)", false)
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        let client = Client(connection: connection, server: self)
        connections[ObjectIdentifier(client)] = client
        client.start()
        onConnection(true, connections.count)
    }

    fileprivate func closed(_ client: Client) {
        // (A connection can report closing more than once; count it once.)
        guard connections.removeValue(forKey: ObjectIdentifier(client)) != nil else { return }
        announced.remove(ObjectIdentifier(client))
        if keying == ObjectIdentifier(client) { keying = nil }
        if keyedBy == ObjectIdentifier(client) {
            unkey(saying: "Transmitting stopped: the program that was transmitting went.")
        }
        onConnection(false, connections.count)
    }

    // MARK: - Answers

    // hamlib's error numbers, as rigctld sends them.
    private static let ok = "RPRT 0\n"
    private static let notImplemented = "RPRT -4\n"   // RIG_ENIMPL: no such command here
    private static let timedOut = "RPRT -5\n"          // RIG_ETIMEOUT: the radio isn't answering
    private static let invalid = "RPRT -1\n"           // RIG_EINVAL: a bad value
    private static let refused = "RPRT -9\n"           // RIG_ERJCTED: the radio said no
    private static let unavailable = "RPRT -11\n"      // RIG_ENAVAIL: not available (transmit, for now)

    // Long command names, as their short letters.
    private static let longNames = [
        "\\get_freq": "f", "\\set_freq": "F", "\\get_mode": "m", "\\set_mode": "M", "\\get_vfo": "v",
        "\\set_vfo": "V", "\\get_ptt": "t", "\\set_ptt": "T", "\\get_split_vfo": "s", "\\set_split_vfo": "S",
        "\\get_level": "l", "\\get_split_freq": "i", "\\set_split_freq": "I", "\\get_split_mode": "x",
        "\\set_split_mode": "X", "\\quit": "q",
    ]

    // One command line's answer, from `client` (the program that sent it).
    // `done` gets the text to send back, or nil to close the connection
    // ("q").
    func answer(_ line: String, from client: ObjectIdentifier? = nil,
                done: @escaping @MainActor (String?) -> Void) {
        var words = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard !words.isEmpty else { return done("") }
        if let short = Self.longNames[words[0]] { words[0] = short }
        let reading = radio.reading
        switch words[0] {
        case "q", "Q":
            return done(nil)
        case "\\get_powerstat":
            return done("1\n")
        case "\\chk_vfo":
            return done("0\n")
        case "\\dump_state":
            return done(dumpState())
        case "\\get_lock_mode":
            // rigctld answers this one with the value and then RPRT 0, and
            // hamlib's client reads both (recorded from rigctld 4.7.2).
            return done("0\nRPRT 0\n")
        case "f", "i":
            return done(reading.map { "\($0.hertz)\n" } ?? Self.timedOut)
        case "m", "x":
            return done(reading.map { "\($0.mode)\n\($0.passband ?? 0)\n" } ?? Self.timedOut)
        case "v":
            guard reading != nil else { return done(Self.timedOut) }
            return done("\(radio.status?.vfo ?? "VFOA")\n")
        case "s":
            guard reading != nil else { return done(Self.timedOut) }
            return done(radio.status?.split == true ? "1\nVFOB\n" : "0\nNone\n")
        case "t":
            return done(isTransmitting ? "1\n" : "0\n")
        case "l":
            guard words.count == 2, words[1] == "KEYSPD" else { return done(Self.unavailable) }
            return done("\(radio.status?.keyerWPM ?? 0)\n")
        case "T":
            guard words.count == 2, let value = Int(words[1]), (0...3).contains(value) else {
                return done(Self.invalid)
            }
            return value == 0 ? receive(done) : transmit(value, from: client ?? ObjectIdentifier(self), done)
        case "F":
            // "F 7074000.000000": hertz, sometimes with decimals.
            guard words.count == 2, let hertz = Double(words[1]), hertz > 0, hertz < 1e10 else {
                return done(Self.invalid)
            }
            // Already there: nothing to send. Programs re-send the frequency
            // constantly (WSJT-X, even while transmitting, when the TS-590
            // refuses any frequency command), so this saves the radio's port
            // and a needless refusal.
            let target = Int(hertz.rounded())
            if radio.reading?.hertz == target { return done(Self.ok) }
            return change("F \(target)", done)
        case "M":
            // "M PKTUSB 3000": a width of 0 or -1 means the radio's usual one.
            guard words.count == 3, let width = Int(words[2]) else { return done(Self.invalid) }
            let mode = words[1].uppercased()
            // Already in that mode, with no new width: nothing to send.
            if radio.reading?.mode == mode, width <= 0 { return done(Self.ok) }
            // While a program transmits, a mode request isn't sent: the radio
            // won't change mode on the air, and programs re-send the mode
            // they already set (WSJT-X's "M PKTUSB -1" before and during each
            // transmission). It's taken again once the radio is receiving.
            if isTransmitting { return done(Self.ok) }
            return change("M \(mode) \(max(width, 0))", done)
        case "V":
            guard words.count == 2 else { return done(Self.invalid) }
            if words[1] == "currVFO" { return done(Self.ok) }
            return change("V \(words[1])", done)
        case "S":
            guard words.count == 3, words[1] == "0" || words[1] == "1" else { return done(Self.invalid) }
            return change("S \(words[1]) \(words[1] == "1" ? "VFOB" : "VFOA")", done)
        case "I", "X":
            return done(Self.unavailable)
        default:
            return done(Self.notImplemented)
        }
    }

    // MARK: - Transmitting

    private func transmit(_ value: Int, from client: ObjectIdentifier,
                          _ done: @escaping @MainActor (String?) -> Void) {
        guard allowTransmit else { return done(Self.unavailable) }
        guard radio.reading != nil else { return done(Self.timedOut) }
        // Another program is on the air: one at a time.
        if let keyedBy, keyedBy != client { return done(Self.refused) }
        keying = client
        radio.send("T \(value)") { [self] worked in
            // The program went (or sharing stopped) while the radio was
            // being keyed: back to receive at once.
            guard keying == client else {
                if worked { radio.send("T 0") { _ in } }
                return done(Self.refused)
            }
            keying = nil
            guard worked else { return done(Self.refused) }
            keyedBy = client
            limitTimer?.invalidate()
            let timer = Timer(timeInterval: transmitLimit, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let minutes = Int((self.transmitLimit / 60).rounded())
                    self.unkey(saying: "Transmitting stopped after \(minutes) minutes, Solid Copy's limit.")
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            limitTimer = timer
            let first = announced.insert(client).inserted
            if first { onTransmit("A program is transmitting through Solid Copy.", true) }
            done(Self.ok)
        }
    }

    // "T 0". Only sent to the radio if a program keyed it here: a program
    // saying "receive" mustn't cut off you transmitting with the
    // microphone's own PTT.
    private func receive(_ done: @escaping @MainActor (String?) -> Void) {
        guard keyedBy != nil else { return done(Self.ok) }
        keyedBy = nil
        limitTimer?.invalidate()
        limitTimer = nil
        radio.send("T 0") { worked in done(worked ? Self.ok : Self.refused) }
    }

    // Solid Copy unkeys the radio itself (a safeguard), and says why.
    private func unkey(saying why: String) {
        guard keyedBy != nil else { return }
        keyedBy = nil
        limitTimer?.invalidate()
        limitTimer = nil
        radio.send("T 0") { _ in }
        onTransmit(why, true)
    }

    // At quit: back to receive, waiting for the radio, since there's no
    // later.
    func unkeyNow() {
        guard keyedBy != nil else { return }
        keyedBy = nil
        limitTimer?.invalidate()
        limitTimer = nil
        radio.receiveNow()
    }

    // A refusal, put in words (see onRefused). `reply` is "RPRT -n".
    fileprivate func refused(_ line: String, reply: String) {
        let words = line.split(separator: " ")
        let transmit = words.first == "T" && words.count == 2 && words[1] != "0"
        let why: String
        switch reply.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "RPRT -4": why = "Solid Copy doesn't know that command"
        case "RPRT -11": why = transmit ? "Let them transmit is off" : "Solid Copy can't do that"
        case "RPRT -9": why = transmit ? "another program is transmitting, or the radio said no" : "the radio said no"
        case "RPRT -5": why = "the radio isn't answering"
        case "RPRT -1": why = "the value wasn't understood"
        default: why = "it was refused (\(reply.trimmingCharacters(in: .whitespacesAndNewlines)))"
        }
        if transmit {
            onRefused("A program tried to transmit, but \(why).", true)
        } else {
            onRefused("A program asked for \"\(line)\", but \(why).", false)
        }
    }

    private func change(_ command: String, _ done: @escaping @MainActor (String?) -> Void) {
        guard radio.reading != nil else { return done(Self.timedOut) }
        radio.send(command) { worked in done(worked ? Self.ok : Self.refused) }
    }

    // What the radio can do, in the order hamlib's network client reads it
    // (rigctld's own \dump_state). Mode bits are hamlib's: AM 0x1, CW 0x2,
    // USB 0x4, LSB 0x8, RTTY 0x10, FM 0x20, CWR 0x80, RTTYR 0x100, PKTLSB
    // 0x400, PKTUSB 0x800: 0xdbf is all of them.
    func dumpState() -> String {
        let modes = "0xdbf"
        let milliwatts = Int(radio.maxWatts * 1000)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let lines = [
            "1",                         // protocol version
            "\(radio.model)",            // the radio's hamlib model
            "0",                         // ITU region (not used)
            // Receive range: low, high, modes, low power, high power, VFOs, antennas.
            "30000.000000 60000000.000000 \(modes) -1 -1 0x3 0x1",
            "0 0 0 0 0 0 0",
            // Transmit range, the HF bands to 6 m.
            "1800000.000000 54000000.000000 \(modes) 1000 \(milliwatts) 0x3 0x1",
            "0 0 0 0 0 0 0",
            // Tuning steps.
            "\(modes) 1", "\(modes) 10", "\(modes) 100", "\(modes) 1000",
            "0 0",
            // Filters: SSB, CW, data, AM, FM.
            "0xc 2400", "0x82 500", "0x82 250", "0xc00 2400", "0xc00 500", "0x1 6000", "0x20 12000",
            "0 0",
            "9990",                      // most RIT
            "9990",                      // most XIT
            "0",                         // most IF shift
            "0",                         // announcements
            "12 ",                       // preamps (dB)
            "12 ",                       // attenuators (dB)
            "0x0", "0x0",                // functions it can read, set (none offered)
            "0x0", "0x0",                // levels
            "0x0", "0x0",                // parameters
            "vfo_ops=0x0",
            // 1 (RIG_PTT_RIG): keying goes through Solid Copy. Always 1,
            // even with Let them transmit off: a program reads this only
            // when it connects, and with 0 its hamlib refuses PTT itself
            // until it reconnects (found with iDigi, 20 November 2026). So
            // Solid Copy refuses "T 1" itself instead, which follows the
            // checkbox at once.
            "ptt_type=0x1",
            "targetable_vfo=0x0",
            "has_set_vfo=1", "has_get_vfo=1", "has_set_freq=1", "has_get_freq=1",
            "has_set_conf=0", "has_get_conf=0", "has_power2mW=0", "has_mW2power=0",
            "timeout=0",
            "rig_model=\(radio.model)",
            "rigctld_version=Solid Copy \(version)",
            "done",
        ]
        return lines.joined(separator: "\n") + "\n"
    }
}

// One program connected. Its lines are answered in order, one at a time,
// so a change finishes before the next question is answered.
@MainActor
private final class Client {
    private let connection: NWConnection
    private weak var server: RigctlServer?
    private var buffer = Data()
    private var lines: [String] = []
    private var busy = false
    private var closing = false
    // Kinds of command already reported as refused (the first word, and
    // for T its value), so a program polling one doesn't flood Activity.
    private var reportedRefusals: Set<String> = []

    // A line longer than this isn't a rigctl command; the program is closed.
    private static let longestLine = 4096

    init(connection: NWConnection, server: RigctlServer) {
        self.connection = connection
        self.server = server
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .failed, .cancelled: self?.finished()
                default: break
                }
            }
        }
        connection.start(queue: .main)
        receive()
    }

    func close() {
        closing = true
        connection.cancel()
    }

    private func finished() {
        closing = true
        server?.closed(self)
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let data { self.buffer.append(data) }
                self.splitLines()
                // The program closed its end, or the connection failed:
                // close ours. After "q" ("closing"), stop reading but let
                // the goodbye go out first; its send closes the connection.
                if isComplete || error != nil {
                    self.close()
                } else if !self.closing {
                    self.receive()
                }
            }
        }
    }

    private func splitLines() {
        while let end = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = String(decoding: buffer[buffer.startIndex..<end], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...end)
            lines.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if buffer.count > Self.longestLine { return close() }
        next()
    }

    private func next() {
        guard !busy, !closing, !lines.isEmpty, let server else { return }
        busy = true
        let line = lines.removeFirst()
        server.answer(line, from: ObjectIdentifier(self)) { [weak self] reply in
            guard let self else { return }
            self.busy = false
            guard let reply else {
                // "q": the program is done. Close once the goodbye is sent.
                self.closing = true
                return self.connection.send(content: Data("RPRT 0\n".utf8), completion: .contentProcessed {
                    [weak self] _ in MainActor.assumeIsolated { self?.close() }
                })
            }
            if !reply.isEmpty {
                self.connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in })
            }
            if reply.hasPrefix("RPRT -") {
                let words = line.split(separator: " ")
                let kind = words.first == "T" ? words.prefix(2).joined(separator: " ") : String(words.first ?? "")
                if self.reportedRefusals.insert(kind).inserted { self.server?.refused(line, reply: reply) }
            }
            self.next()
        }
    }
}
