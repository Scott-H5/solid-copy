// tools/logs-check/main.swift
//
// Checks separate logs (LogList.swift) and that a test log never uploads,
// in a temporary folder and a settings domain of its own, so nothing of
// yours is touched:
//   - the list: the main log always first, new logs added with unique
//     names, the log in use remembered, the main log can't be removed;
//   - where each log's file goes (the main log where it always was);
//   - a test log: QRZ Logbook and LoTW refuse it before sending anything,
//     and automatic uploads never queue its contacts.
//
// Run it with:  bash tools/check-logs.sh

import AppKit

func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }

let suite = "solidcopy.logs-check.\(UUID().uuidString)"
LogList.defaults = UserDefaults(suiteName: suite)!
defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
let work = FileManager.default.temporaryDirectory.appendingPathComponent("logs-check-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }

// MARK: The list
check(LogList.all == [.main] && LogList.current == .main, "to start: just the main log, in use")
let contest = LogList.add(name: "  Field Day 2027 ", isTest: false)
let practice = LogList.add(name: "", isTest: true)
let again = LogList.add(name: "field day 2027", isTest: false)
check(contest.name == "Field Day 2027" && !contest.isTest, "a named log, trimmed")
check(practice.name == "Test log" && practice.isTest && practice.title == "Test log (test log)",
      "a test log with no name gets one, and says it's a test log")
check(again.name == "field day 2027 2", "a name already used gets a number: \(again.name)")
check(LogList.all.map(\.id) == [LogInfo.mainID, contest.id, practice.id, again.id], "main first, then in the order made")
LogList.use(practice)
check(LogList.current == practice, "the log in use is remembered")
LogList.remove(.main)
check(LogList.all.first == .main, "the main log can't be removed")
LogList.remove(practice)
check(LogList.current == .main && !LogList.all.contains(practice), "removing the log in use goes back to the main log")
LogList.defaults.set("not a uuid", forKey: "currentLog")
check(LogList.current == .main, "a damaged setting falls back to the main log")
LogList.defaults.set(Data("junk".utf8), forKey: "logs")
check(LogList.all == [.main], "a damaged list still has the main log")

// MARK: Contest logs
let fdLog = LogList.add(name: "Field Day 2027 test", isTest: false, contest: "ARRL-FIELD-DAY")
check(LogList.all.first { $0.id == fdLog.id }?.contest == "ARRL-FIELD-DAY" && contest.contest == nil,
      "a contest log remembers its contest; other logs have none")

// MARK: Each log remembers its profile
let fieldDayProfile = UUID()
let fd = LogList.add(name: "Field Day 2027", isTest: false)
check(LogList.all.first { $0.id == fd.id }?.profileID == nil, "a new log has no profile yet")
LogList.setProfile(fieldDayProfile, for: fd.id)
check(LogList.all.first { $0.id == fd.id }?.profileID == fieldDayProfile, "a log remembers the profile used with it")
LogList.setProfile(fieldDayProfile, for: LogInfo.mainID)
check(LogList.all.first?.profileID == fieldDayProfile && LogList.all.first?.isMain == true,
      "the main log remembers one too, and stays first")

// MARK: Where files go
let base = URL(fileURLWithPath: "/Base/Solid Copy")
check(LogList.fileURL(for: .main, in: base).path == "/Base/Solid Copy/Logbook.sqlite", "the main log stays where it was")
check(LogList.fileURL(for: contest, in: base).path == "/Base/Solid Copy/Logs/\(contest.id.uuidString)/Logbook.sqlite",
      "another log has a folder of its own, named by its ID")

// MARK: A test log never uploads
MainActor.assumeIsolated {
    let testInfo = LogInfo(id: UUID(), name: "Practice", isTest: true, created: Date())
    let database = try! LogDatabase(fileURL: work.appendingPathComponent("test.sqlite"))
    let logbook = try! Logbook(database: database, info: testInfo)
    var qso = QSO(call: "W1AW", timeOn: Date()); qso["band"] = "20m"
    try! logbook.add(qso)
    check(logbook.isTest && logbook.info.title == "Practice (test log)", "a test logbook knows it is one")

    var sent = 0
    OneByOneUpload.send = { _ in sent += 1; return (Data("RESULT=OK".utf8), URLResponse()) }
    QRZLogbookUpload.key = { "TEST-KEY" }
    let semaphore = DispatchSemaphore(value: 0)
    ClubLogUpload.token = { "cl_TEST" }
    EQSLUpload.login = { ("N0CALL", "secret", "") }
    var qrz = UploadReport(text: "", ok: true), lotw = UploadReport(text: "", ok: true), sync = ""
    var clubLog = qrz, eqsl = qrz, qrzSync = ""
    Task { @MainActor in
        qrz = await QRZLogbookUpload.upload(logbook.contacts, logbook: logbook)
        clubLog = await ClubLogUpload.upload(logbook.contacts, logbook: logbook)
        eqsl = await EQSLUpload.upload(logbook.contacts, logbook: logbook)
        qrzSync = await QRZLogbookSync.sync(logbook) { _ in }
        lotw = await LoTWSync.upload(logbook.contacts, to: logbook)
        sync = await LoTWSync.sync(logbook) { _ in }
        semaphore.signal()
    }
    while semaphore.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    check(sent == 0 && !qrz.ok && qrz.text == UploadReport.testLogText, "QRZ Logbook refuses a test log, sending nothing")
    check(!clubLog.ok && clubLog.text == UploadReport.testLogText && !eqsl.ok && eqsl.text == UploadReport.testLogText,
          "Club Log and eQSL refuse a test log, sending nothing")
    check(sent == 0 && qrzSync == UploadReport.testLogText, "QRZ Logbook sync refuses a test log (no confirmations either)")
    check(!lotw.ok && lotw.text == UploadReport.testLogText, "LoTW upload refuses a test log")
    check(sync == UploadReport.testLogText, "LoTW sync refuses a test log (no confirmations either)")
    check(!UploadService.qrzLogbook.isUploaded(logbook.contacts[0]), "nothing marked uploaded")

    let auto = AutoUploader()
    auto.resumeAfter = 3600
    auto.logbook = logbook
    for service in UploadService.allCases { Settings.setAutoUpload(.soonAfterEach, for: service) }
    auto.logged(logbook.contacts[0].id)
    check(UploadService.allCases.allSatisfy { auto.waitingCount($0) == 0 }, "automatic uploads never queue a test log's contacts")
    for service in UploadService.allCases { UserDefaults.standard.removeObject(forKey: "autoUpload.\(service.rawValue)") }
}
// MARK: Copy and paste between logs (what Command-C and Command-V use)
MainActor.assumeIsolated {
    let from = try! Logbook(database: LogDatabase(fileURL: work.appendingPathComponent("from.sqlite")))
    var a = QSO(call: "K5ZZZ", timeOn: QSO.date(adifDate: "20261116", adifTime: "201200")!)
    a["band"] = "20m"; a["mode"] = "CW"; a["skcc"] = "26050T"; a["notes"] = "Tom, two lines\nof notes"
    a["lotw_qsl_sent"] = "Y"; a["app_solidcopy_qsl_card"] = "K5ZZZ.jpg"
    try! from.add(a)
    let copied = LogExport.adif(from.contacts, includeNotes: true)
    let read = ADIFImport.read(copied).contacts
    check(read.count == 1, "the copy reads back as one contact")
    let back = read[0]
    let same = LogField.all.map(\.adif).filter { $0 != "app_solidcopy_qsl_card" }.allSatisfy { back[$0] == a[$0] }
    check(same && back.call == a.call && back.timeOn == a.timeOn, "every field comes across, Notes too")
    let into = try! Logbook(database: LogDatabase(fileURL: work.appendingPathComponent("into.sqlite")),
                            info: LogInfo(id: UUID(), name: "Practice", isTest: true, created: Date()))
    let first = try! into.importContacts(read)
    let second = try! into.importContacts(ADIFImport.read(copied).contacts)
    check(first.added.count == 1 && second.added.isEmpty && second.skipped == 1 && into.contacts.count == 1,
          "pasting twice adds the contact once")
    check(into.contacts[0].id != a.id, "a pasted contact is a new contact in its new log")
}
print("All log checks passed.")
