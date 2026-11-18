// SerialPort.swift
//
// A thin wrapper around the Mac's standard (POSIX) serial calls: open a
// port, set its speed and format with "termios", then read and write
// bytes. Used for the WinKeyer (WinKeyer.swift). Copied from Keyer
// Sidetone, where it was tested with the same WinKeyer Mini; kept as its
// own copy because Solid Copy uses no shared packages.
//
// The radio doesn't use this: hamlib's rigctld opens the radio's port.

import Foundation

enum SerialPortError: Error, LocalizedError {
    case inUse
    case cantOpen(String)

    var errorDescription: String? {
        switch self {
        case .inUse: "Another app is using it. Quit any other app using the WinKeyer, then try again."
        case .cantOpen(let why): "The port couldn't be opened: \(why)."
        }
    }
}

final class SerialPort {
    private var fd: Int32

    var fileDescriptor: Int32 { fd }

    // 8 data bits, no parity; two stop bits for the WinKeyer's 1200 baud.
    init(_ path: String, baud: speed_t = speed_t(B1200), twoStopBits: Bool = true) throws {
        // O_NONBLOCK: don't wait for a modem "carrier" signal while opening.
        fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            if errno == EBUSY { throw SerialPortError.inUse }
            throw SerialPortError.cantOpen(String(cString: strerror(errno)))
        }
        // Exclusive: while Solid Copy has it, no other app can open it too
        // (and one that already has it makes this fail with EBUSY).
        guard ioctl(fd, TIOCEXCL) == 0 else {
            Darwin.close(fd)
            fd = -1
            throw SerialPortError.inUse
        }
        var t = termios()
        tcgetattr(fd, &t)
        cfmakeraw(&t)                       // bytes in and out exactly as sent
        cfsetspeed(&t, baud)
        t.c_cflag |= tcflag_t(CS8 | CLOCAL | CREAD | (twoStopBits ? CSTOPB : 0))
        t.c_cflag &= ~tcflag_t(PARENB | CRTSCTS)
        tcsetattr(fd, TCSANOW, &t)
    }

    deinit { close() }

    func write(_ bytes: [UInt8]) {
        guard fd >= 0, !bytes.isEmpty else { return }
        _ = bytes.withUnsafeBufferPointer { Darwin.write(fd, $0.baseAddress, $0.count) }
        tcdrain(fd)   // wait until they have actually gone out
    }

    // Reads up to `count` bytes, giving up after `timeout` seconds.
    func read(_ count: Int, timeout: Double) -> [UInt8] {
        var out: [UInt8] = []
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 64)
        while out.count < count {
            let wait = deadline.timeIntervalSinceNow
            guard wait > 0 else { break }
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&p, 1, Int32(wait * 1000)) > 0 else { break }
            let n = Darwin.read(fd, &buffer, min(buffer.count, count - out.count))
            if n <= 0 { break }
            out += buffer.prefix(n)
        }
        return out
    }

    // Whatever has arrived, without waiting: empty if nothing has, or nil
    // if the port has gone (unplugged).
    func readAvailable() -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: 64)
        let n = Darwin.read(fd, &buffer, buffer.count)
        if n > 0 { return Array(buffer.prefix(n)) }
        if n < 0 && (errno == EAGAIN || errno == EINTR) { return [] }
        return nil
    }

    func discardInput() { tcflush(fd, TCIFLUSH) }

    func close() {
        if fd >= 0 { Darwin.close(fd) }
        fd = -1
    }

    // The Mac's serial ports, for choosing the WinKeyer's: /dev/cu.* less
    // Bluetooth and the built-in debug ports nobody keys a radio with.
    static func available() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return names.filter { $0.hasPrefix("cu.") && !$0.contains("Bluetooth") && $0 != "cu.debug-console" }
            .sorted().map { "/dev/" + $0 }
    }
}
