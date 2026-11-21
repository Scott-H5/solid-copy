// tools/wsjtx-check/main.swift
//
// Checks reading WSJT-X's UDP messages (Sources/WSJTX): the format, what
// a decode says, refusing broken datagrams, and the listener really
// hearing a message sent to it over UDP. No WSJT-X needed.
//
// Run it with:  bash tools/check-wsjtx.sh

import Foundation
import Network

func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }

typealias Writer = WSJTXMessage.Writer

// A Decode, written as WSJT-X writes one (schema 2).
func decodeMessage(_ text: String, snr: Int32 = -12, seconds: UInt32 = 52_215, df: UInt32 = 1_500,
                   id: String = "WSJT-X", lowConfidence: Bool = false) -> Data {
    var w = Writer(type: 2, id: id)
    w.bool(true)                     // new
    w.uint32(seconds * 1000)         // QTime, ms since midnight
    w.int32(snr)
    w.double(0.2)
    w.uint32(df)
    w.utf8("~")                      // FT8's mode character
    w.utf8(text)
    w.bool(lowConfidence)
    w.bool(false)                    // off air
    return w.data
}

func statusMessage(hertz: UInt64 = 14_074_000, transmitting: Bool = false, myCall: String = "N0CALL") -> Data {
    var w = Writer(type: 1, id: "WSJT-X")
    w.uint64(hertz); w.utf8("FT8"); w.utf8(""); w.utf8("-12"); w.utf8("FT8")
    w.bool(false); w.bool(transmitting); w.bool(false)
    w.uint32(1500); w.uint32(1500)
    w.utf8(myCall); w.utf8("FN20"); w.utf8("")
    w.bool(false); w.utf8(""); w.bool(false); w.uint8(0); w.uint32(10); w.uint32(15); w.utf8("Default"); w.utf8("")
    return w.data
}

