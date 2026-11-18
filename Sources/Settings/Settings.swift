// Settings.swift
//
// Your settings, kept between launches. Most are in "user defaults", the
// standard Mac place for an app's preferences. The QRZ password is the
// exception: it's in the Keychain (Keychain.swift), never in a file.
//
// The Settings window (SettingsWindowController.swift) changes these.

import Foundation

// One field on the logging form: which field (its ADIF name), whether Tab
// stops on it, and what it starts as on a fresh form ("5" for Power when
// portable), if anything. Signal reports start blank, so a report is
// only logged when you type the one actually given.
struct FormFieldChoice: Codable, Equatable {
    var adif: String
    var tabStop: Bool
    var startingValue: String = ""

    init(adif: String, tabStop: Bool, startingValue: String = "") {
        self.adif = adif
        self.tabStop = tabStop
        self.startingValue = startingValue
    }

    // Settings saved before starting values existed have none: blank.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        adif = try values.decode(String.self, forKey: .adif)
        tabStop = try values.decode(Bool.self, forKey: .tabStop)
        startingValue = try values.decodeIfPresent(String.self, forKey: .startingValue)
            ?? ""
    }
}

// An operating profile, such as "Home" or "Portable": a logging form, and
// your station's details (callsign, grid, park, radio, ...), which are
// added to every contact logged with it. One profile is in use at a time.
struct Profile: Codable, Equatable {
    var id = UUID()
    var name: String
    // The fields on the logging form after Callsign, in order.
    var formFields: [FormFieldChoice]
    // Your station, by ADIF name: the "My station" fields in LogField.swift
    // (station_callsign, my_gridsquare, my_pota_ref, my_rig, ...).
    var station: [String: String] = [:]
    // The CW messages F1 to F8 send with this profile (CWMessages.swift),
    // or nil to use the starting set. A profile from a contest template
    // comes with that contest's messages (Field Day's CQ FD, say).
    var cwMessages: [String]?
}

// Radios were briefly kept in profiles (14 November 2026). Only used to
// move them into the radio list.
private struct ProfileWithRadio: Decodable {
    var id: UUID
    var radio: RadioSettings?
}

enum Settings {
    private static let defaults = UserDefaults.standard

    // Sent whenever a setting that changes the main window (the form's
    // fields, the log's columns) changes, so the window can rebuild.
    static let didChange = Notification.Name("SolidCopySettingsDidChange")

    // Called once at launch: the values used until you change them.
    static func registerDefaults() {
        defaults.register(defaults: [
            Key.lookupEnabled: true,
            Key.useCallook: true,
            Key.skccLookup: true,
        ])
        blankSignalReportsOnce()
    }

    // Signal reports used to start at 59. Once, clear that from profiles
    // saved then, so they start blank too (15 November 2026). A 59 you
    // set yourself afterwards, in Logging Form > Starting value, stays.
    private static func blankSignalReportsOnce() {
        guard !defaults.bool(forKey: Key.reportsBlanked) else { return }
        defaults.set(true, forKey: Key.reportsBlanked)
        guard let saved: [Profile] = decoded(Key.profiles) else { return }
        profiles = saved.map { profile in
            var profile = profile
            for index in profile.formFields.indices
            where ["rst_sent", "rst_rcvd"].contains(profile.formFields[index].adif)
                && profile.formFields[index].startingValue == "59" {
                profile.formFields[index].startingValue = ""
            }
            return profile
        }
    }

    private enum Key {
        static let skccLookup = "skccLookup"
        static let lookupEnabled = "lookupEnabled"
        static let qrzUsername = "qrzUsername"
        static let useCallook = "useCallook"
        static let myCallsign = "myCallsign"
        static let myGrid = "myGrid"
        static let formFields = "formFields"
        static let profiles = "profiles"
        static let currentProfile = "currentProfile"
        static let logColumns = "logColumns"
        static let columnWidths = "columnWidths"
        static let radios = "radios"
        static let reportsBlanked = "reportsBlanked"
        static let currentRadio = "currentRadio"
    }

