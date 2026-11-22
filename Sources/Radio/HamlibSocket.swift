// HamlibSocket.swift
//
// One conversation with a hamlib network program: rigctld (radios,
// RigctldClient.swift) or rotctld (rotors, RotctldClient.swift). Both take
// one-line text commands and, in the "extended" form with a + in front,
// end every reply with "RPRT n" (0 means it worked), so it's always clear
// where a reply ends.
//
// Calls wait for the network, so they're made from a background queue,
// never the main thread. Every wait has a time limit, so a silent program
// can't hang anything.

import Foundation

// "@unchecked Sendable": used from one background queue at a time.
final class HamlibSocket: @unchecked Sendable {
    let host: String
    let port: UInt16
    // How long to wait for a reply, and to connect.
    private let replySeconds: Int
    private static let connectMilliseconds: Int32 = 2_000

    private var socket: Int32 = -1
    private var buffer: [UInt8] = []

    init(host: String, port: UInt16, replySeconds: Int) {
        self.host = host
        self.port = port
        self.replySeconds = replySeconds
    }

    deinit { disconnect() }

    var isOpen: Bool { socket >= 0 }

    func disconnect() {
        if socket >= 0 { Darwin.close(socket) }
        socket = -1
        buffer.removeAll()
    }

    // Sends an extended command ("+p") and returns its reply's values,
    // without the first line (which repeats the command) and without each
    // line's label ("Azimuth: 21.80" -> "21.80").
    // rigctld closes a connection after some hamlib errors (an "RPRT 10"
    // from a value out of range, say) while carrying on itself, so if an
    // open connection turns out to be closed, it's opened again and the
    // command sent once more, rather than the radio seeming to vanish.
    func values(_ command: String) throws -> [String] {
        let wasOpen = socket >= 0
        do {
            return try valuesOnce(command)
        } catch RadioFailure.notRunning where wasOpen {
            disconnect()
            try connect()
            return try valuesOnce(command)
        }
    }

    private func valuesOnce(_ command: String) throws -> [String] {
        try send(command + "\n")
        var lines: [String] = []
        // A raw reply ("W") ends in a 0 byte, with RPRT straight after it
        // on the same line ("Reply: NR0;\0RPRT 0"), so 0 bytes split lines
        // too.
        var pending: [String] = []
        while true {
            if pending.isEmpty {
                pending = try readLine().split(separator: "\u{0}", omittingEmptySubsequences: false).map(String.init)
            }
            let line = pending.removeFirst()
            if line.hasPrefix("RPRT") {
                // hamlib's error numbers: -5 is a time-out and -6 an
                // input/output error (the radio didn't answer); anything
                // else means it answered "no".
                guard line == "RPRT 0" else {
                    throw ["RPRT -5", "RPRT -6"].contains(line) ? RadioFailure.notAnswering : RadioFailure.rejected
                }
                // The first line repeats the command ("get_freq:").
                return Array(lines.dropFirst())
            }
            lines.append(line.range(of: ": ").map { String(line[$0.upperBound...]) } ?? line)
            // A real reply is a few lines. Anything longer isn't hamlib.
            if lines.count > 20 { disconnect(); throw RadioFailure.notAnswering }
        }
    }

    // MARK: - The connection

    func connect() throws {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &list) == 0 else { throw RadioFailure.notRunning }
        defer { freeaddrinfo(list) }
        var next = list
        while let address = next?.pointee {
            next = address.ai_next
            let candidate = Darwin.socket(address.ai_family, address.ai_socktype, address.ai_protocol)
            guard candidate >= 0 else { continue }
            if Self.connect(candidate, address, replySeconds: replySeconds) {
                socket = candidate
                return
            }
            Darwin.close(candidate)
        }
        throw RadioFailure.notRunning
    }

    // Connects with a time limit. (A plain connect to a far-off address
    // that doesn't answer can wait over a minute.) Then sets the time
    // limits for sending and receiving.
    private static func connect(_ socket: Int32, _ address: addrinfo, replySeconds: Int) -> Bool {
        let flags = fcntl(socket, F_GETFL)
        _ = fcntl(socket, F_SETFL, flags | O_NONBLOCK)
        if Darwin.connect(socket, address.ai_addr, address.ai_addrlen) != 0 {
            guard errno == EINPROGRESS else { return false }
            var waiting = pollfd(fd: socket, events: Int16(POLLOUT), revents: 0)
            var problem: Int32 = 0
            var size = socklen_t(MemoryLayout<Int32>.size)
            guard poll(&waiting, 1, connectMilliseconds) == 1,
                  getsockopt(socket, SOL_SOCKET, SO_ERROR, &problem, &size) == 0, problem == 0 else { return false }
        }
        _ = fcntl(socket, F_SETFL, flags)
        var limit = timeval(tv_sec: replySeconds, tv_usec: 0)
        let limitSize = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &limit, limitSize)
        setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, &limit, limitSize)
        // If the program goes away mid-send, report an error rather than
        // ending Solid Copy (which is what a "broken pipe" does by default).
        var on: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        return true
    }

    private func send(_ text: String) throws {
        let bytes = Array(text.utf8)
        var sent = 0
        while sent < bytes.count {
            let count = bytes[sent...].withUnsafeBytes { Darwin.send(socket, $0.baseAddress, $0.count, 0) }
            guard count > 0 else { disconnect(); throw RadioFailure.notRunning }
            sent += count
        }
    }

    // One line of the reply, without its line ending. Running out of time
    // means the radio didn't answer; the connection closing means rigctld
    // stopped. Either way the connection is dropped, so a late reply
    // can't be mistaken for the answer to the next command.
    private func readLine() throws -> String {
        while true {
            if let end = buffer.firstIndex(of: 10) {
                let line = String(decoding: buffer[..<end], as: UTF8.self)
                buffer.removeSubrange(...end)
                return line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard buffer.count < 4_096 else { disconnect(); throw RadioFailure.notAnswering }
            var chunk = [UInt8](repeating: 0, count: 1_024)
            let count = chunk.withUnsafeMutableBytes { recv(socket, $0.baseAddress, $0.count, 0) }
            if count > 0 {
                buffer += chunk[..<count]
            } else {
                let timedOut = count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)
                disconnect()
                throw timedOut ? RadioFailure.notAnswering : RadioFailure.notRunning
            }
        }
    }
}
