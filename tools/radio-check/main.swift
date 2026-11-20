// tools/radio-check/main.swift
//
// Checks the radio connection without a real radio. Hamlib's "Dummy" radio
// (model 1), in Homebrew's rigctld on a spare port (4600), stands in for a
// rigctld you run (Hamlib NET rigctl). It's a test tool only: the app
// doesn't use hamlib, and these checks start and stop the dummy themselves,
// so they never disturb a rigctld or a radio in use:
//   - frequency, band, mode and power in ADIF's terms;
//   - talking to a rigctld, and telling "not running" from "not answering";
//   - Solid Copy connecting to a rigctld, reconnecting when it stops and
//     starts again, and saying so once each;
//   - the logging form filling in from the radio, and keeping what you type;
//   - tuning, mode, filter, keyer, the receive settings, RIT and its
//     offset, split and VFOs, from the keyboard;
//   - power, RF gain and squelch (FM only), band up and down, dual watch
//     and the S-meter;
//   - the built-in Kenwood driver's commands and answers, from canned
//     replies (no radio, no port): what each command is sent as, and how
//     an answer is read; and trouble said once for a silent serial port.
//
// Run it with:  bash tools/check-radio.sh

import AppKit

func check(_ ok: Bool, _ what: String) {
    print(ok ? "PASS" : "FAIL", what)
    fflush(stdout)   // so a stalled run shows where it stopped
    if !ok { exit(1) }
}

let homebrew = URL(fileURLWithPath: "/opt/homebrew/bin/rigctld")

