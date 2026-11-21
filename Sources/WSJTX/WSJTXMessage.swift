// WSJTXMessage.swift
//
// WSJT-X's UDP messages: what it decodes, what it's doing, and the
// contacts it logs, sent to 127.0.0.1 port 2237 (WSJT-X's Settings >
// Reporting, UDP Server). Solid Copy reads them to show the decodes in a
// list VoiceOver reads (DecodesWindowController.swift), so WSJT-X can do
// the signal work in the background.
//
// The format, from WSJT-X's Network/NetworkMessage.hpp (read 21 November
// 2026): big-endian Qt QDataStream data.
//   - Header: quint32 magic 0xadbccbda, quint32 schema (2 or 3), quint32
//     message type, then the sending program's id (utf8).
//   - utf8: quint32 byte count, then the bytes; 0xffffffff is "null"
//     (read as empty). bool: one byte. QTime: quint32 milliseconds since
//     midnight. Floating point: 64-bit double. QDateTime: qint64 Julian
//     day, quint32 milliseconds, quint8 time spec (1 is UTC), and a qint32
//     offset only when the spec is 2.
//   - Types used here: 0 Heartbeat, 1 Status, 2 Decode, 3 Clear, 5 QSO
//     Logged, 6 Close, 12 Logged ADIF. (4 Reply and 8 Halt Tx go the other
//     way: Writer, below.) Others are skipped.
//   - New fields are only ever added at the end, so anything after the
//     fields known here is ignored, as the file says to.
// A datagram that isn't WSJT-X's, or is cut short, is refused (nil):
// anything can send to a UDP port, so nothing is trusted.

import Foundation

enum WSJTXMessage: Equatable {
    case heartbeat(id: String, version: String)
    case status(WSJTXStatus)
    case decode(WSJTXDecode)
    case clear(id: String)
    case loggedADIF(id: String, adif: String)
    case close(id: String)
    // A type Solid Copy doesn't use (QSO Logged, WSPR, ...).
    case other(id: String, type: UInt32)

    static let magic: UInt32 = 0xadbc_cbda

    // nil if `data` isn't a whole WSJT-X message.
    static func parse(_ data: Data) -> WSJTXMessage? {
        var reader = Reader(data)
        guard let magic = reader.uint32(), magic == Self.magic,
              let schema = reader.uint32(), (1...3).contains(schema),
              let type = reader.uint32(), let id = reader.utf8() else { return nil }
        switch type {
        case 0:
            _ = reader.uint32()   // highest schema it speaks
            return .heartbeat(id: id, version: reader.utf8() ?? "")
        case 1:
            guard let hertz = reader.uint64(), let mode = reader.utf8(), let dxCall = reader.utf8(),
                  let report = reader.utf8(), let txMode = reader.utf8(), let txEnabled = reader.bool(),
                  let transmitting = reader.bool(), let decoding = reader.bool(),
                  let rxDF = reader.uint32(), let txDF = reader.uint32(),
                  let deCall = reader.utf8(), let deGrid = reader.utf8(), let dxGrid = reader.utf8()
            else { return nil }
            return .status(WSJTXStatus(id: id, dialHertz: hertz, mode: mode, dxCall: dxCall, report: report,
                                       txMode: txMode, txEnabled: txEnabled, transmitting: transmitting,
                                       decoding: decoding, rxDF: rxDF, txDF: txDF, deCall: deCall,
                                       deGrid: deGrid, dxGrid: dxGrid))
        case 2:
            guard let new = reader.bool(), let milliseconds = reader.uint32(), let snr = reader.int32(),
                  let dt = reader.double(), let df = reader.uint32(), let mode = reader.utf8(),
                  let text = reader.utf8() else { return nil }
            let lowConfidence = reader.bool() ?? false
            let offAir = reader.bool() ?? false
            return .decode(WSJTXDecode(id: id, isNew: new, milliseconds: milliseconds, snr: Int(snr), dt: dt,
                                       df: Int(df), mode: mode, text: text, lowConfidence: lowConfidence,
                                       offAir: offAir))
        case 3:
            return .clear(id: id)
        case 6:
            return .close(id: id)
        case 12:
            guard let adif = reader.utf8() else { return nil }
            return .loggedADIF(id: id, adif: adif)
        default:
            return .other(id: id, type: type)
        }
    }

