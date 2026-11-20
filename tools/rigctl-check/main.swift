// tools/rigctl-check/main.swift
//
// Checks the rigctl server (Sources/Radio/RigctlServer.swift) the way
// other programs will use it: hamlib's own rigctl, as "Hamlib NET
// rigctl" (-m 2), connects to it and asks and sets things. Behind the
// server is a pretend radio, so no radio is needed and nothing is sent to
// one. It listens on port 45332, not 4532, so a Solid Copy that's open
// and sharing the radio isn't disturbed.
//
// Needs hamlib's rigctl (brew install hamlib); without it, the rigctl
// part is skipped and said so.
//
// Run it with:  bash tools/check-rigctl.sh

import Foundation

func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }

@MainActor
final class PretendRadio: RigctlRadio {
    var reading: RadioReading? = RadioReading(hertz: 7_025_300, mode: "CW", watts: 5, passband: 500, maxWatts: 100)
    var status: RadioStatus? = RadioStatus(vfo: "VFOA", keyerWPM: 22, split: false)
    var model = 2037
    var maxWatts = 100.0
    var sent: [String] = []
    func send(_ command: String, done: @escaping @MainActor (Bool) -> Void) {
        sent.append(command)
        let words = command.split(separator: " ").map(String.init)
        switch words.first {
        case "F": reading?.hertz = Int(words[1]) ?? 0
        case "M": reading?.mode = words[1]; reading?.passband = Int(words[2]).flatMap { $0 > 0 ? $0 : nil } ?? 2400
        case "V": status?.vfo = words[1]
        case "S": status?.split = words[1] == "1"
        default: break
        }
        // As a radio would: a moment later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { MainActor.assumeIsolated { done(true) } }
    }
}

// Waits (running the main queue, where the server works) until `ok` or
// the time is up.
@MainActor func wait(_ seconds: Double, until ok: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while !ok(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    return ok()
}

// Runs a program to the end, keeping the main queue going meanwhile.
@MainActor func run(_ path: String, _ arguments: [String], input: String? = nil) -> (out: String, code: Int32) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let out = Pipe()
    process.standardOutput = out
    process.standardError = out
    let inPipe = Pipe()
    if input != nil { process.standardInput = inPipe }
    var data = Data()
    out.fileHandleForReading.readabilityHandler = { handle in
        let chunk = handle.availableData
        DispatchQueue.main.async { data.append(chunk) }
    }
    do { try process.run() } catch { return ("", -1) }
    if let input {
        inPipe.fileHandleForWriting.write(Data(input.utf8))
        try? inPipe.fileHandleForWriting.close()
    }
    _ = wait(20) { !process.isRunning }
    if process.isRunning {
        process.terminate()
        _ = wait(5) { !process.isRunning }
        if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
    }
    out.fileHandleForReading.readabilityHandler = nil
    data.append(out.fileHandleForReading.readDataToEndOfFile())
    return (String(decoding: data, as: UTF8.self), process.terminationStatus)
}