MainActor.assumeIsolated {
    // The header, made byte by byte (not with Writer), so the reader is
    // checked against the format itself: magic, schema 2, Heartbeat (0),
    // id "WSJT-X", maximum schema 3, version "3.0.1", revision "".
    var bytes: [UInt8] = [0xad, 0xbc, 0xcb, 0xda, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 6]
    bytes += Array("WSJT-X".utf8) + [0, 0, 0, 3, 0, 0, 0, 5] + Array("3.0.1".utf8) + [0, 0, 0, 0]
    check(WSJTXMessage.parse(Data(bytes)) == .heartbeat(id: "WSJT-X", version: "3.0.1"),
          "a Heartbeat made byte by byte: id and version")
    var clearBytes: [UInt8] = [0xad, 0xbc, 0xcb, 0xda, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 1]
    clearBytes += Array("W".utf8)
    check(WSJTXMessage.parse(Data(clearBytes)) == .clear(id: "W"), "a Clear")
    // Qt's null string (length 0xffffffff) reads as empty.
    var withNull: [UInt8] = [0xad, 0xbc, 0xcb, 0xda, 0, 0, 0, 2, 0, 0, 0, 6, 0xff, 0xff, 0xff, 0xff]
    check(WSJTXMessage.parse(Data(withNull)) == .close(id: ""), "a null string reads as empty")
    withNull[3] = 0xdb
    check(WSJTXMessage.parse(Data(withNull)) == nil, "the wrong magic number: refused")

    // A Decode.
    guard case .decode(let d) = WSJTXMessage.parse(decodeMessage("CQ W1AW FN31")) else { return check(false, "a Decode") }
    check(d.text == "CQ W1AW FN31" && d.snr == -12 && d.df == 1500 && d.timeText == "14:30:15" && d.isNew,
          "a Decode: text, -12 dB, 1500 Hz, 14:30:15")
    // Broken or hostile datagrams: every length cut short (the last two
    // fields are optional, so those two cuts are fine), and a huge string
    // length.
    let whole = decodeMessage("CQ W1AW FN31")
    let cutOK = (0..<whole.count - 2).allSatisfy { WSJTXMessage.parse(whole.prefix($0)) == nil }
    check(cutOK, "a Decode cut short at any point: refused, no crash")
    var huge = Writer(type: 2, id: "x").data
    huge.append(contentsOf: [1, 0, 0, 0, 0, 0, 0, 0, 0] + [0x7f, 0xff, 0xff, 0xff])
    check(WSJTXMessage.parse(huge) == nil, "a string claiming 2 GB: refused")
    check((0..<200).allSatisfy { _ in
        WSJTXMessage.parse(Data((0..<Int.random(in: 0...80)).map { _ in UInt8.random(in: 0...255) })) == nil
            || true
    }, "random bytes: no crash")
    // Extra fields at the end (a newer WSJT-X) are ignored.
    var newer = decodeMessage("CQ W1AW FN31")
    newer.append(contentsOf: [1, 2, 3, 4])
    if case .decode(let n) = WSJTXMessage.parse(newer) { check(n.text == "CQ W1AW FN31", "extra fields at the end: ignored") }
    else { check(false, "extra fields at the end: ignored") }
    // A Status.
    if case .status(let s) = WSJTXMessage.parse(statusMessage(transmitting: true)) {
        check(s.dialHertz == 14_074_000 && s.mode == "FT8" && s.transmitting && s.deCall == "N0CALL",
              "a Status: 14.074 MHz, FT8, transmitting, my call")
    } else { check(false, "a Status") }

    // The words of a message.
    let cq = FT8Text("CQ W1AW FN31")
    check(cq?.isCQ == true && cq?.from == "W1AW" && cq?.grid == "FN31" && cq?.cqTo == "", "CQ W1AW FN31")
    let pota = FT8Text("CQ POTA W1AW FN31")
    check(pota?.isCQ == true && pota?.cqTo == "POTA" && pota?.from == "W1AW", "CQ POTA W1AW FN31")
    let reply = FT8Text("K1ABC W1AW RR73")
    check(reply?.to == "K1ABC" && reply?.from == "W1AW" && reply?.exchange == "RR73" && reply?.grid == nil,
          "K1ABC W1AW RR73: RR73 isn't a grid")
    check(FT8Text("<W1AW> K1ABC -08")?.to == "<W1AW>" && FT8Text("CQ <PJ4/K1ABC>")?.plainFrom == "PJ4/K1ABC",
          "hashed calls")
    check(FT8Text("TNX") == nil, "one word: not a QSO message")

    // What a line says.
    let decode = WSJTXDecode(id: "WSJT-X", isNew: true, milliseconds: 52_215_000, snr: -12, dt: 0.2, df: 1500,
                             mode: "~", text: "CQ W1AW FN31", lowConfidence: false, offAir: false)
    check(DecodeLine.line(for: decode, words: cq, myCall: "N0CALL", country: "United States", needed: "new band")
          == "W1AW calling CQ, United States, grid FN31, -12 dB, 14:30:15, new band", "a CQ's line")
    var toMe = decode
    toMe.text = "N0CALL K1ABC -08"
    check(DecodeLine.line(for: toMe, words: FT8Text(toMe.text), myCall: "n0call", workedBefore: true)
          == "To you, from K1ABC: -08, -12 dB, 14:30:15, worked before", "a call to you comes first")
    check(DecodeLine.line(for: decode, words: nil, myCall: "") == "CQ W1AW FN31, -12 dB, 14:30:15",
          "a message that isn't a QSO: as sent")

    // The listener keeps decodes newest first, skips repeats, clears.
    let listener = WSJTXListener.shared
    listener.reset()
    listener.handle(WSJTXMessage.parse(decodeMessage("CQ W1AW FN31"))!)
    listener.handle(WSJTXMessage.parse(decodeMessage("CQ K1ABC FN42", seconds: 52_230))!)
    listener.handle(WSJTXMessage.parse(decodeMessage("CQ W1AW FN31"))!)
    check(listener.decodes.map(\.decode.text) == ["CQ K1ABC FN42", "CQ W1AW FN31"], "newest first, a replayed decode not added twice")
    let old = Date().addingTimeInterval(-WSJTXListener.keptFor - 60)
    listener.reset()
    listener.handle(WSJTXMessage.parse(decodeMessage("CQ OLD1 FN31"))!, now: old)
    listener.handle(WSJTXMessage.parse(decodeMessage("CQ NEW1 FN31"))!)
    check(listener.decodes.map(\.decode.text) == ["CQ NEW1 FN31"], "decodes older than 15 minutes are dropped")
    listener.handle(.clear(id: "WSJT-X"))
    check(listener.decodes.isEmpty, "WSJT-X's Erase clears the list")
    check(DecodeLine.status(listener: { listener.reset(); return listener }(), shown: 0, total: 0).hasPrefix("Waiting for WSJT-X"),
          "nothing heard yet: says how to set WSJT-X up")
    listener.handle(WSJTXMessage.parse(statusMessage())!)
    listener.handle(.heartbeat(id: "WSJT-X", version: "3.0.1"))
    check(DecodeLine.status(listener: listener, shown: 3, total: 9) == "WSJT-X 3.0.1: 14.074 megahertz, FT8. 3 of 9 decodes.",
          "the status line: \(DecodeLine.status(listener: listener, shown: 3, total: 9))")

    // A real UDP datagram to a listening port (45337, not 2237, so a
    // running copy of Solid Copy isn't disturbed).
    listener.reset()
    listener.start(port: 45337)
    let sender = NWConnection(host: "127.0.0.1", port: 45337, using: .udp)
    sender.start(queue: .main)
    sender.send(content: decodeMessage("CQ UDP1 FN31"), completion: .contentProcessed { _ in })
    let end = Date().addingTimeInterval(5)
    while listener.decodes.isEmpty, Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    check(listener.decodes.first?.decode.text == "CQ UDP1 FN31", "a decode sent over UDP is heard")
    sender.cancel()
    listener.stop()
    print("All WSJT-X checks passed.")
}
