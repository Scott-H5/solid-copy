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

    // WSJT-X's mode for the log (ADIF).
    check(WSJTXStatus.adifMode("FT8")! == ("FT8", "") && WSJTXStatus.adifMode("FT4")! == ("MFSK", "FT4")
          && WSJTXStatus.adifMode("Q65")! == ("MFSK", "Q65") && WSJTXStatus.adifMode("Echo") == nil,
          "WSJT-X's modes in ADIF: FT8 is FT8, FT4 and Q65 are MFSK submodes")

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

    // Reply: WSJT-X's field order (Id, Time, snr, Delta time, Delta
    // frequency, Mode, Message, Low confidence, Modifiers), checked with a
    // reader, not the writer.
    let replyData = WSJTXMessage.reply(to: decode)
    var r = WSJTXMessage.Reader(replyData)
    let header = (r.uint32(), r.uint32(), r.uint32(), r.utf8())
    check(header.0 == WSJTXMessage.magic && header.2 == 4 && header.3 == "WSJT-X", "Reply: header, type 4, WSJT-X's id")
    check(r.uint32() == 52_215_000 && r.int32() == -12 && r.double() == 0.2 && r.uint32() == 1500 && r.utf8() == "~"
          && r.utf8() == "CQ W1AW FN31" && r.bool() == false && r.uint32() == nil,
          "Reply: the decode's time, signal, offset, mode and text, as WSJT-X sent them")
    var h = WSJTXMessage.Reader(WSJTXMessage.haltTx(id: "WSJT-X"))
    check(h.uint32() == WSJTXMessage.magic && h.uint32() == 2 && h.uint32() == 8 && h.utf8() == "WSJT-X"
          && h.bool() == false, "Halt Tx: type 8, stop now (not just the automatic sequence)")

    // Answering: told whether WSJT-X took it, from its next Status.
    listener.reset()
    var sentData: [Data] = []
    listener.sendHook = { sentData.append($0) }
    var answered: WSJTXListener.Answer?
    listener.answer(decode, call: "W1AW", wait: 2) { answered = $0 }
    var took = WSJTXMessage.parse(statusMessage())!
    if case .status(var st) = took { st.dxCall = "W1AW"; took = .status(st) }
    listener.handle(took)
    check(answered == .sent && sentData.count == 1, "WSJT-X takes the Reply (its DX call is W1AW): said as calling")
    answered = nil
    listener.handle(WSJTXMessage.parse(statusMessage())!)   // WSJT-X calling nobody
    listener.answer(decode, call: "W1AW", wait: 0.3) { answered = $0 }
    let waitEnd = Date().addingTimeInterval(3)
    while answered == nil, Date() < waitEnd { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    check(answered == .ignored, "WSJT-X ignores it (Accept UDP requests off): said, with what to turn on")
    listener.sendHook = nil
    answered = nil
    listener.answer(decode, call: "W1AW") { answered = $0 }
    check(answered == .unheard, "no WSJT-X heard: nothing sent, said")
    check(!listener.haltTransmitting(), "Stop Transmitting with no WSJT-X heard: said, not sent")

    // WSJT-X quit and opened again: the old run's decodes are cleared
    // (it can't answer them), by its Close, or by a new sending address.
    listener.reset()
    listener.handle(WSJTXMessage.parse(decodeMessage("CQ OLD2 FN31"))!, endpoint: "127.0.0.1:50001")
    listener.handle(WSJTXMessage.parse(decodeMessage("CQ OLD3 FN31", seconds: 52_230))!, endpoint: "127.0.0.1:50001")
    check(listener.decodes.count == 2, "decodes from one run of WSJT-X are kept together")
    listener.handle(WSJTXMessage.parse(decodeMessage("CQ NEW2 FN31", seconds: 52_245))!, endpoint: "127.0.0.1:50002")
    check(listener.decodes.map(\.decode.text) == ["CQ NEW2 FN31"], "a new run of WSJT-X (new address): old decodes cleared")
    listener.handle(.close(id: "WSJT-X"))
    check(listener.decodes.isEmpty, "WSJT-X closing: its decodes cleared")
    // Answering the station WSJT-X is already calling: confirmed at once.
    var already = WSJTXMessage.parse(statusMessage())!
    if case .status(var st) = already { st.dxCall = "W1AW"; already = .status(st) }
    listener.handle(already)
    listener.sendHook = { _ in }
    var again: WSJTXListener.Answer?
    listener.answer(decode, call: "W1AW", wait: 0.2) { again = $0 }
    check(again == .sent, "answering the station WSJT-X is already calling: said as calling, not refused")
    listener.sendHook = nil

    // Logging: WSJT-X's Logged ADIF, as it sends it (a header, then one
    // record), into contacts, with the profile filling what WSJT-X left out.
    let adif = """
    <adif_ver:5>3.1.0
    <programid:6>WSJT-X
    <EOH>
    <call:6>KJ5IUY <gridsquare:4>EM12 <mode:3>FT8 <rst_sent:3>-14 <rst_rcvd:3>-10 <qso_date:8>20261121 \
    <time_on:6>175615 <qso_date_off:8>20261121 <time_off:6>175815 <band:3>20m <freq:9>14.075057 \
    <station_callsign:6>N0CALL <my_gridsquare:6>FN20aa <tx_pwr:2>50 <EOR>
    """
    let logged = WSJTXLogging.contacts(from: adif, station: ["my_rig": "TS-590SG", "tx_pwr": "100", "my_gridsquare": "FN31"])
    check(logged.count == 1 && logged[0].call == "KJ5IUY" && logged[0]["mode"] == "FT8" && logged[0]["band"] == "20m"
          && logged[0]["freq"].hasPrefix("14.075") && logged[0]["rst_sent"] == "-14" && logged[0]["gridsquare"] == "EM12",
          "a contact WSJT-X logged: call, mode FT8, band, frequency, reports, grid")
    check(logged[0]["my_rig"] == "TS-590SG" && logged[0]["tx_pwr"] == "50" && logged[0]["my_gridsquare"] == "FN20aa",
          "the profile fills what WSJT-X left out (rig), but never replaces what it sent (power, grid)")
    check(WSJTXLogging.contacts(from: "not ADIF at all", station: [:]).isEmpty, "a message with no contact: nothing")
    check(WSJTXLogging.spoken(added: logged, skipped: 0) == "Logged KJ5IUY from WSJT-X."
          && WSJTXLogging.spoken(added: [], skipped: 1).contains("already in the log"),
          "said: logged, or already in the log")
    // Into a throwaway log: added once; the same contact again is skipped.
    let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("wsjtx-check-\(UUID()).sqlite")
    defer { try? FileManager.default.removeItem(at: logURL) }
    if let book = try? Logbook(database: LogDatabase(fileURL: logURL)) {
        let first = try? book.importContacts(logged)
        let again = try? book.importContacts(WSJTXLogging.contacts(from: adif, station: [:]))
        check(first?.added.count == 1 && again?.added.isEmpty == true && again?.skipped == 1 && book.contacts.count == 1,
              "logged once; WSJT-X sending the same contact again doesn't add it twice")
    } else {
        check(false, "a throwaway log opens")
    }
    // The listener hands it to the app.
    var handed: String?
    listener.onLoggedADIF = { handed = $0 }
    var loggedMessage = Writer(type: 12, id: "WSJT-X")
    loggedMessage.utf8(adif)
    listener.handle(WSJTXMessage.parse(loggedMessage.data)!)
    check(handed == adif, "a Logged ADIF message is handed to the app to log")
    listener.onLoggedADIF = nil

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
    // And the Reply goes back to the sender, the way WSJT-X's messages came.
    var back: Data?
    sender.receiveMessage { data, _, _, _ in DispatchQueue.main.async { back = data } }
    let heard = listener.decodes.first!.decode
    listener.answer(heard, call: "UDP1", wait: 1) { _ in }
    let backEnd = Date().addingTimeInterval(5)
    while back == nil, Date() < backEnd { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    var backReader = WSJTXMessage.Reader(back ?? Data())
    _ = (backReader.uint32(), backReader.uint32())
    check(backReader.uint32() == 4, "the Reply reaches WSJT-X over UDP, at the address its messages came from")
    sender.receiveMessage { data, _, _, _ in DispatchQueue.main.async { back = data } }
    back = nil
    listener.handle(WSJTXMessage.parse(statusMessage())!)   // so Halt has an id
    check(listener.haltTransmitting(), "Stop Transmitting is sent")
    let haltEnd = Date().addingTimeInterval(5)
    while back == nil, Date() < haltEnd { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    var haltReader = WSJTXMessage.Reader(back ?? Data())
    _ = (haltReader.uint32(), haltReader.uint32())
    check(haltReader.uint32() == 8, "Halt Tx reaches WSJT-X over UDP")
    sender.cancel()
    listener.stop()
    print("All WSJT-X checks passed.")
}
