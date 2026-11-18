// tools/radio-check/main.swift
//
// Checks the radio connection without a real radio, using hamlib's
// "Dummy" radio (model 1) in Homebrew's rigctld, on a spare port (4600),
// so it never disturbs a rigctld or a radio in use:
//   - frequency, band, mode and power in ADIF's terms;
//   - reading hamlib's list of radios;
//   - talking to rigctld, and telling "not running" from "not answering";
//   - Solid Copy starting rigctld, starting it again after it stops, and
//     stopping and restarting it as the radio's port goes and comes back;
//   - a radio that's off but whose port stays: trouble said once, and
//     rigctld restarted less and less often;
//   - the logging form filling in from the radio, and keeping what you type;
//   - tuning, mode, filter, keyer, the receive settings, RIT and its
//     offset, split and VFOs, from the keyboard;
//   - power, RF gain and squelch (FM only), band up and down, dual watch
//     and the S-meter.
//
// Run it with:  bash tools/check-radio.sh

import AppKit

func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }

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

    // hamlib's list of radios.
    let models = RadioModels.parse(run(homebrew.path, ["-l"]))
    check(models.contains { $0.number == 2037 && $0.maker == "Kenwood" && $0.name == "TS-590SG" }
          && models.contains { $0.number == 2045 && $0.maker == "Elecraft" && $0.name == "KX3" }
          && !models.contains { $0.number == 2 } && models.count > 100,
          "hamlib's list has the TS-590SG and KX3 (\(models.count) radios), and not NET rigctl")

    // Talking to rigctld directly.
    let nobody = RigctldClient(host: "127.0.0.1", port: 4601)
    check(Result { try nobody.reading() }.failure == .notRunning, "nothing at the address: not running")
    startSulkingServer(port: 4602)
    let sulking = RigctldClient(host: "127.0.0.1", port: 4602)
    check(Result { try sulking.reading() }.failure == .notAnswering, "rigctld there but the radio silent: not answering")

    // Solid Copy's own rigctld, with the dummy radio. Its "port" is a
    // file this check makes and removes, to act like a USB port coming
    // and going.
    RadioModels.rigctld = homebrew
    RadioSettings.ownPort = 4600
    let port = work.appendingPathComponent("cu.pretend-radio").path
    FileManager.default.createFile(atPath: port, contents: nil)
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
    Settings.currentRadio = RadioSettings(model: 1, modelName: "Hamlib Dummy", port: port, baud: 38_400)
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

    // A rigctld left running by a force-quit: Solid Copy stops it before
    // starting its own.
    let leftover = Process()
    leftover.executableURL = homebrew
    leftover.arguments = ["-m", "1", "-r", port, "-T", "127.0.0.1", "-t", "4600"]
    leftover.standardError = FileHandle.nullDevice
    try! leftover.run()
    try! "\(leftover.processIdentifier)".write(to: RadioMonitor.pidURL, atomically: true, encoding: .utf8)
    monitor.use(Settings.currentRadio)
    check(waitFor("connected") { monitor.reading != nil }, "Solid Copy starts rigctld and connects")
    check(!leftover.isRunning, "and first stops a rigctld left over from before")
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

    // rigctld stops by itself: Solid Copy starts it again.
    run("/usr/bin/pkill", ["-f", "rigctld -m 1 -r \(port)"])
    check(waitFor("noticed") { monitor.reading == nil }, "Solid Copy notices rigctld stopped")
    check(waitFor("restarted", seconds: 20) { monitor.reading != nil }, "and starts it again, and reconnects")

    // The radio's port goes away (the TS-590SG switched off).
    let tonesBefore = tones.count
    try? FileManager.default.removeItem(atPath: port)
    check(waitFor("port gone") { monitor.state == .portMissing }, "port gone: off or unplugged")
    check(waitFor("rigctld stopped") { Result { try RigctldClient(host: "127.0.0.1", port: 4600).reading() }.failure == .notRunning },
          "and its rigctld is stopped, freeing the port")
    // ...and comes back.
    FileManager.default.createFile(atPath: port, contents: nil)
    check(waitFor("back", seconds: 20) { monitor.reading != nil }, "port back: rigctld started again, connected")
    check(Array(tones.dropFirst(tonesBefore)) == [.radioLost, .radioBack],
          "the radio dropping plays the lost tone once, and its return the back tone once: \(tones)")
    // However it went down, every lost is followed by one back.
    check(tones.count.isMultiple(of: 2) && tones.enumerated().allSatisfy { $1 == ($0.isMultiple(of: 2) ? .radioLost : .radioBack) },
          "lost and back tones take turns: \(tones)")

    monitor.stop()
    check(waitFor("stopped") { Result { try RigctldClient(host: "127.0.0.1", port: 4600).reading() }.failure == .notRunning },
          "stopping (as Solid Copy quits) stops its rigctld")

    // A radio that's off but whose port stays (the KX3, whose USB chip is
    // in its cable): a pretend serial port that never answers. The
    // trouble is said once, however often rigctld is restarted, and the
    // restarts slow down. (Restarts here after 3 seconds' silence, then
    // 30, rather than 10 and 30, to keep the check short.)
    let silentPort = posix_openpt(O_RDWR | O_NOCTTY)
    check(silentPort >= 0 && grantpt(silentPort) == 0 && unlockpt(silentPort) == 0, "a pretend silent serial port")
    defer { close(silentPort) }
    RadioMonitor.restartDelays = [3, 30, 60]
    var said: [String] = []
    RadioMonitor.say = { said.append($0) }
    monitor.use(RadioSettings(model: 2037, modelName: "Silent TS-590SG", port: String(cString: ptsname(silentPort)),
                              baud: 38_400))
    let trouble = { said.filter { $0.contains("not answering") || $0.contains("not running") } }
    check(waitFor("silent", seconds: 30) { !trouble().isEmpty }, "a silent radio is noticed: \(said)")
    check(waitFor("restarted", seconds: 40) { monitor.startsWithoutReading >= 2 }, "rigctld restarted after 3 seconds' silence")
    let starts = monitor.startsWithoutReading
    _ = waitFor("quiet", seconds: 20) { false }
    check(trouble().count == 1, "and the trouble said only once: \(said)")
    check(monitor.startsWithoutReading == starts, "the next restart waits longer (30 seconds)")
    monitor.stop()
}

extension Result {
    var success: Success? { try? get() }
    var failure: RigctldClient.Failure? {
        if case .failure(let error) = self { return error as? RigctldClient.Failure }
        return nil
    }
}