    // Reads QDataStream values, each nil if the data runs out first.
    struct Reader {
        private let bytes: [UInt8]
        private var at = 0
        // No WSJT-X string comes near this; a bigger "length" is a broken
        // or hostile datagram.
        private static let longestString = 65_536

        init(_ data: Data) { bytes = Array(data) }

        private mutating func take(_ count: Int) -> ArraySlice<UInt8>? {
            guard count >= 0, at + count <= bytes.count else { return nil }
            defer { at += count }
            return bytes[at..<at + count]
        }
        private mutating func unsigned(_ count: Int) -> UInt64? {
            take(count).map { $0.reduce(0) { $0 << 8 | UInt64($1) } }
        }
        mutating func uint32() -> UInt32? { unsigned(4).map { UInt32($0) } }
        mutating func int32() -> Int32? { uint32().map { Int32(bitPattern: $0) } }
        mutating func uint64() -> UInt64? { unsigned(8) }
        mutating func bool() -> Bool? { take(1).map { $0.first != 0 } }
        mutating func double() -> Double? { uint64().map { Double(bitPattern: $0) } }
        mutating func utf8() -> String? {
            guard let length = uint32() else { return nil }
            if length == 0xffff_ffff { return "" }   // Qt's null string
            guard Int(length) <= Self.longestString, let body = take(Int(length)) else { return nil }
            return String(decoding: body, as: UTF8.self)
        }
    }

    // Reply (4): what WSJT-X does when you double-click a decode: it
    // calls that station, starting its usual sequence of messages. The
    // decode is sent back as WSJT-X sent it, since WSJT-X matches it to a
    // line in its Band Activity. Modifiers 0: no Shift or Control held.
    // WSJT-X takes it only with Settings > Reporting > Accept UDP requests
    // on.
    static func reply(to decode: WSJTXDecode) -> Data {
        var w = Writer(type: 4, id: decode.id)
        w.uint32(decode.milliseconds)
        w.int32(Int32(clamping: decode.snr))
        w.double(decode.dt)
        w.uint32(UInt32(clamping: max(decode.df, 0)))
        w.utf8(decode.mode)
        w.utf8(decode.text)
        w.bool(decode.lowConfidence)
        w.uint8(0)
        return w.data
    }

    // Halt Tx (8): stop transmitting now (Auto Tx Only false: not just the
    // automatic sequence, the transmission on the air too).
    static func haltTx(id: String) -> Data {
        var w = Writer(type: 8, id: id)
        w.bool(false)
        return w.data
    }

    // Writes QDataStream values, for the messages Solid Copy sends WSJT-X
    // (Reply and Halt Tx), and for the check's made-up messages.
    struct Writer {
        private(set) var data = Data()

        init(type: UInt32, id: String, schema: UInt32 = 2) {
            uint32(WSJTXMessage.magic)
            uint32(schema)
            uint32(type)
            utf8(id)
        }
        mutating func uint32(_ value: UInt32) { withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) } }
        mutating func int32(_ value: Int32) { uint32(UInt32(bitPattern: value)) }
        mutating func uint64(_ value: UInt64) { withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) } }
        mutating func bool(_ value: Bool) { data.append(value ? 1 : 0) }
        mutating func double(_ value: Double) { uint64(value.bitPattern) }
        mutating func uint8(_ value: UInt8) { data.append(value) }
        mutating func utf8(_ value: String) {
            let bytes = Array(value.utf8)
            uint32(UInt32(bytes.count))
            data.append(contentsOf: bytes)
        }
    }
}

