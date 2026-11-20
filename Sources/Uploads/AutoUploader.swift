// AutoUploader.swift
//
// Sends new contacts to LoTW, QRZ Logbook, Club Log and eQSL by themselves, if you chose
// that in Settings > Uploads (AutoUpload in Upload.swift): soon after each
// contact, or five minutes after the last one. By hand is the default:
// nothing is sent unless you turn it on.
//
// Only contacts logged on the form while Solid Copy is open are sent this
// way, never your older ones (an import of thousands shouldn't go up
// without asking; QSL > Upload or Sync sends those). Each new contact
// waits; every new one restarts the wait, so a run of contacts goes up
// together, as they are by then (lookup details, corrections).
//
// What you hear: nothing when it works (you're logging). A problem is
// said once, with the warning sound. If the internet is down, the
// contacts keep waiting, and go with the next contact you log or after
// ten minutes, whichever is first.
//
// The waiting list is saved as it changes (user defaults, key
// "autoUpload.waiting"), so quitting during the wait loses nothing: the
// next launch sends them half a minute after opening. Before 16 November
// 2026 quitting forgot them, which mattered once Scott chose "five
// minutes after the last contact": log the last one, quit, and it stayed
// behind.

import AppKit

@MainActor
final class AutoUploader {
    static let shared = AutoUploader()

    // Set at launch; contacts left waiting when Solid Copy last quit are
    // picked up then.
    var logbook: Logbook? {
        didSet { if logbook != nil, oldValue == nil { resumeSaved() } }
    }
    // How a report of trouble is told; the checks listen in here.
    var tell: (String) -> Void = { text in
        UploadReport.last = text
        Speaker.Cue.warning.play()
        Speaker.announce(text)
    }
    // How each service uploads; the checks swap in pretend ones.
    var uploaders: [UploadService: @MainActor ([QSO], Logbook) async -> UploadReport] = [
        .lotw: { await LoTWSync.upload($0, to: $1) },
        .qrzLogbook: { await QRZLogbookUpload.upload($0, logbook: $1) },
        .clubLog: { await ClubLogUpload.upload($0, logbook: $1) },
        .eqsl: { await EQSLUpload.upload($0, logbook: $1) },
    ]
    // Seconds to wait, from the setting; the checks shorten it.
    var delay: (AutoUpload) -> TimeInterval = { $0.delay }
    static let retryAfter: TimeInterval = 600

    private var waiting: [UploadService: Set<UUID>] = [:] {
        didSet { if waiting != oldValue { save() } }
    }
    // How long after launch saved contacts go: time for the window to
    // open and the internet to be up, without making you wait.
    var resumeAfter: TimeInterval = 30
    static let savedKey = "autoUpload.waiting"
    private var timers: [UploadService: Timer] = [:]
    private var busy: Set<UploadService> = []
    // The last problem said for each service, so it isn't said again and
    // again while it lasts.
    private var lastProblem: [UploadService: String] = [:]

    // The waiting list, as service name -> contact IDs.
    private func save() {
        let plain = Dictionary(uniqueKeysWithValues: waiting.compactMap { service, ids in
            ids.isEmpty ? nil : (service.rawValue, ids.map(\.uuidString).sorted())
        })
        if plain.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.savedKey)
        } else {
            UserDefaults.standard.set(plain, forKey: Self.savedKey)
        }
    }

    // What was waiting when Solid Copy last quit, sent soon. A service
    // turned back to By hand since then gets nothing (run checks again).
    // IDs that aren't contacts any more simply match nothing.
    private func resumeSaved() {
        guard let saved = UserDefaults.standard.dictionary(forKey: Self.savedKey) as? [String: [String]] else { return }
        for (name, strings) in saved {
            guard let service = UploadService(rawValue: name) else { continue }
            let ids = Set(strings.compactMap(UUID.init(uuidString:)))
            guard !ids.isEmpty else { continue }
            waiting[service, default: []].formUnion(ids)
            schedule(service, after: resumeAfter)
        }
    }

    // Sends whatever's waiting now, for every service: before switching
    // to another log, so the log being left doesn't keep its contacts
    // waiting (they'd match nothing in the next one).
    func sendWaitingNow() async {
        for service in UploadService.allCases where waitingCount(service) > 0 {
            timers[service]?.invalidate()
            timers[service] = nil
            await run(service)
        }
    }

    // Contacts waiting for a service (for the checks).
    func waitingCount(_ service: UploadService) -> Int { waiting[service]?.count ?? 0 }

    // A contact was just logged on the form.
    func logged(_ id: UUID) {
        // A test log's contacts never wait to go anywhere.
        guard logbook?.isTest != true else { return }
        for service in UploadService.allCases {
            let when = Settings.autoUpload(service)
            guard when != .byHand else { continue }
            waiting[service, default: []].insert(id)
            schedule(service, after: delay(when))
        }
    }

    private func schedule(_ service: UploadService, after seconds: TimeInterval) {
        timers[service]?.invalidate()
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in
            MainActor.assumeIsolated { AutoUploader.shared.start(service) }
        }
        RunLoop.main.add(timer, forMode: .common)
        timers[service] = timer
    }

    private func start(_ service: UploadService) {
        timers[service] = nil
        Task { await run(service) }
    }

    // Uploads what's waiting for a service now (also for the checks).
    func run(_ service: UploadService) async {
        guard let logbook, let ids = waiting[service], !ids.isEmpty else { return }
        guard !logbook.isTest else { waiting[service] = nil; return }
        // Turned off meanwhile: nothing goes.
        guard Settings.autoUpload(service) != .byHand else { waiting[service] = nil; return }
        // A sync or upload by hand is running: try again in a minute.
        guard !busy.contains(service), !(service == .lotw ? LoTWSync.running : OneByOneUpload.running.contains(service)) else {
            return schedule(service, after: 60)
        }
        // As they are now; deleted ones (or an Undo of logging) drop out.
        let contacts = logbook.contacts.filter { ids.contains($0.id) && !service.isUploaded($0) }
        waiting[service] = nil
        guard !contacts.isEmpty, let upload = uploaders[service] else { return }
        busy.insert(service)
        let what = "Automatic upload: \(contacts.count == 1 ? "1 contact" : "\(contacts.count) contacts")"
        let report = await Activity.shared.track(service.name, what, { _ in
            await upload(contacts, logbook)
        }, finish: { ($0.ok, $0.text) })
        busy.remove(service)
        if report.ok {
            lastProblem[service] = nil
            return
        }
        if report.tryAgain {
            waiting[service, default: []].formUnion(contacts.map(\.id))
            schedule(service, after: Self.retryAfter)
        }
        if lastProblem[service] != report.text {
            lastProblem[service] = report.text
            // LoTW's words don't name it (they're also Sync's), so add it.
            tell("Automatic upload. " + (service == .lotw ? "LoTW. " : "") + report.text)
        }
    }
}
