// WinKeyer.swift
//
// Sends CW through a K1EL WinKeyer (the author's is a WinKeyer Mini, WK3.1, at
// /dev/cu.usbserial-8410). The WinKeyer keys the radio itself, with its own
// timing; Solid Copy hands it text.
//
// Connecting happens only when you ask (CW > Connect WinKeyer), never at
// launch: Keyer Sidetone uses the same WinKeyer, and only one app can hold
// its port (CLAUDE.md decision, 17 November 2026). If another app has it,
// you hear so.
//
// The WinKeyer's language (K1EL's "WinKeyer3 IC Interface & Operation
// Manual"), at 1200 baud, 8 data bits, 2 stop bits:
//   0x00 0x02   host open: the keyer answers with its version byte, and
//               takes commands until host close
//   0x00 0x03   host close: back to its own saved settings
//   0x02 n      speed, n words per minute (5 to 99)
//   0x0A        clear the buffer: stops sending at once
//   letters     queued and sent as CW, in order
// It reports status as bytes from 0xC0 up: bit 0x04 means "busy" (sending),
// so Solid Copy knows when sending starts and ends (Escape stops it only
// while it's sending). Bytes 0x80 to 0xBF are a speed knob (the Mini has
// none) and printable bytes echo the paddle; both are ignored here.
//
// Nothing is ever written into the WinKeyer's memory. Host close, at quit
// or on disconnecting, leaves it exactly as Keyer Sidetone left it.

import Foundation

@MainActor
final class WinKeyer {
    static let shared = WinKeyer()

    enum State: Equatable {
        case off
        case connected(port: String, version: Int)
    }

    private(set) var state: State = .off { didSet { if state != oldValue { changed() } } }
    // True while the keyer says it's sending.
    private(set) var isSending = false
    var isConnected: Bool { if case .connected = state { return true } else { return false } }

    static let didChange = Notification.Name("SolidCopyWinKeyerDidChange")

    private var port: SerialPort?
    private var reader: DispatchSourceRead?
    // Serial work happens off the main thread, one thing at a time.
    private let queue = DispatchQueue(label: "Solid Copy WinKeyer")

    private func changed() {
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    // Opens the port and host mode, and sets the speed. Calls back with an
    // error in words, or nil.
    func connect(to path: String, wpm: Int, done: @escaping (String?) -> Void) {
        guard !isConnected else { return done(nil) }
        queue.async {
            let result: Result<(SerialPort, Int), Error> = Result {
                let port = try SerialPort(path)
                // The WinKeyer resets as the port opens; give it a moment.
                Thread.sleep(forTimeInterval: 0.3)
                port.discardInput()
                port.write([0x00, 0x02])
                guard let version = port.read(1, timeout: 1.5).first else {
                    port.close()
                    throw SerialPortError.cantOpen("nothing answered; is it a WinKeyer, and plugged in?")
                }
                port.write([0x02, UInt8(Self.clamp(wpm))])
                return (port, Int(version))
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    switch result {
                    case .success(let (port, version)):
                        self.port = port
                        self.listen(to: port)
                        self.state = .connected(port: path, version: version)
                        done(nil)
                    case .failure(let error):
                        done(error.localizedDescription)
                    }
                }
            }
        }
    }

    // Host close, and the port. Safe to call when not connected.
    func disconnect() {
        reader?.cancel()
        reader = nil
        if let port {
            queue.sync {
                port.write([0x0A])          // nothing left half-sent
                port.write([0x00, 0x03])
                port.close()
            }
        }
        port = nil
        isSending = false
        state = .off
    }

    // Queues text to send. Only what CW can carry goes: letters, figures,
    // and / ? . , = + -; anything else is left out (and lower case is
    // made upper). Returns false if not connected.
    @discardableResult
    func send(_ text: String) -> Bool {
        guard let port else { return false }
        let bytes = Array(Self.sendable(text).utf8)
        guard !bytes.isEmpty else { return true }
        queue.async { port.write(bytes) }
        isSending = true
        changed()
        return true
    }

    // Stops at once. Returns true if it was sending (so Escape knows it
    // did something).
    @discardableResult
    func stop() -> Bool {
        guard let port, isSending else { return false }
        queue.async { port.write([0x0A]) }
        isSending = false
        changed()
        return true
    }

    func setSpeed(_ wpm: Int) {
        guard let port else { return }
        let speed = UInt8(Self.clamp(wpm))
        queue.async { port.write([0x02, speed]) }
    }

    nonisolated static func clamp(_ wpm: Int) -> Int { min(max(wpm, 5), 99) }

    // What can be sent: upper case, the characters the WinKeyer knows,
    // single spaces.
    nonisolated static func sendable(_ text: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/?.,=+- ")
        let kept = text.uppercased().filter { allowed.contains($0) }
        return kept.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    // Status bytes: busy on and off. An unplugged keyer ends the
    // connection, said once.
    private func listen(to port: SerialPort) {
        let reader = DispatchSource.makeReadSource(fileDescriptor: port.fileDescriptor, queue: queue)
        reader.setEventHandler { [weak self] in
            guard let bytes = port.readAvailable() else {
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.lost() } }
                return
            }
            // The last status byte in this batch says busy or not.
            guard let status = bytes.last(where: { $0 & 0xC0 == 0xC0 }) else { return }
            let busy = status & 0x04 != 0
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.isSending != busy else { return }
                    self.isSending = busy
                    self.changed()
                }
            }
        }
        reader.resume()
        self.reader = reader
    }

    private func lost() {
        guard isConnected else { return }
        reader?.cancel()
        reader = nil
        port?.close()
        port = nil
        isSending = false
        state = .off
        Speaker.Cue.warning.play()
        Speaker.announce("WinKeyer lost. Plug it back in, then CW > Connect WinKeyer.")
    }
}