    // MARK: - Radios

    // Your radios (Settings > Radio), in the order you added them.
    static var radios: [RadioSettings] {
        get {
            if let saved: [RadioSettings] = decoded(Key.radios) { return saved }
            // First time: gather the radios that were in profiles, once
            // each, and keep using the profile in use's radio.
            let old: [ProfileWithRadio] = decoded(Key.profiles) ?? []
            var found: [RadioSettings] = []
            for radio in old.compactMap(\.radio) where !found.contains(where: { $0.model == radio.model
                && $0.port == radio.port && $0.address == radio.address }) {
                found.append(radio)
            }
            let currentID = defaults.string(forKey: Key.currentProfile)
            let inUse = old.first { $0.id.uuidString == currentID }?.radio
            let current = found.first { $0.model == inUse?.model && $0.port == inUse?.port }
            defaults.set(try? JSONEncoder().encode(found), forKey: Key.radios)
            defaults.set(current?.id.uuidString ?? "", forKey: Key.currentRadio)
            return found
        }
        set { encode(newValue, Key.radios) }
    }

    // The radio in use, or nil for none. Setting it saves your changes to
    // it (or adds it, if it's new) and makes it the one in use.
    static var currentRadio: RadioSettings? {
        get {
            let all = radios
            let id = defaults.string(forKey: Key.currentRadio)
            return all.first { $0.id.uuidString == id }
        }
        set {
            guard let newValue else { return useRadio(nil) }
            var all = radios
            if let index = all.firstIndex(where: { $0.id == newValue.id }) {
                all[index] = newValue
            } else {
                all.append(newValue)
            }
            defaults.set(newValue.id.uuidString, forKey: Key.currentRadio)
            radios = all
        }
    }