// What WSJT-X is doing (Status, sent when anything changes).
struct WSJTXStatus: Equatable {
    // WSJT-X's mode as ADIF names it, for the log: FT8, JT65, JT9, MSK144
    // and WSPR are ADIF modes; FT4, Q65, FST4 and JS8 are submodes of
    // MFSK (ADIF 3.1's mode list). nil for one Solid Copy doesn't know.
    static func adifMode(_ mode: String) -> (mode: String, submode: String)? {
        switch mode.uppercased() {
        case "FT8", "JT65", "JT9", "MSK144", "WSPR", "JT4": return (mode.uppercased(), "")
        case "FT4", "Q65", "FST4", "FST4W", "JS8": return ("MFSK", mode.uppercased())
        default: return nil
        }
    }

    var id: String
    var dialHertz: UInt64
    var mode: String
    var dxCall: String
    var report: String
    var txMode: String
    var txEnabled: Bool
    var transmitting: Bool
    var decoding: Bool
    var rxDF: UInt32
    var txDF: UInt32
    var deCall: String
    var deGrid: String
    var dxGrid: String
}

// One decoded message, such as "CQ W1AW FN31" at -12 dB.
struct WSJTXDecode: Equatable {
    var id: String
    var isNew: Bool
    // UTC time of the period it was heard in, in milliseconds since midnight.
    var milliseconds: UInt32
    var snr: Int
    var dt: Double
    // Audio offset in hertz above the dial frequency.
    var df: Int
    var mode: String
    var text: String
    var lowConfidence: Bool
    var offAir: Bool

    // "14:30:15".
    var timeText: String {
        let seconds = Int(milliseconds / 1000)
        return String(format: "%02d:%02d:%02d", seconds / 3600 % 24, seconds / 60 % 60, seconds % 60)
    }
}

// The words of an FT8 or FT4 message, as who's calling whom.
//   "CQ W1AW FN31"          a CQ from W1AW in grid FN31
//   "CQ POTA W1AW FN31"     a CQ with a word after CQ (POTA, DX, NA, ...)
//   "K1ABC W1AW -12"        W1AW to K1ABC, with a report
//   "K1ABC W1AW RR73"       and so on: the last word is the exchange
// Calls are as sent: "<...>" (a hashed call WSJT-X couldn't name) is kept.
struct FT8Text: Equatable {
    var isCQ: Bool
    // The word after CQ ("POTA", "DX"), if any.
    var cqTo: String
    // Who sent it.
    var from: String
    // Who it's for (empty for a CQ).
    var to: String
    // A grid, a report, RR73, 73 ... (empty if none).
    var exchange: String

    init?(_ text: String) {
        let words = text.uppercased().split(separator: " ").map(String.init)
        guard words.count >= 2 else { return nil }
        if words[0] == "CQ" || words[0] == "QRZ" {
            isCQ = true
            to = ""
            // "CQ W1AW FN31" or "CQ POTA W1AW FN31": the call is the first
            // word that looks like one.
            var rest = Array(words.dropFirst())
            cqTo = ""
            if rest.count >= 2, !Self.looksLikeCall(rest[0]) {
                cqTo = rest.removeFirst()
            }
            guard let call = rest.first else { return nil }
            from = call
            exchange = rest.count > 1 ? rest[1] : ""
        } else {
            isCQ = false
            cqTo = ""
            to = words[0]
            from = words[1]
            exchange = words.count > 2 ? words[2] : ""
        }
    }

    // A grid square, such as FN31 (not RR73, which looks like one).
    var grid: String? {
        guard exchange.count == 4, exchange != "RR73" else { return nil }
        let c = Array(exchange)
        return c[0].isLetter && c[1].isLetter && c[2].isNumber && c[3].isNumber ? exchange : nil
    }

    // Letters and a digit, or a hashed call ("<W1AW>").
    static func looksLikeCall(_ word: String) -> Bool {
        if word.hasPrefix("<") { return true }
        return word.contains(where: \.isNumber) && word.contains(where: \.isLetter) && word.count >= 3
    }

    // The call with the hash brackets taken off, for looking up.
    var plainFrom: String { from.trimmingCharacters(in: CharacterSet(charactersIn: "<>")) }
}