MainActor.assumeIsolated {
    let port: UInt16 = 45332
    let radio = PretendRadio()
    let server = RigctlServer(radio: radio)
    var events: [(String, Bool)] = []
    server.onEvent = { events.append(($0, $1)) }
    server.run(true, port: port)
    check(wait(5) { events.contains { $0.1 } }, "the server listens on 127.0.0.1 port \(port): \(events.map(\.0))")

    // Answers, line by line, as the client reads them.
    var said: String?
    server.answer("\\dump_state") { said = $0 }
    check(said?.hasPrefix("1\n2037\n0\n") == true && said?.hasSuffix("done\n") == true
          && said?.contains("ptt_type=0x0") == true, "\\dump_state: protocol 1, the radio's model, no PTT, ends in done")
    server.answer("\\get_freq") { said = $0 }
    check(said == "7025300\n", "a long name (\\get_freq) is understood")
    server.answer("T 1") { said = $0 }
    check(said == "RPRT -11\n" && radio.sent.isEmpty, "transmit (T 1) is refused, and nothing is sent to the radio")
    server.answer("T 0") { said = $0 }
    check(said == "RPRT 0\n" && radio.sent.isEmpty, "stop transmitting (T 0) is accepted, and nothing is sent")
    server.answer("F abc") { said = $0 }
    check(said == "RPRT -1\n" && radio.sent.isEmpty, "a bad frequency is refused, not sent")
    server.answer("\\set_conf foo bar") { said = $0 }
    check(said == "RPRT -4\n", "an unknown command: not implemented")

    // A silent radio: questions and changes time out; nothing is sent.
    let saved = radio.reading
    radio.reading = nil
    server.answer("f") { said = $0 }
    check(said == "RPRT -5\n", "no radio: f times out")
    server.answer("F 7030000") { said = $0 }
    check(said == "RPRT -5\n" && radio.sent.isEmpty, "no radio: F times out, nothing sent")
    radio.reading = saved

    // A second server can't take the same port, and says why.
    let second = RigctlServer(radio: radio)
    var secondEvents: [(String, Bool)] = []
    second.onEvent = { secondEvents.append(($0, $1)) }
    second.run(true, port: port)
    check(wait(5) { !secondEvents.isEmpty } && secondEvents.first?.1 == false
          && secondEvents.first?.0.contains("has port \(port)") == true,
          "the port already taken: said, not shared: \(secondEvents.map(\.0))")

    // hamlib's own client.
    let rigctl = ["/opt/homebrew/bin/rigctl", "/usr/local/bin/rigctl"].first { FileManager.default.isExecutableFile(atPath: $0) }
    guard let rigctl else {
        print("     (No hamlib rigctl here, so its checks were skipped: brew install hamlib.)")
        server.run(false)
        exit(0)
    }
    let address = "127.0.0.1:\(port)"
    var result = run(rigctl, ["-m", "2", "-r", address, "f", "m", "v", "s", "t"])
    check(result.code == 0 && result.out == "7025300\nCW\n500\nVFOA\n0\nNone\n0\n",
          "rigctl connects (handshake) and reads frequency, mode, VFO, split, PTT: \(result.out.debugDescription)")

    // (rigctl answers f and m right after setting them from its own cache,
    // so the width read back is the 0 it sent, not the radio's 2400.)
    result = run(rigctl, ["-m", "2", "-r", address, "F", "14074000", "M", "PKTUSB", "0", "f", "m"])
    check(result.code == 0 && result.out == "14074000\nPKTUSB\n0\n" && radio.sent == ["F 14074000", "M PKTUSB 0"],
          "rigctl tunes and sets a data mode, and reads them back: \(result.out.debugDescription), sent \(radio.sent)")

    radio.sent = []
    result = run(rigctl, ["-m", "2", "-r", address, "T", "1", "t"])
    check(result.out.lowercased().contains("not available") && result.out.hasSuffix("0\n") && radio.sent.isEmpty,
          "rigctl's transmit is refused, and the radio stays receiving: \(result.out.debugDescription)")

    result = run(rigctl, ["-m", "2", "-r", address, "V", "VFOB", "v", "S", "1", "VFOB", "s"])
    // (hamlib's client sets split from VFO A and goes back to B itself, so
    // the radio is sent V VFOB, V VFOA, S 1 VFOB, V VFOB.)
    check(result.code == 0 && result.out == "VFOB\n1\nVFOB\n" && radio.sent.contains("S 1 VFOB")
          && radio.status?.vfo == "VFOB" && radio.status?.split == true,
          "rigctl chooses VFO B and split: \(result.out.debugDescription), code \(result.code), sent \(radio.sent)")

    // Two programs at once (two digital-mode programs, say): both are answered.
    let other = Process()
    other.executableURL = URL(fileURLWithPath: rigctl)
    other.arguments = ["-m", "2", "-r", address]
    let otherIn = Pipe()
    other.standardInput = otherIn
    other.standardOutput = FileHandle.nullDevice
    try? other.run()
    result = run(rigctl, ["-m", "2", "-r", address, "f"])
    check(result.out == "14074000\n", "a second program is answered while the first stays connected")
    try? otherIn.fileHandleForWriting.close()
    _ = wait(5) { !other.isRunning }

    // A line far too long isn't a command: the connection is closed.
    result = run("/usr/bin/nc", ["127.0.0.1", "\(port)"], input: String(repeating: "a", count: 10_000))
    check(result.out.isEmpty, "a 10,000-character line is refused (connection closed)")
    result = run("/usr/bin/nc", ["127.0.0.1", "\(port)"], input: "f\nq\n")
    check(result.out == "14074000\nRPRT 0\n", "the server still answers after that, and q says goodbye")

    server.run(false)
    check(wait(3) { !server.isRunning }, "turned off, it stops listening")
    result = run(rigctl, ["-m", "2", "-r", address, "f"])
    check(result.code != 0, "turned off, nothing answers")
    print("All rigctl server checks passed.")
}