    // Switches to another radio, or to none.
    static func useRadio(_ id: UUID?) {
        defaults.set(id?.uuidString ?? "", forKey: Key.currentRadio)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    // MARK: - Profiles

    // The Home form: Name starts on the form but not as a Tab stop, because
    // lookups fill it in (accessibility contract, rule 7).
    static let defaultFormFields = [
        FormFieldChoice(adif: "name", tabStop: false),
        FormFieldChoice(adif: "rst_sent", tabStop: true),
        FormFieldChoice(adif: "rst_rcvd", tabStop: true),
        FormFieldChoice(adif: "comment", tabStop: true),
    ]

    // The Portable form, for when the radio or the internet isn't there:
    // band, mode, frequency and power are typed, so they're Tab stops, and
    // power starts at 5 watts.
    static let portableFormFields = [
        FormFieldChoice(adif: "name", tabStop: false),
        FormFieldChoice(adif: "band", tabStop: true),
        FormFieldChoice(adif: "mode", tabStop: true),
        FormFieldChoice(adif: "freq", tabStop: true),
        FormFieldChoice(adif: "tx_pwr", tabStop: true, startingValue: "5"),
        FormFieldChoice(adif: "rst_sent", tabStop: true),
        FormFieldChoice(adif: "rst_rcvd", tabStop: true),
        FormFieldChoice(adif: "comment", tabStop: true),
    ]

    // Ready-made forms a new profile can start from (Settings > Profiles >
    // New Profile). Each is only a starting point: change its fields in
    // Logging Form afterwards. Name is never a Tab stop, as lookups fill it
    // in; fields the radio or a lookup fills (band, state) aren't either.
    // Contest exchanges are typed as text for now; serial numbers that
    // count themselves, dupes and scoring come with contest support.
    struct Template {
        let name: String
        // What it's for, said in its menu item.
        let about: String
        let formFields: [FormFieldChoice]
        // CW messages for the contest, if any (CWMessages.swift).
        var cwMessages: [String]?
    }

    static let templates: [Template] = [
        Template(name: "Home", about: "name, reports and comment", formFields: defaultFormFields),
        Template(name: "Portable", about: "band, mode, frequency and power typed, for no radio or internet",
                 formFields: portableFormFields),
        Template(name: "POTA activation", about: "their park, for park to park", formFields: [
            FormFieldChoice(adif: "name", tabStop: false),
            FormFieldChoice(adif: "rst_sent", tabStop: true),
            FormFieldChoice(adif: "rst_rcvd", tabStop: true),
            FormFieldChoice(adif: "state", tabStop: false),
            FormFieldChoice(adif: "pota_ref", tabStop: true),
            FormFieldChoice(adif: "comment", tabStop: true),
        ]),
        Template(name: "SOTA activation", about: "their summit, for summit to summit", formFields: [
            FormFieldChoice(adif: "name", tabStop: false),
            FormFieldChoice(adif: "rst_sent", tabStop: true),
            FormFieldChoice(adif: "rst_rcvd", tabStop: true),
            FormFieldChoice(adif: "sota_ref", tabStop: true),
            FormFieldChoice(adif: "comment", tabStop: true),
        ]),
        Template(name: "Field Day", about: "their class and section, typed as one", formFields: [
            FormFieldChoice(adif: "srx_string", tabStop: true),
            FormFieldChoice(adif: "stx_string", tabStop: false),
            FormFieldChoice(adif: "contest_id", tabStop: false, startingValue: "ARRL-FIELD-DAY"),
        ], cwMessages: CWMessages.fieldDay),
        Template(name: "State QSO Party", about: "reports and their county or state", formFields: [
            FormFieldChoice(adif: "rst_sent", tabStop: true),
            FormFieldChoice(adif: "rst_rcvd", tabStop: true),
            FormFieldChoice(adif: "srx_string", tabStop: true),
            FormFieldChoice(adif: "stx_string", tabStop: false),
            FormFieldChoice(adif: "contest_id", tabStop: false),
        ]),
    ]

    // Every profile, in menu order. The first time, Home is made from your
    // earlier settings (form, callsign and grid) and Portable is added.
    static var profiles: [Profile] {
        get {
            if let saved: [Profile] = decoded(Key.profiles), !saved.isEmpty { return saved }
            var station: [String: String] = [:]
            if let call = defaults.string(forKey: Key.myCallsign), !call.isEmpty { station["station_callsign"] = call }
            if let grid = defaults.string(forKey: Key.myGrid), !grid.isEmpty { station["my_gridsquare"] = grid }
            let home = Profile(name: "Home", formFields: decoded(Key.formFields) ?? defaultFormFields, station: station)
            var portableStation: [String: String] = [:]
            portableStation["station_callsign"] = station["station_callsign"]
            let portable = Profile(name: "Portable", formFields: portableFormFields, station: portableStation)
            // Saved straight away, so they keep the same identities.
            let made = [home, portable]
            defaults.set(try? JSONEncoder().encode(made), forKey: Key.profiles)
            defaults.set(home.id.uuidString, forKey: Key.currentProfile)
            return made
        }
        set { encode(newValue, Key.profiles) }
    }

    // The profile in use.
    static var currentProfile: Profile {
        get {
            let all = profiles
            let id = defaults.string(forKey: Key.currentProfile).flatMap(UUID.init(uuidString:))
            return all.first { $0.id == id } ?? all[0]
        }
        set {
            var all = profiles
            if let index = all.firstIndex(where: { $0.id == newValue.id }) {
                all[index] = newValue
            } else {
                all.append(newValue)
            }
            defaults.set(newValue.id.uuidString, forKey: Key.currentProfile)
            profiles = all
        }
    }

    // The profile for a contest (Contest.swift): one whose form logs that
    // contest (its Contest field starts as the contest's ID), or a new one
    // made from the contest's file (Contest.swift): Callsign, Serial
    // received if the contest has serials, its exchange fields, then (not
    // Tab stops) Exchange sent for {SENT}, Serial sent if it has serials,
    // and Contest set to its ID; its CW messages if the file has some.
    // Your station comes from the profile in use, less where you're
    // operating from (park, summit, special event). Returns its ID;
    // doesn't switch to it.
    static func profile(for contest: Contest) -> UUID {
        let all = profiles
        if let existing = all.first(where: { profile in
            profile.formFields.contains { $0.adif == "contest_id"
                && $0.startingValue.caseInsensitiveCompare(contest.id) == .orderedSame }
        }) { return existing.id }
        var station = currentProfile.station
        for adif in ["my_pota_ref", "my_sota_ref", "my_wwff_ref", "my_sig", "my_sig_info"] { station[adif] = nil }
        let names = Set(all.map(\.name))
        var name = contest.name, number = 2
        while names.contains(name) {
            name = "\(contest.name) \(number)"
            number += 1
        }
        var formFields: [FormFieldChoice] = []
        if contest.serial { formFields.append(FormFieldChoice(adif: "srx", tabStop: true)) }
        formFields += contest.exchange.map { FormFieldChoice(adif: $0, tabStop: true) }
        if !contest.exchange.contains("stx_string") {
            formFields.append(FormFieldChoice(adif: "stx_string", tabStop: false))
        }
        if contest.serial { formFields.append(FormFieldChoice(adif: "stx", tabStop: false)) }
        formFields.append(FormFieldChoice(adif: "contest_id", tabStop: false, startingValue: contest.id))
        let profile = Profile(name: name, formFields: formFields, station: station,
                              cwMessages: contest.messages.isEmpty ? nil : contest.messages)
        profiles = all + [profile]
        return profile.id
    }

    // Switches to another profile.
    static func useProfile(_ id: UUID) {
        defaults.set(id.uuidString, forKey: Key.currentProfile)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    // The current profile's logging form: the fields after Callsign (which
    // is always first and always a Tab stop), in order.
    static var formFields: [FormFieldChoice] {
        get { currentProfile.formFields }
        set { currentProfile.formFields = newValue }
    }

    // MARK: - Log columns

    // The log's columns, in order, by ID: "call", "date" and "time", or a
    // field's ADIF name.
    static let defaultLogColumns = ["call", "name", "date", "time", "band", "freq", "mode",
                                    "rst_sent", "rst_rcvd", "country", "comment"]

    static var logColumns: [String] {
        get { decoded(Key.logColumns) ?? defaultLogColumns }
        set { encode(newValue, Key.logColumns) }
    }

    // Column widths you've set by dragging, by column ID.
    static var columnWidths: [String: Double] {
        get { decoded(Key.columnWidths) ?? [:] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.columnWidths) }
    }

    private static func decoded<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    // Saves a setting and tells the main window.
    private static func encode<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    // Look up each callsign when you leave the Callsign field.
    // How much is said for each adjustable kind of message (Settings >
    // Speech). Everything is said in full until you change it.
    static func speechLevel(for kind: Speaker.Kind) -> Speaker.Level {
        let saved = defaults.string(forKey: "speech." + kind.rawValue).flatMap(Speaker.Level.init(rawValue:))
        return saved.flatMap { kind.levels.contains($0) ? $0 : nil } ?? .full
    }

    static func setSpeechLevel(_ level: Speaker.Level, for kind: Speaker.Kind) {
        defaults.set(level.rawValue, forKey: "speech." + kind.rawValue)
    }

    // Settings > Speech, Sounds (Tone.swift): the sound for a dupe and for
    // "needed", by its saved name. A name no longer offered gets the
    // standard one.
    static func alertSound(for alert: Alert) -> String {
        let saved = defaults.string(forKey: "sound." + alert.rawValue) ?? ""
        return Alert.choices.contains { $0.id == saved } ? saved : alert.standard
    }
    static func setAlertSound(_ id: String, for alert: Alert) {
        defaults.set(id, forKey: "sound." + alert.rawValue)
    }

    // Which DX cluster spots play the needed sound as they come in: new
    // countries only (the standard: a young log needs nearly every band
    // and mode, and would chime all day), anything needed, or none.
    enum NeededSpotSound: String, CaseIterable {
        case newCountry, anyNeeded, off
        var title: String {
            switch self {
            case .newCountry: "New countries only"
            case .anyNeeded: "New country, band or mode"
            case .off: "No sound"
            }
        }
    }
    static var neededSpotSound: NeededSpotSound {
        get { NeededSpotSound(rawValue: defaults.string(forKey: "sound.neededSpots") ?? "") ?? .newCountry }
        set { defaults.set(newValue.rawValue, forKey: "sound.neededSpots") }
    }

    // Settings > Spots: the DX cluster, off until turned on, and its node
    // (VE7CC unless you choose another; the same as DXCluster.nodes[0],
    // written out so this file doesn't need the Spots code).
    static var clusterEnabled: Bool {
        get { defaults.bool(forKey: "cluster.enabled") }
        set { defaults.set(newValue, forKey: "cluster.enabled") }
    }
    static var clusterHost: String {
        get { defaults.string(forKey: "cluster.host").flatMap { $0.isEmpty ? nil : $0 } ?? "dxc.ve7cc.net" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: "cluster.host") }
    }
    // Machine-heard CW spots (the Reverse Beacon Network's skimmers) and
    // FT8/FT4 spots: many nodes leave them out unless asked. Off at first.
    static var clusterSkimmer: Bool {
        get { defaults.bool(forKey: "cluster.skimmer") }
        set { defaults.set(newValue, forKey: "cluster.skimmer") }
    }
    static var clusterFT8: Bool {
        get { defaults.bool(forKey: "cluster.ft8") }
        set { defaults.set(newValue, forKey: "cluster.ft8") }
    }
    // Settings > Uploads, LoTW (LoTW.swift). The website login: the username is
    // usually your callsign; the password is in the Keychain.
    static var lotwUsername: String {
        get { defaults.string(forKey: "lotw.username") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: "lotw.username") }
    }
    static var lotwPassword: String {
        Keychain.password(for: lotwUsername, service: Keychain.lotwService) ?? ""
    }
    // The TQSL station location to sign with, as it's named in TQSL
    // ("Anytown, N0CALL").
    static var tqslLocation: String {
        get { defaults.string(forKey: "lotw.location") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: "lotw.location") }
    }
    // Upload only contacts from this UTC day on ("2020-01-01"), or every
    // contact when empty.
    static var lotwUploadFrom: String {
        get { defaults.string(forKey: "lotw.uploadFrom") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: "lotw.uploadFrom") }
    }
    // LoTW's own "latest confirmation" time from the last download, sent
    // back next time so only newer ones come (LoTW's advice).
    static var lotwLastQSL: String {
        get { defaults.string(forKey: "lotw.lastQSL") ?? "" }
        set { defaults.set(newValue, forKey: "lotw.lastQSL") }
    }
    // Settings > Uploads, QRZ Logbook (QRZLogbook.swift): your logbook's
    // API key, from the logbook's Settings on qrz.com, kept in the
    // Keychain ("Solid Copy: QRZ Logbook") like a password.
    static var qrzLogbookKey: String {
        Keychain.password(for: Keychain.qrzLogbookAccount, service: Keychain.qrzLogbookService) ?? ""
    }
    // Like lotwUploadFrom, for QRZ Logbook.
    static var qrzUploadFrom: String {
        get { defaults.string(forKey: "qrzLogbook.uploadFrom") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: "qrzLogbook.uploadFrom") }
    }
    // Like lotwUploadFrom, for any service (Club Log, eQSL; LoTW and QRZ
    // Logbook keep their own names, above, from before there were four).
    static func uploadFrom(_ service: UploadService) -> String {
        switch service {
        case .lotw: lotwUploadFrom
        case .qrzLogbook: qrzUploadFrom
        default: defaults.string(forKey: "\(service.rawValue).uploadFrom") ?? ""
        }
    }
    static func setUploadFrom(_ day: String, for service: UploadService) {
        switch service {
        case .lotw: lotwUploadFrom = day
        case .qrzLogbook: qrzUploadFrom = day
        default: defaults.set(day.trimmingCharacters(in: .whitespaces), forKey: "\(service.rawValue).uploadFrom")
        }
    }
    // Settings > Uploads, Club Log (ClubLogUpload.swift): your token, made
    // on clublog.org (Settings, API), kept in the Keychain ("Solid Copy:
    // Club Log") like a password.
    static var clubLogToken: String {
        Keychain.password(for: Keychain.tokenAccount, service: Keychain.clubLogService) ?? ""
    }
    // Settings > Uploads, eQSL (EQSLUpload.swift): your eQSL username
    // (usually your callsign), its password in the Keychain ("Solid Copy:
    // eQSL"), and the QTH Nickname, only needed with more than one eQSL
    // account for your callsign.
    static var eqslUsername: String {
        get { defaults.string(forKey: "eqsl.username") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: "eqsl.username") }
    }
    static var eqslPassword: String {
        Keychain.password(for: eqslUsername, service: Keychain.eqslService) ?? ""
    }
    static var eqslQTHNickname: String {
        get { defaults.string(forKey: "eqsl.qthNickname") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: "eqsl.qthNickname") }
    }
    // When each service is sent new contacts by itself (Uploads.swift).
    // By hand unless you choose otherwise.
    static func autoUpload(_ service: UploadService) -> AutoUpload {
        AutoUpload(rawValue: defaults.string(forKey: "autoUpload.\(service.rawValue)") ?? "") ?? .byHand
    }
    static func setAutoUpload(_ when: AutoUpload, for service: UploadService) {
        defaults.set(when.rawValue, forKey: "autoUpload.\(service.rawValue)")
    }
    // Settings > Backups: the second folder backups are copied to, as a
    // bookmark (like the TQSL folder, below), when the last copy went
    // there, and a problem from a copy at quit, said at the next launch.
    static var backupFolderBookmark: Data? {
        get { defaults.data(forKey: "backup.folder") }
        set { defaults.set(newValue, forKey: "backup.folder") }
    }
    // How often to back up while Solid Copy stays open, if the log changed:
    // 0 never, else every so many hours (1, 4 or 24). Every 4 hours to
    // start: since only the newest 20 backups are kept, hourly ones on a
    // busy weekend would push out older days.
    static let backupScheduleChoices: [(hours: Int, title: String)] = [
        (0, "Never"), (1, "Every hour"), (4, "Every 4 hours"), (24, "Once a day"),
    ]
    static var backupEveryHours: Int {
        get { defaults.object(forKey: "backup.everyHours") as? Int ?? 4 }
        set { defaults.set(newValue, forKey: "backup.everyHours") }
    }
    static var backupLast: Date? {
        get { defaults.object(forKey: "backup.last") as? Date }
        set { defaults.set(newValue, forKey: "backup.last") }
    }
    static var backupProblem: String {
        get { defaults.string(forKey: "backup.problem") ?? "" }
        set { defaults.set(newValue, forKey: "backup.problem") }
    }

    // The folder Solid Copy and TQSL swap files in, as a bookmark (the
    // App Sandbox lets Solid Copy use a folder you chose, again later).
    static var lotwFolderBookmark: Data? {
        get { defaults.data(forKey: "lotw.folder") }
        set { defaults.set(newValue, forKey: "lotw.folder") }
    }

    static var clusterPort: Int {
        get { defaults.object(forKey: "cluster.port") == nil ? 23 : defaults.integer(forKey: "cluster.port") }
        set { defaults.set(newValue, forKey: "cluster.port") }
    }

    static var lookupEnabled: Bool {
        get { defaults.bool(forKey: Key.lookupEnabled) }
        set { defaults.set(newValue, forKey: Key.lookupEnabled) }
    }

    // Your QRZ.com username (usually your callsign). Empty means "don't use
    // QRZ".
    static var qrzUsername: String {
        get { defaults.string(forKey: Key.qrzUsername) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: Key.qrzUsername) }
    }

    // Your QRZ.com password, from the Keychain.
    static var qrzPassword: String {
        Keychain.password(for: qrzUsername) ?? ""
    }

    // Use callook.info (free, US calls only, no account) when QRZ isn't set
    // up or doesn't find a call.
    // Settings > CW (WinKeyer.swift, CWMessages.swift): the WinKeyer's
    // port, its speed, your name for messages, and the eight messages F1
    // to F8 send (those per profile: Profile.cwMessages).
    static var cwPort: String {
        get { defaults.string(forKey: "cw.port") ?? "" }
        set { defaults.set(newValue, forKey: "cw.port") }
    }
    static var cwSpeed: Int {
        // 5 to 99, what the WinKeyer takes; 20 to start.
        get { min(max(defaults.object(forKey: "cw.speed") as? Int ?? 20, 5), 99) }
        set { defaults.set(min(max(newValue, 5), 99), forKey: "cw.speed") }
    }
    static var cwMyName: String {
        get { defaults.string(forKey: "cw.myName") ?? "" }
        set { defaults.set(newValue, forKey: "cw.myName") }
    }
    // Whether the first-run setup sheet has been answered (FirstRunSheet.swift).
    static var firstRunDone: Bool {
        get { defaults.bool(forKey: "firstRunDone") }
        set { defaults.set(newValue, forKey: "firstRunDone") }
    }
    // The messages for the profile in use: its own, or (until it has
    // some) the starting set. A set saved before messages were per
    // profile (one day, 17 November 2026) is the starting set instead.
    // Changing them gives the profile in use its own.
    static var cwMessages: [String] {
        get {
            let base = currentProfile.cwMessages ?? defaults.stringArray(forKey: "cw.messages") ?? []
            return (0..<CWMessages.count).map { base.indices.contains($0) ? base[$0] : CWMessages.defaults[$0] }
        }
        set { currentProfile.cwMessages = Array(newValue.prefix(CWMessages.count)) }
    }

    // Settings > Clubs: use SKCC's member list (SKCCRoster.swift).
    static var skccLookup: Bool {
        get { defaults.bool(forKey: Key.skccLookup) }
        set { defaults.set(newValue, forKey: Key.skccLookup) }
    }

    static var useCallook: Bool {
        get { defaults.bool(forKey: Key.useCallook) }
        set { defaults.set(newValue, forKey: Key.useCallook) }
    }

    // MARK: - Your QSL card (Settings > QSL Card, ElectronicCard.swift)
    // Shared by every log and profile, like your logins: it's your card.

    // The fields on it, in order (ElectronicCard.choices ids).
    static var cardFields: [String] {
        get {
            let known = Set(ElectronicCard.choices.map(\.id))
            return (defaults.stringArray(forKey: "card.fields") ?? ElectronicCard.standardFields)
                .filter(known.contains)
        }
        set { defaults.set(newValue, forKey: "card.fields") }
    }

    // Your three lines under your call: name, QTH, and anything else
    // (club numbers, say).
    static var cardDetails: [String] {
        get { (0..<3).map { defaults.string(forKey: "card.details\($0)") ?? "" } }
        set {
            for index in 0..<3 {
                let line = newValue.indices.contains(index) ? newValue[index] : ""
                defaults.set(line.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "card.details\(index)")
            }
        }
    }

    // Said on a card whose contact has no QSL message of its own.
    static var cardMessage: String {
        get { defaults.string(forKey: "card.message") ?? "Thanks for the contact." }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "card.message") }
    }

    static var cardPictureDescription: String {
        get { defaults.string(forKey: "card.pictureDescription") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "card.pictureDescription") }
    }

    // Your picture, made ready when chosen (ElectronicCard.preparedPicture):
    // Application Support/Solid Copy/Card Picture.jpg. Nil if there's none.
    static var cardPictureFile: URL? {
        guard let url = try? LogList.baseFolder().appendingPathComponent("Card Picture.jpg"),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    static var cardDesign: ElectronicCard.Design {
        ElectronicCard.Design(fields: cardFields, details: cardDetails, message: cardMessage,
                              pictureDescription: cardPictureDescription, hasPicture: cardPictureFile != nil)
    }

    // (Your callsign and grid used to be kept here; they're now part of
    // each profile's station details. The old values become Home's.)
}