// Runs a program and returns what it printed.
@discardableResult
func run(_ path: String, _ arguments: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try? process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

// A pretend rigctld that answers every command with an error, as rigctld
// does when the radio doesn't answer.
func startSulkingServer(port: UInt16) {
    let listener = socket(AF_INET, SOCK_STREAM, 0)
    var on: Int32 = 1
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
    var address = sockaddr_in(sin_len: UInt8(MemoryLayout<sockaddr_in>.size), sin_family: sa_family_t(AF_INET),
                              sin_port: port.bigEndian, sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
                              sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
    _ = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    listen(listener, 4)
    Thread.detachNewThread {
        while true {
            let connection = accept(listener, nil, nil)
            guard connection >= 0 else { continue }
            var buffer = [UInt8](repeating: 0, count: 256)
            while recv(connection, &buffer, buffer.count, 0) > 0 {
                let reply = Array("get_freq:\nRPRT -5\n".utf8)
                _ = send(connection, reply, reply.count, 0)
            }
            close(connection)
        }
    }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let work = URL(fileURLWithPath: CommandLine.arguments[1])

    // The built-in Kenwood driver's words, with no radio: what each command
    // is sent as, and how canned answers are read. The answers are Kenwood's
    // and Elecraft's formats as the command references give them (from
    // memory, not yet checked against a radio: see docs/PLAN.md, Phase 3).
    let kenwood590 = KenwoodRadio.forModel(2037)!
    let elecraftKX3 = KenwoodRadio.forModel(2045)!
    func sent(_ command: String, _ radio: KenwoodRadio, vfoB: Bool = false) -> [String]? {
        try? KenwoodCAT.commands(for: command, radio: radio, receiveVFOB: vfoB)
    }
    check(KenwoodRadio.forModel(1) == nil && KenwoodRadio.forModel(2029)?.isElecraft == true
          && KenwoodRadio.forModel(2031)?.isElecraft == false, "the built-in driver knows its radios by model")
    check(kenwood590.maxWatts == 100 && elecraftKX3.maxWatts == 15, "TS-590SG 100 watts, KX3 15")
    check(sent("F 7025300", kenwood590) == ["FA00007025300"] && sent("F 7025300", kenwood590, vfoB: true) == ["FB00007025300"],
          "tuning sends eleven digits to the receiving VFO")
    check(sent("SCAN 1", kenwood590) == ["SC1"] && sent("SCAN 0", kenwood590) == ["SC0"] && sent("SCAN 2", kenwood590) == nil,
          "the radio's own band scan: SC1 up, SC0 stop")
    check(sent("W 100", kenwood590) == ["FW0100"] && sent("W 80", kenwood590) == ["FW0080"]
          && sent("W 2500", elecraftKX3) == ["BW0250"], "a filter width alone, no mode (for the TS-590 that's just FW)")
    check(sent("M CW 500", kenwood590) == ["MD3", "FW0500"] && sent("M CW 500", elecraftKX3) == ["MD3", "BW0050"]
          && sent("M CW 0", elecraftKX3) == ["MD3"], "mode, then the filter in tens of hertz (width 0 sends no filter)")
    check(sent("M PKTUSB 0", elecraftKX3) == ["MD6"] && sent("M RTTY 0", kenwood590) == ["MD6"], "data is 6 on the KX3, RTTY 6 on the TS-590")
    check(sent("L KEYSPD 22", kenwood590) == ["KS022"], "keyer speed, three digits")
    check(sent("L PREAMP 12", kenwood590) == ["PA1"] && sent("L PREAMP 0", kenwood590) == ["PA0"]
          && sent("L PREAMP 6", kenwood590) == nil && sent("L PREAMP 10", elecraftKX3) == ["PA1"],
          "preamp: the TS-590 takes its 12 dB only, the KX3 any value on")
    check(sent("L ATT 12", kenwood590) == ["RA01"] && sent("L ATT 0", kenwood590) == ["RA00"] && sent("L ATT 3", kenwood590) == nil,
          "attenuator: on at the radio's own level, off, nothing else")
    check(sent("L AGC 2", kenwood590) == ["GC3", "GC2"] && sent("L AGC 3", kenwood590) == ["GC3", "GC1"]
          && sent("L AGC 0", kenwood590) == ["GC0"] && sent("L AGC 5", kenwood590) == nil,
          "TS-590 AGC: fast and slow go through GC3 first, no medium")
    check(sent("L AGC 2", elecraftKX3) == ["GT002"] && sent("L AGC 3", elecraftKX3) == ["GT004"] && sent("L AGC 0", elecraftKX3) == nil,
          "KX3 AGC: GT002 fast, GT004 slow, no off")
    check(sent("U NB 1", kenwood590) == ["NB1"] && sent("U NR 0", elecraftKX3) == ["NR0"] && sent("U RIT 1", kenwood590) == ["RT1"]
          && sent("U XIT 0", kenwood590) == ["XT0"], "noise blanker, noise reduction, RIT and XIT switches")
    check(sent("U DUAL_WATCH 1", elecraftKX3) == ["SB1"] && sent("U DUAL_WATCH 1", kenwood590) == nil
          && sent("U APF 1", elecraftKX3) == ["AP1"] && sent("U APF 1", kenwood590) == nil,
          "dual watch and peak filter are KX3 only")
    check(sent("J 30", kenwood590) == ["RO+0030"] && sent("Z -50", kenwood590) == ["RO-0050"], "RIT offset: signed, four digits")
    check(sent("S 1 VFOB", kenwood590) == ["FT1"] && sent("S 0 VFOA", kenwood590) == ["FT0"], "split on and off")
    check(sent("G XCHG", kenwood590) == ["SV"] && sent("G TOGGLE", kenwood590) == nil && sent("V VFOB", kenwood590) == ["FR1"],
          "swap VFOs, and receive on VFO B")
    check(sent("G BAND_UP", elecraftKX3) == ["BU"] && sent("G BAND_DOWN", elecraftKX3) == ["BD"], "band up and down")
    check(sent("POWER 5", kenwood590) == ["PC005"] && sent("POWER 500", kenwood590) == ["PC100"]
          && sent("POWER 500", elecraftKX3) == ["PC015"] && sent("POWER 0.2", kenwood590) == ["PC001"],
          "power in watts, whole, kept between one watt and the radio's most")
    check(sent("L RF 0.5", kenwood590) == ["RG128"] && sent("L AF 0.5", kenwood590) == ["AG0128"]
          && sent("L SQL 0.5", elecraftKX3) == ["SQ015"] && sent("L NR 0.5", kenwood590) == nil,
          "RF gain, volume and squelch as fractions of each radio's scale; L NR is refused")
    check(sent("X 1", kenwood590) == nil && sent("F", kenwood590) == nil, "a command the driver doesn't know is refused")

    // Canned answers, read a byte at a time as the serial port gives them.
    func answer(_ text: String) -> String? {
        var bytes: [UInt8] = []
        var token: String?
        for byte in text.utf8 where token == nil { token = KenwoodCAT.addByte(byte, to: &bytes) }
        return token
    }
    check(answer("FA00014060000;") == "FA00014060000" && answer("ID021;") == "ID021",
          "an answer ends at its semicolon, without it")
    check(answer("\r\nMD3;") == "MD3", "line ends and spaces around an answer are ignored")
    check(KenwoodCAT.hertz("00014060000") == 14_060_000 && KenwoodCAT.hertz("00000000000") == nil,
          "frequency from eleven digits; zero is no frequency")
    check(KenwoodCAT.mode("3", kenwood590) == "CW" && KenwoodCAT.mode("7", elecraftKX3) == "CWR" && KenwoodCAT.mode("2", kenwood590) == "USB"
          && KenwoodCAT.mode("6", elecraftKX3) == "PKTUSB" && KenwoodCAT.mode("6", kenwood590) == "RTTY"
          && KenwoodCAT.mode("9", elecraftKX3) == "PKTLSB" && KenwoodCAT.mode("12", elecraftKX3) == nil,
          "modes from their numbers, which differ between the two families")
    check(KenwoodCAT.passband("0050", unit: 10) == 500 && KenwoodCAT.passband("0050", unit: 1) == 50
          && KenwoodCAT.passband("0000", unit: 1) == nil, "filter width in hertz on the TS-590, tens on the Elecraft")
    check(KenwoodCAT.watts("100") == 100 && KenwoodCAT.watts("000") == nil, "power from PC, nil when zero")
    check(KenwoodCAT.offset("+0100") == 100 && KenwoodCAT.offset("-0050") == -50, "signed RIT offset")
    check(KenwoodCAT.isOn("10") && !KenwoodCAT.isOn("00") && !KenwoodCAT.isOn("0") && KenwoodCAT.isOn("2"),
          "a switch is on unless its first digit is 0")
    check(KenwoodCAT.pad(7, 3) == "007" && KenwoodCAT.pad(15, 11) == "00000000015", "numbers padded with zeros")

    // Frequency, band, mode and power.
    let cw = RadioReading(hertz: 7_025_241, mode: "CW", watts: 5)
    check(cw.megahertzText == "7.025241" && cw.band == "40m" && cw.wattsText == "5", "7.025241 MHz is 40m; 5 watts")
    check(RadioReading(hertz: 14_060_000, mode: "CW").megahertzText == "14.060", "14.060 keeps three decimals")
    check(Bands.name(forHertz: 5_357_000) == "60m" && Bands.name(forHertz: 146_520_000) == "2m"
          && Bands.name(forHertz: 11_000_000) == nil, "60m, 2m, and nothing between bands")
    // A band as typed becomes ADIF's name (TQSL refused "20").
    check(["20", "20m", "20 M", "20 meters", "14.058", ""].map(Bands.normalized)
          == ["20m", "20m", "20m", "20m", "20m", ""]
          && Bands.normalized("2") == "2m" && Bands.normalized("70 cm") == "70cm"
          && Bands.normalized("144.2") == "2m" && Bands.normalized("1.25m") == "1.25m"
          && Bands.normalized("11") == nil && Bands.normalized("abc") == nil,
          "typed bands: 20, 20 meters and 14.058 are 20m; 11 and abc aren't bands")
    let usb = RadioReading(hertz: 14_250_000, mode: "USB", watts: 0.5)
    check(usb.fields["mode"] == "SSB" && usb.fields["submode"] == "USB" && usb.wattsText == "0.5",
          "USB is mode SSB, submode USB; half a watt is 0.5")
    let data = RadioReading(hertz: 14_074_000, mode: "PKTUSB", watts: 100)
    check(data.fields["mode"] == nil && data.spokenMode == "data" && data.wattsText == "100",
          "a data mode leaves Mode alone, and is spoken as data")
    check(cw.spoken == "7.025 megahertz, CW", "spoken to the kilohertz: \(cw.spoken)")

    // Talking to rigctld directly.
    let nobody = RigctldClient(host: "127.0.0.1", port: 4601)
    check(Result { try nobody.reading() }.failure == .notRunning, "nothing at the address: not running")
    startSulkingServer(port: 4602)
    let sulking = RigctldClient(host: "127.0.0.1", port: 4602)
    check(Result { try sulking.reading() }.failure == .notAnswering, "rigctld there but the radio silent: not answering")

    // The dummy radio: rigctld on port 4600, started and stopped by these
    // checks. Its "port" is a file this check makes, which rigctld needs
    // but doesn't read for the dummy.
    let port = work.appendingPathComponent("cu.pretend-radio").path
    FileManager.default.createFile(atPath: port, contents: nil)
    var dummy: Process?
    func startDummy() {
        let process = Process()
        process.executableURL = homebrew
        process.arguments = ["-m", "1", "-r", port, "-T", "127.0.0.1", "-t", "4600"]
        process.standardError = FileHandle.nullDevice
        try! process.run()
        dummy = process
    }
    func stopDummy() {
        dummy?.terminate()
        dummy?.waitUntilExit()
        dummy = nil
    }
    let monitor = RadioMonitor.shared

    func waitFor(_ what: String, seconds: Double = 15, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while !condition() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        return condition()
    }

    // Radios saved in profiles by the version of 14 November 2026 move into
    // the radio list, once each, and the profile in use's stays in use.
    let defaults = UserDefaults.standard
    let keys = ["profiles", "currentProfile", "lookupEnabled", "radios", "currentRadio"]
    keys.forEach(defaults.removeObject(forKey:))
    defer { keys.forEach(defaults.removeObject(forKey:)) }
    let ts590 = #"{"model":2037,"modelName":"Kenwood TS-590SG","port":"/dev/cu.a","baud":115200,"address":""}"#
    let kx3 = #"{"model":2045,"modelName":"Elecraft KX3","port":"/dev/cu.b","baud":38400,"address":""}"#
    let homeID = UUID(), portableID = UUID(), thirdID = UUID()
    defaults.set(Data("""
        [{"id":"\(homeID)","name":"Home","formFields":[],"station":{},"radio":\(ts590)},
         {"id":"\(portableID)","name":"Portable","formFields":[],"station":{},"radio":\(kx3)},
         {"id":"\(thirdID)","name":"Field Day","formFields":[],"station":{},"radio":\(kx3)}]
        """.utf8), forKey: "profiles")
    defaults.set(portableID.uuidString, forKey: "currentProfile")
    let radios = Settings.radios
    check(radios.map(\.name) == ["Kenwood TS-590SG", "Elecraft KX3"] && radios[0].baud == 115_200,
          "radios in profiles move into the radio list, once each: \(radios.map(\.name))")
    check(Settings.currentRadio?.name == "Elecraft KX3" && Settings.radios.map(\.id) == radios.map(\.id),
          "the profile in use's radio stays in use, and radios keep their identities")
    check(Settings.profiles.map(\.name) == ["Home", "Portable", "Field Day"], "the profiles themselves are kept")
    Settings.useProfile(homeID)
    check(Settings.currentRadio?.name == "Elecraft KX3", "switching profiles leaves the radio alone")
    Settings.useRadio(radios[0].id)
    check(Settings.currentRadio?.name == "Kenwood TS-590SG", "switching radios")

    // The form, with Portable (which has Band, Mode, Frequency and Power),
    // and the dummy radio in use.
    keys.forEach(defaults.removeObject(forKey:))
    defaults.set(false, forKey: "lookupEnabled")
    Settings.useProfile(Settings.profiles[1].id)
    check(Settings.radios.isEmpty && Settings.currentRadio == nil, "no radios to begin with")
    Settings.currentRadio = RadioSettings(model: 1, modelName: "Hamlib Dummy", address: "127.0.0.1:4600")
    let logbook = try! Logbook(database: LogDatabase(fileURL: work.appendingPathComponent("Logbook.sqlite")))
    let form = LogEntryViewController(logbook: logbook)
    let window = NSWindow(contentViewController: form)
    window.layoutIfNeeded()
    func field(_ label: String) -> NSTextField? {
        var found: NSTextField?
        func walk(_ v: NSView) {
            if let t = v as? NSTextField, t.accessibilityLabel() == label, t.isEditable { found = t }
            v.subviews.forEach(walk)
        }
        walk(form.view)
        return found
    }

    startDummy()
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    monitor.use(Settings.currentRadio)
    check(waitFor("connected") { monitor.reading != nil }, "Solid Copy connects to the rigctld at 127.0.0.1:4600")
    check(monitor.reading?.hertz == 145_000_000 && monitor.reading?.mode == "FM", "the dummy radio reads 145 MHz, FM")
    check(waitFor("form") { field("Band")?.stringValue == "2m" } && field("Mode")?.stringValue == "FM"
          && field("Frequency (MHz)")?.stringValue == "145.000", "the form fills in band, mode and frequency")

    // Tune the radio (through rigctld, as another program could).
    run("/opt/homebrew/bin/rigctl", ["-m", "2", "-r", "127.0.0.1:4600", "F", "7025000", "M", "CW", "500"])
    check(waitFor("tuned") { field("Band")?.stringValue == "40m" } && field("Mode")?.stringValue == "CW",
          "tuning the radio changes the form within a second or two")

    // Type a mode yourself: it's kept, and logged, while the radio fills the rest.
    form.callsignField.stringValue = "K1ABC"
    field("Mode")?.stringValue = "SSB"
    form.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field("Mode")))
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    check(field("Mode")?.stringValue == "SSB", "the radio doesn't change a field you typed in")
    form.logContact(nil)
    let logged = logbook.contacts.last
    check(logged?["mode"] == "SSB" && logged?["freq"] == "7.025" && logged?["band"] == "40m",
          "logged with your mode and the radio's frequency and band")
    check(field("Mode")?.stringValue == "CW", "after logging, the radio fills Mode again")

    // MARK: Driving the radio

    // What can be typed in Callsign to tune or change mode.
    check(RadioEntry.parse("14060", currentHertz: nil) == .frequency(hertz: 14_060_000)
          && RadioEntry.parse("7.0255", currentHertz: nil) == .frequency(hertz: 7_025_500)
          && RadioEntry.parse("14060.5", currentHertz: nil) == .frequency(hertz: 14_060_500),
          "14060 is kilohertz, 7.0255 megahertz, 14060.5 kilohertz")
    check(RadioEntry.parse("cw", currentHertz: nil) == .mode("CW") && RadioEntry.parse("data", currentHertz: nil) == .mode("PKTUSB")
          && RadioEntry.parse("SSB", currentHertz: 7_100_000) == .mode("LSB")
          && RadioEntry.parse("SSB", currentHertz: 14_200_000) == .mode("USB"),
          "mode names; SSB is lower sideband below 10 MHz, upper above")
    check(RadioEntry.parse("W1AW", currentHertz: nil) == nil && RadioEntry.parse("K1ABC/P", currentHertz: nil) == nil
          && RadioEntry.parse("", currentHertz: nil) == nil, "callsigns aren't radio commands")

    // Status line: read every 5 seconds.
    check(monitor.status != nil, "the status line's settings were read on connecting")
    run("/opt/homebrew/bin/rigctl", ["-m", "2", "-r", "127.0.0.1:4600", "L", "KEYSPD", "25"])
    check(waitFor("status", seconds: 10) { monitor.status?.keyerWPM == 25 }, "the status line's settings are read: \(monitor.status?.shown ?? "none")")
    check(monitor.status?.shown.hasPrefix("VFO A, Keyer 25 WPM, RIT off, XIT off, split off") == true,
          "status line reads well: \(monitor.status?.shown ?? "")")

    // Typing a frequency in Callsign and pressing Return tunes; nothing is logged.
    let before = logbook.contacts.count
    form.callsignField.stringValue = "14060"
    form.logContact(nil)
    check(waitFor("typed frequency") { monitor.reading?.hertz == 14_060_000 } && logbook.contacts.count == before
          && form.callsignField.stringValue.isEmpty, "14060 and Return tunes to 14.060 MHz; nothing logged")
    check(waitFor("confirmed") { RadioMonitor.shared.reading?.hertz == 14_060_000 && field("Band")?.stringValue == "20m" },
          "the form follows: 20m")

    // The tuning control: arrow keys, fast. The radio ends up on the sum.
    var sliders: [String: RadioSlider] = [:]
    @MainActor func findSliders(_ v: NSView) {
        if let slider = v as? RadioSlider, let name = slider.accessibilityLabel() { sliders[name] = slider }
        v.subviews.forEach(findSliders)
    }
    findSliders(form.view)
    guard let tuningControl = sliders["Tuning"], let offsetControl = sliders["Offset"] else {
        return check(false, "the Tuning and Offset controls are in the window")
    }
    form.focusTuning(nil)
    check(window.firstResponder === tuningControl, "Command-T's command puts focus on the tuning control")
    @MainActor func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], to slider: RadioSlider? = nil) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                                     isARepeat: false, keyCode: code)!
        (slider ?? tuningControl).keyDown(with: event)
    }
    for _ in 1...5 { key(126) }          // Up five times: +500 Hz
    key(125, .shift)                      // Shift-Down: -10 Hz
    key(126, .option)                     // Option-Up: +1 kHz
    check(tuningControl.accessibilityValue() as? String == "14061.49 kilohertz",
          "the control shows the target at once: \(tuningControl.accessibilityValue() ?? "")")
    check(waitFor("tuned") { Result { try RigctldClient(host: "127.0.0.1", port: 4600).reading() }.success?.hertz == 14_061_490 },
          "and the radio ends up on 14061.49 kHz")
    key(53)                               // Escape
    check(window.firstResponder === form.callsignField || (window.firstResponder as? NSText)?.delegate === form.callsignField,
          "Escape goes back to Callsign")

    // Mode and filter.
    monitor.setMode("USB")
    check(waitFor("USB") { monitor.reading?.mode == "USB" }, "mode to USB")
    monitor.setMode("CW")
    check(waitFor("CW") { monitor.reading?.mode == "CW" }, "mode back to CW")
    let width = monitor.reading?.passband ?? 0
    monitor.changeFilter(wider: false)
    check(waitFor("narrower") { (monitor.reading?.passband ?? 0) < width && monitor.reading?.passband != nil },
          "narrower filter: \(width) Hz to \(monitor.reading?.passband ?? 0) Hz")

    // Keyer speed.
    monitor.changeKeyerSpeed(by: 1)
    check(waitFor("faster") { monitor.status?.keyerWPM == 26 }, "keyer faster: 26 WPM")

    // Receive settings: each on, then off, as the radio reports them.
    // (The dummy radio takes any value, so only on and off are checked.)
    @MainActor func onAndOff(_ name: String, _ toggle: () -> Void, _ isOn: @escaping (RadioStatus) -> Bool?) {
        let before = monitor.status.flatMap(isOn)
        toggle()
        let changed = waitFor(name) { monitor.status.flatMap(isOn) == (before == false) }
        toggle()
        check(before != nil && changed && waitFor(name) { monitor.status.flatMap(isOn) == before },
              "\(name) on and off")
    }
    onAndOff("preamp", monitor.togglePreamp) { $0.preampDB.map { $0 > 0 } }
    onAndOff("attenuator", monitor.toggleAttenuator) { $0.attenuatorDB.map { $0 > 0 } }
    onAndOff("noise blanker", monitor.toggleNoiseBlanker) { $0.noiseBlanker }
    onAndOff("noise reduction", monitor.toggleNoiseReduction) { $0.noiseReduction }
    onAndOff("audio peak filter", monitor.togglePeakFilter) { $0.peakFilter }
    onAndOff("XIT", monitor.toggleXIT) { $0.xitOn }
    onAndOff("split", monitor.toggleSplit) { $0.split }
    let agc = monitor.status?.agc
    monitor.nextAGC()
    check(waitFor("AGC") { monitor.status?.agc != agc && monitor.status?.agc != nil },
          "AGC steps on: \(monitor.status?.agcText ?? "none")")

    // RIT on, and its offset from the Offset control: Tab from Tuning,
    // Up three times, then Delete.
    monitor.toggleRIT()
    check(waitFor("RIT") { monitor.status?.ritOn == true }, "RIT on")
    check(!offsetControl.isHidden, "the Offset control is shown")
    form.focusTuning(nil)
    key(48)                                // Tab
    check(window.firstResponder === offsetControl, "Tab goes from Tuning to Offset")
    for _ in 1...3 { key(126, to: offsetControl) }
    check(offsetControl.accessibilityValue() as? String == "plus 30 hertz",
          "the offset shows at once: \(offsetControl.accessibilityValue() ?? "")")
    check(waitFor("offset") { monitor.status?.ritHertz == 30 }, "and the radio's RIT is +30 Hz")
    key(51, to: offsetControl)             // Delete
    check(waitFor("cleared") { monitor.status?.ritHertz == 0 }, "Delete clears it")
    key(48, .shift, to: offsetControl)     // Shift-Tab
    check(window.firstResponder === tuningControl, "Shift-Tab goes back to Tuning")
    key(53)
    monitor.toggleRIT()
    check(waitFor("RIT off") { monitor.status?.ritOn == false }, "RIT off")

    // Swap VFOs: the dummy radio's VFO B is on another frequency.
    let vfoA = monitor.reading?.hertz
    monitor.swapVFOs()
    check(waitFor("swapped") { monitor.reading?.hertz != vfoA }, "Swap VFOs: \(monitor.reading?.shown ?? "")")
    monitor.swapVFOs()
    check(waitFor("swapped back") { monitor.reading?.hertz == vfoA }, "and back")
    check(monitor.status?.shown.contains("NB off") == true, "the status line: \(monitor.status?.shown ?? "")")

    // Power, RF gain and squelch controls, and Tab through them.
    guard let powerControl = sliders["Power"], let rfControl = sliders["RF gain"],
          let squelchControl = sliders["Squelch"] else {
        return check(false, "the Power, RF gain and Squelch controls are in the window")
    }
    run("/opt/homebrew/bin/rigctl", ["-m", "2", "-r", "127.0.0.1:4600", "L", "RFPOWER", "0.05"])
    check(waitFor("power read") { monitor.reading?.watts == 5 && !powerControl.isHidden },
          "power is read (5 W) and the Power control shown")
    check(monitor.reading?.maxWatts == 100, "the radio's most power: \(monitor.reading?.maxWatts ?? 0) W")
    key(126, to: powerControl)
    key(126, to: powerControl)
    check(powerControl.accessibilityValue() as? String == "7 watts",
          "Power shows the target at once: \(powerControl.accessibilityValue() ?? "")")
    check(waitFor("power set") { monitor.reading?.watts == 7 }, "and the radio is set to 7 W")
    check(waitFor("RF gain") { !rfControl.isHidden }, "the RF gain control is shown")
    let gain = monitor.status?.rfGain ?? 0
    key(126, to: rfControl)
    check(waitFor("RF gain set") { abs((monitor.status?.rfGain ?? 0) - (gain + 0.05)) < 0.01 },
          "RF gain up 5 percent: \(rfControl.accessibilityValue() ?? "")")
    check(squelchControl.isHidden, "no Squelch control in CW")
    form.focusTuning(nil)
    key(48); key(48, to: offsetControl); key(48, to: powerControl)
    check(window.firstResponder === rfControl, "Tab: Tuning, Offset, Power, RF gain")
    key(48, to: rfControl)
    check(window.firstResponder === form.callsignField || (window.firstResponder as? NSText)?.delegate === form.callsignField,
          "and from the last control shown back to Callsign")
    monitor.setMode("FM")
    check(waitFor("squelch", seconds: 10) { !squelchControl.isHidden }, "in FM the Squelch control is shown")
    key(126, to: squelchControl)
    check(waitFor("squelch set") { (monitor.status?.squelch ?? 0) > 0.04 }, "squelch up 5 percent")
    monitor.setMode("CW")
    check(waitFor("no squelch") { squelchControl.isHidden }, "back in CW it's hidden again")

    // Dual watch.
    onAndOff("dual watch", monitor.toggleDualWatch) { $0.dualWatch }

    // Band up and down. The dummy radio has no band keys, so Solid Copy
    // tunes: up to 17 meters' usual CW spot, then back down to where it
    // was on 20.
    let on20 = monitor.reading?.hertz
    monitor.changeBand(up: true)
    check(waitFor("17m") { monitor.reading?.band == "17m" }, "Band Up from 20 meters: \(monitor.reading?.shown ?? "")")
    check(monitor.reading?.hertz == 18_080_000, "to 17 meters' usual CW spot, 18.080 MHz")
    monitor.changeBand(up: false)
    check(waitFor("20m") { monitor.reading?.band == "20m" } && monitor.reading?.hertz == on20,
          "Band Down goes back to where you were on 20 meters")

    // The S-meter, in S units.
    check(RadioMonitor.sMeterText(-54) == "S 0" && RadioMonitor.sMeterText(-12) == "S 7"
          && RadioMonitor.sMeterText(0) == "S 9" && RadioMonitor.sMeterText(10) == "S 9 plus 10 dB",
          "S-meter readings in S units")
    check((try? RigctldClient(host: "127.0.0.1", port: 4600).strength()) != nil, "the radio's S-meter is read")

    // Lost and back have their own tones (Tone.swift), listened for here.
    var tones: [Tone] = []
    RadioMonitor.tone = { tones.append($0) }
    check(Tone.wav([440]).count > 44 && Tone.wav([440]).prefix(4) == Data("RIFF".utf8), "the tones are made as WAV audio")

    // The rigctld you run stops: Solid Copy notices, and connects again
    // when it's back. (Its lost and back tones are checked just below.)
    let tonesBefore = tones.count
    stopDummy()
    check(waitFor("noticed") { monitor.reading == nil }, "Solid Copy notices its rigctld stopped")
    startDummy()
    check(waitFor("back", seconds: 20) { monitor.reading != nil }, "and connects again when it's back")
    check(Array(tones.dropFirst(tonesBefore)) == [.radioLost, .radioBack],
          "the radio dropping plays the lost tone once, and its return the back tone once: \(tones)")
    // However it went down, every lost is followed by one back.
    check(tones.count.isMultiple(of: 2) && tones.enumerated().allSatisfy { $1 == ($0.isMultiple(of: 2) ? .radioLost : .radioBack) },
          "lost and back tones take turns: \(tones)")

    // Band scan (Control-Command-C) is the radio's own, on the TS-590 only.
    check(!monitor.scanning, "no band scan before one is started")

    monitor.stop()
    check((try? RigctldClient(host: "127.0.0.1", port: 4600).reading()) != nil,
          "stopping (as Solid Copy quits) leaves a rigctld you run alone")

    // A radio that's off but whose port stays (the KX3, whose USB chip is
    // in its cable): a pretend serial port that never answers, for the
    // built-in driver. The trouble is said once, however long it goes on.
    let silentPort = posix_openpt(O_RDWR | O_NOCTTY)
    check(silentPort >= 0 && grantpt(silentPort) == 0 && unlockpt(silentPort) == 0, "a pretend silent serial port")
    // Something must read what Solid Copy writes to the port, as a real
    // adapter's chip does: the write waits (tcdrain) until it's read.
    Thread.detachNewThread {
        var sink = [UInt8](repeating: 0, count: 64)
        while read(silentPort, &sink, sink.count) > 0 {}
    }
    defer { close(silentPort) }
    var said: [String] = []
    RadioMonitor.say = { said.append($0) }
    monitor.use(RadioSettings(model: 2037, modelName: "Silent TS-590SG", port: String(cString: ptsname(silentPort)),
                              baud: 38_400, builtIn: true))
    let trouble = { said.filter { $0.contains("not answering") || $0.contains("not running") } }
    check(waitFor("silent", seconds: 30) { !trouble().isEmpty }, "a silent radio is noticed: \(said)")
    _ = waitFor("quiet", seconds: 20) { false }
    check(trouble().count == 1, "and the trouble said only once: \(said)")
    // Let go of the pretend port before it closes (the monitor holds its
    // other end; closing the master first can hang).
    monitor.use(nil)
    stopDummy()
}

extension Result {
    var success: Success? { try? get() }
    var failure: RigctldClient.Failure? {
        if case .failure(let error) = self { return error as? RigctldClient.Failure }
        return nil
    }
}
