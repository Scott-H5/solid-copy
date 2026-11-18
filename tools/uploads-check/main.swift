// tools/uploads-check/main.swift
//
// Checks uploads to QRZ Logbook, Club Log and eQSL, and automatic uploads, with no internet
// (a pretend QRZ answers) and nothing from your Keychain or Settings:
//   - which contacts go, and what's sent: the form safely encoded, one
//     ADIF record without Notes or Solid Copy's own fields;
//   - QRZ's answers read right: added, duplicate, refused, key problems;
//   - an upload marks only what QRZ has, keeps edits made meanwhile, and
//     stops when the internet is down;
//   - automatic uploads: off by default, only new contacts, a run sent
//     together, a problem said once, offline contacts kept for later.
//
// Run it with:  bash tools/check-uploads.sh

import AppKit

func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }
func at(_ adifDate: String, _ time: String) -> Date { QSO.date(adifDate: adifDate, adifTime: time)! }

// A log of its own, in a temporary folder, and a settings domain of its
// own, so nothing of yours is touched.
let work = FileManager.default.temporaryDirectory.appendingPathComponent("uploads-check-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }
func clearAutoUpload() {
    for service in UploadService.allCases { UserDefaults.standard.removeObject(forKey: "autoUpload.\(service.rawValue)") }
}
clearAutoUpload()
let logbook = try! Logbook(database: LogDatabase(fileURL: work.appendingPathComponent("log.sqlite")))

// MARK: - What goes

var old = QSO(call: "W1AW", timeOn: at("19990101", "120000"))
var sent = QSO(call: "K1ABC", timeOn: at("20260101", "120000")); sent["qrzcom_qso_upload_status"] = "Y"
let new = QSO(call: "K3ABC", timeOn: at("20260103", "120000"))
check(UploadService.qrzLogbook.toUpload([old, sent, new], from: "").map(\.call) == ["W1AW", "K3ABC"], "QRZ: everything not yet sent")
check(UploadService.qrzLogbook.toUpload([old, sent, new], from: "2020-01-01").map(\.call) == ["K3ABC"], "QRZ: from a day on")
check(UploadService.lotw.isUploaded({ var q = new; q["lotw_qsl_rcvd"] = "Y"; return q }()),
      "LoTW: a confirmed contact counts as uploaded")

var full = QSO(call: "VE6AAA", timeOn: at("20251217", "153000"))
full["band"] = "20m"; full["mode"] = "CW"; full["station_callsign"] = "N0CALL"
full["notes"] = "private"; full["app_solidcopy_card_text"] = "card words"; full["name"] = "Bob & Al"
let record = LogExport.adifRecord(full)
check(record.hasPrefix("<CALL:6>VE6AAA ") && record.hasSuffix("<EOR>") && !record.contains("<EOH>"),
      "one ADIF record, no header")
check(record.contains("<BAND:3>20m") && record.contains("<STATION_CALLSIGN:6>N0CALL"), "with its band and station")
check(!record.contains("NOTES") && !record.contains("APP_SOLIDCOPY"), "without Notes or Solid Copy's own fields")
check(OneByOneUpload.formEncoded("<A:2>x& =+é") == "%3CA%3A2%3Ex%26%20%3D%2B%C3%A9", "form encoding: nothing left to break it")
let body = String(decoding: QRZLogbook.insertBody(key: "AB-12", qso: full), as: UTF8.self)
check(body.hasPrefix("KEY=AB-12&ACTION=INSERT&ADIF=%3CCALL%3A6%3EVE6AAA") && body.contains("Bob%20%26%20Al"),
      "the form: key, INSERT, the record")

// MARK: - QRZ's answers

func answer(_ text: String) -> ContactAnswer { QRZLogbook.answer(from: Data(text.utf8)) }
check(answer("RESULT=OK&LOGID=130877825&COUNT=1") == .added, "OK: added")
check(answer("RESULT=REPLACE&LOGID=1&COUNT=1") == .added, "REPLACE: in the logbook")
check(answer("RESULT=FAIL&REASON=Unable to add QSO to database: duplicate&EXTENDED=") == .alreadyThere,
      "a duplicate: already there")
check(answer("RESULT=FAIL&REASON=QSO date outside of logbook range & more") == .refused("QSO date outside of logbook range & more"),
      "refused, with QRZ's reason (an & in it kept)")
if case .stop(_, false) = answer("RESULT=AUTH") {} else { check(false, "AUTH stops, not tried again") }
if case .stop(_, false) = answer("RESULT=FAIL&REASON=invalid api key") {} else { check(false, "a bad key stops") }
check(answer("RESULT=AUTH") != .added && answer("<html>error</html>") == .refused("QRZ's answer wasn't understood"),
      "AUTH stops; a web page isn't taken for success")
check(answer("") == .refused("QRZ sent an empty answer"), "an empty answer")

// MARK: - Uploading, with a pretend QRZ

let ok200 = HTTPURLResponse(url: QRZLogbook.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
var requests: [URLRequest] = []
var replies: [String] = []
QRZLogbookUpload.key = { "TEST-KEY" }
OneByOneUpload.send = { request in
    requests.append(request)
    guard !replies.isEmpty else { throw URLError(.notConnectedToInternet) }
    return (Data(replies.removeFirst().utf8), ok200)
}

var a = QSO(call: "K1AAA", timeOn: at("20261116", "100000")); a["band"] = "20m"; a["mode"] = "CW"
var b = QSO(call: "K1BBB", timeOn: at("20261116", "100500")); b["band"] = "20m"; b["mode"] = "CW"
var c = QSO(call: "K1CCC", timeOn: at("20261116", "101000")); c["band"] = "20m"; c["mode"] = "CW"
for qso in [a, b, c] { try! logbook.add(qso) }
replies = ["RESULT=OK&LOGID=1&COUNT=1", "RESULT=FAIL&REASON=duplicate", "RESULT=FAIL&REASON=outside date range"]
// An edit made while the upload runs (the second answer) must survive.
let sendWithEdit = OneByOneUpload.send
OneByOneUpload.send = { request in
    if requests.count == 1 {
        await MainActor.run { var edited = logbook.contacts[0]; edited["name"] = "Edited"; _ = try! logbook.update(edited) }
    }
    return try await sendWithEdit(request)
}
var report = await QRZLogbookUpload.upload([a, b, c], logbook: logbook)
OneByOneUpload.send = sendWithEdit
@MainActor func now(_ call: String) -> QSO { logbook.contacts.first { $0.call == call }! }
check(requests.count == 3 && requests.allSatisfy { $0.httpMethod == "POST" && $0.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("SolidCopy/") == true },
      "one POST per contact, naming Solid Copy")
check(UploadService.qrzLogbook.isUploaded(now("K1AAA")) && UploadService.qrzLogbook.isUploaded(now("K1BBB"))
      && !UploadService.qrzLogbook.isUploaded(now("K1CCC")), "added and duplicate marked; refused not: \(report.text)")
check(now("K1AAA")["name"] == "Edited", "an edit made during the upload is kept")
check(now("K1AAA")["qrzcom_qso_upload_date"] == QSL.today(), "dated today")
check(!report.ok && report.text.contains("added 1 contact") && report.text.contains("1 was already there")
      && report.text.contains("1 wasn't taken, because its date is outside your QRZ logbook's date range")
      && report.text.hasSuffix(": K1CCC."), "the report: \(report.text)")
// QRZ's real answer for a contact before the logbook's start (16 November
// 2026), in plain words, with what to do.
check(answer("RESULT=FAIL&REASON=QRZ Internal Error: Unable to add QSO to database.&EXTENDED=add_qso: outside date range,")
      == .refused(QRZLogbook.plainReason("outside date range")), "QRZ's wrapped reason unwrapped")
check(QRZLogbook.plainReason("QRZ Internal Error: Unable to add QSO to database.&EXTENDED=freq_to_band: cannot determine band from , freq_to_band: cannot determine band from , qso_hash: required field missing band1, qso_hash: required field missing band1,")
      == "it has no band or frequency (add one in Edit Contact, then upload again)", "no band, in plain words")
check(QRZLogbook.plainReason("QRZ Internal Error: x.&EXTENDED=add_qso: bad mode, add_qso: bad mode, other: bad call,")
      == "bad mode; bad call", "an unknown reason: each part once, without QRZ's labels")
check(QRZLogbook.plainReason("QRZ Internal Error: Unable to add QSO to database.&EXTENDED=") == "Unable to add QSO to database",
      "an empty EXTENDED keeps the main reason, tidied")
// Refusals grouped by reason: one sentence each, five calls then a count.
let grouped = OneByOneUpload.refusals((1...7).map { ("K\($0)A", "reason one") } + [("W1X", "reason two")])
check(grouped == " 7 weren't taken, because reason one: K1A, K2A, K3A, K4A, K5A, and 2 more."
      + " 1 wasn't taken, because reason two: W1X.", "refusals grouped: \(grouped)")

// No internet: stops at once, worth trying again.
requests = []
report = await QRZLogbookUpload.upload([now("K1CCC")], logbook: logbook)
check(requests.count == 1 && report.tryAgain && report.text.contains("QRZ couldn't be reached"), "offline: stops, try again: \(report.text)")
// A key problem stops before the rest.
requests = []
replies = ["RESULT=AUTH", "RESULT=OK"]
report = await QRZLogbookUpload.upload([now("K1CCC"), now("K1AAA")], logbook: logbook)
check(requests.count == 1 && !report.tryAgain && report.text.contains("subscription"), "AUTH stops the rest: \(report.text)")
QRZLogbookUpload.key = { "" }
report = await QRZLogbookUpload.upload([now("K1CCC")], logbook: logbook)
check(report.text.contains("API key in Settings > Uploads"), "no key: says where to add it")
QRZLogbookUpload.key = { "TEST-KEY" }

// MARK: - QRZ Logbook confirmations

func fetched(_ text: String) -> QRZLogbookFetch.Answer { QRZLogbookFetch.answer(from: Data(text.utf8)) }
let twoRecords = "<call:5>K1AAA<band:3>20m<mode:2>CW<qso_date:8>20261116<time_on:4>1002<app_qrzlog_logid:3>101"
    + "<app_qrzlog_qsldate:8>20261117<app_qrzlog_status:1>C<eor>"
    + "<call:5>K1BBB<band:3>20m<mode:2>CW<qso_date:8>20261116<time_on:4>1005<app_qrzlog_logid:3>102<app_qrzlog_status:1>N<eor>"
if case .page(let page) = fetched("RESULT=OK&COUNT=2&LOGIDS=101,102&ADIF=" + twoRecords) {
    check(page.records == 2 && page.highestLogID == 102 && page.confirmations.map(\.call) == ["K1AAA"]
          && page.confirmations[0].confirmedOn == "20261117", "QRZ fetch: records read; one marked N isn't taken")
} else { check(false, "QRZ fetch: an OK answer is a page") }
let webText = twoRecords.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
if case .page(let page) = fetched("RESULT=OK&COUNT=2&ADIF=" + webText + "&LOGIDS=101,102") {
    check(page.records == 2 && page.confirmations.count == 1, "QRZ fetch: ADIF sent as web text (&lt;) read too")
} else { check(false, "QRZ fetch: web-text ADIF") }
let noStatus = "<call:5>K1AAA<band:3>20m<mode:2>CW<qso_date:8>20261116<time_on:4>1002<eor>"
if case .page(let page) = fetched("RESULT=OK&COUNT=1&ADIF=" + noStatus) {
    check(page.confirmations.count == 1 && page.confirmations[0].confirmedOn.isEmpty,
          "QRZ fetch: no status field: taken as confirmed (only confirmed were asked for), no date")
} else { check(false, "QRZ fetch: no status field") }
check(fetched("RESULT=FAIL&COUNT=0&REASON=no log entries found") == .page(.init(confirmations: [], records: 0, highestLogID: 0)),
      "QRZ fetch: nothing confirmed yet is an empty page, not a problem")
if case .problem(let why) = fetched("RESULT=AUTH"), why.contains("subscription") {} else { check(false, "QRZ fetch: AUTH is a problem") }
if case .problem = fetched("<html>error</html>") {} else { check(false, "QRZ fetch: a web page isn't taken for an answer") }
let fetchBody = String(decoding: QRZLogbookFetch.fetchBody(key: "AB-12", afterLogID: 251), as: UTF8.self)
check(fetchBody == "KEY=AB-12&ACTION=FETCH&OPTION=STATUS%3ACONFIRMED%2CMAX%3A250%2CAFTERLOGID%3A251",
      "QRZ fetch: confirmed only, 250 at a time, from a log ID: \(fetchBody)")

// Paging, matching and marking, with a pretend QRZ: a full page of 250
// (K1AAA among them), then the rest.
var page1 = ""
for n in 0..<249 {
    page1 += "<call:5>W9Z\(String(format: "%02d", n % 100))<band:3>40m<mode:2>CW<qso_date:8>20200101<time_on:4>1200<app_qrzlog_logid:\(String(n + 1).count)>\(n + 1)<eor>"
}
page1 += "<call:5>K1AAA<band:3>20m<mode:2>CW<qso_date:8>20261116<time_on:4>1002<app_qrzlog_logid:3>250<app_qrzlog_qsldate:8>20261117<eor>"
try! logbook.change([now("K1CCC").id]) { $0["qrzcom_qso_download_status"] = "Y"; $0["qrzcom_qso_download_date"] = "20261101" }
requests = []
replies = ["RESULT=OK&COUNT=250&ADIF=" + page1,
           "RESULT=OK&COUNT=1&ADIF=<call:5>K1CCC<band:3>20m<mode:2>CW<qso_date:8>20261116<time_on:4>1010<app_qrzlog_logid:3>300<eor>"]
let fetchSummary = await QRZLogbookSync.download(logbook) { _ in }
let secondBody = requests.count == 2 ? String(decoding: requests[1].httpBody ?? Data(), as: UTF8.self) : ""
check(requests.count == 2 && secondBody.contains("AFTERLOGID%3A251"), "QRZ fetch: a full page asks for the next, past its last log ID")
check(now("K1AAA")["qrzcom_qso_download_status"] == "Y" && now("K1AAA")["qrzcom_qso_download_date"] == "20261117"
      && UploadService.qrzLogbook.isUploaded(now("K1AAA")), "QRZ confirmations: matched by call, band and time, marked confirmed and uploaded")
check(now("K1CCC")["qrzcom_qso_download_date"] == "20261101", "QRZ confirmations: no date from QRZ keeps the date already there")
check(fetchSummary.contains("1 contact newly confirmed by QRZ Logbook") && fetchSummary.contains("249 matched nothing"),
      "QRZ confirmations summary: \(fetchSummary)")

// MARK: - Club Log

@MainActor func clubLog(_ status: Int, _ json: String) -> ContactAnswer { ClubLogUpload.answer(status: status, data: Data(json.utf8)) }
check(clubLog(201, #"{"status":"created","qsoid":123,"message":"QSO added"}"#) == .added, "Club Log: 201 created is added")
check(clubLog(200, #"{"status":"duplicate","qsoid":123}"#) == .alreadyThere, "Club Log: a duplicate is already there")
check(clubLog(200, #"{"status":"updated","qsoid":123}"#) == .added, "Club Log: updated is in the log")
check(clubLog(422, #"{"code":"bad_band","message":"Band is not valid"}"#) == .refused("Club Log said: Band is not valid"),
      "Club Log: 422 refused, with its reason")
if case .stop(let why, false) = clubLog(201, #"{"status":"created","qsoid":null}"#), why.contains("test-mode") {} else {
    check(false, "Club Log: a test-mode token stops, marks nothing")
}
if case .stop(_, false) = clubLog(401, #"{"message":"Token not accepted"}"#) {} else { check(false, "Club Log: 401 stops, not retried") }
if case .stop(_, false) = clubLog(403, "{}") {} else { check(false, "Club Log: 403 stops, not retried") }
if case .stop(_, true) = clubLog(429, "") {} else { check(false, "Club Log: 429 stops, tried later") }
if case .stop(_, true) = clubLog(503, "<html>") {} else { check(false, "Club Log: its own error, tried later") }
if case .stop = clubLog(200, "<html>not json</html>") {} else { check(false, "Club Log: a web page isn't taken for success") }

var mine = full; mine["station_callsign"] = ""
let clubRequest = try! ClubLogUpload.request(for: mine, token: "cl_TEST", myCall: "n0call")
let clubBody = try! JSONSerialization.jsonObject(with: clubRequest.httpBody!) as! [String: String]
check(clubRequest.url == ClubLogUpload.endpoint && clubRequest.httpMethod == "POST"
      && clubRequest.value(forHTTPHeaderField: "Authorization") == "Bearer cl_TEST"
      && clubBody["call"] == "N0CALL" && clubBody["adif"] == LogExport.adifRecord(mine),
      "Club Log: POST, the token as Bearer, your call (the profile's when the contact has none), one record")
do { _ = try ClubLogUpload.request(for: mine, token: "cl_TEST", myCall: ""); check(false, "no callsign: not sent") }
catch let notSent as NotSent { check(notSent.reason.contains("no station callsign"), "Club Log: no callsign at all: not sent, said why") }
catch { check(false, "no callsign: the wrong error") }

// MARK: - eQSL

let eqslAdded = """
<HTML><!-- Reply form eQSL.cc ADIF Real-time Interface --><BODY>
Information: Received 210 bytes<BR>Caution: ProgramID or Logger not found<BR>Result: 1 out of 1 records added<BR></BODY></HTML>
"""
check(EQSLUpload.answer(eqslAdded) == .added, "eQSL: 1 out of 1 added (a Caution doesn't matter)")
// A QTH Nickname that isn't one of the account's profiles names it, and says how to fix it.
if case .stop(let text, false) = EQSLUpload.answer("Error: No match on APP_EQSL_QTH_NICKNAME: Home") {
    check(text.contains("\"Home\"") && text.contains("clear QTH Nickname"), "eQSL: a QTH Nickname with no profile names it and says how to fix it")
} else { check(false, "eQSL: a QTH Nickname with no profile names it and says how to fix it") }
check(EQSLUpload.answer("Warning: Y=2025 M=12 D=17 Bad record: Duplicate<BR>Result: 0 out of 1 records added<BR>") == .alreadyThere,
      "eQSL: a duplicate is already there")
check(EQSLUpload.answer("Warning: Y=2025 M=12 D=17 Bad record: duplicate<BR>Result: 0 out of 1 records added") == .alreadyThere,
      "eQSL: duplicate in any case")
check(EQSLUpload.answer("Warning: Y=2025 M=12 D=17 Bad Mode: XYZ<BR>Result: 0 out of 1 records added")
      == .refused("eQSL doesn't take its mode, XYZ (change it in Edit Contact, then upload again)"), "eQSL: a bad mode, in plain words")
check(EQSLUpload.answer("Warning: Y=2025 M=12 D=17 Bad Band/Freq: <BR>Result: 0 out of 1 records added")
      == .refused("it has no band or frequency eQSL knows (add one in Edit Contact, then upload again)"), "eQSL: no band")
check(EQSLUpload.answer("Result: 0 out of 1 records added") == .refused("eQSL didn't add it, and gave no reason"),
      "eQSL: not added, no reason")
if case .stop(let why, false) = EQSLUpload.answer("Error: No match on eQSL_User/eQSL_Pswd<BR>"), why.contains("username and password") {} else {
    check(false, "eQSL: a wrong login stops, not retried")
}
if case .refused(let why) = EQSLUpload.answer("Error: No match on eQSL_User/eQSL_Pswd for date 19980101 12:00<BR>"),
   why.contains("doesn't cover its date") {} else { check(false, "eQSL: an account that doesn't cover the date refuses that one") }
if case .stop(let why, false) = EQSLUpload.answer("Error: Multiple accounts match eQSL_User/eQSL_Pswd for date 20251217 15:30"),
   why.contains("QTH Nickname") {} else { check(false, "eQSL: several accounts: says to set QTH Nickname") }
if case .stop(_, true) = EQSLUpload.answer("Error: The system is down until 0300Z") {} else { check(false, "eQSL down: tried later") }
if case .stop = EQSLUpload.answer("<html>Login page</html>") {} else { check(false, "eQSL: a web page isn't taken for success") }

let eqslFile = EQSLUpload.file(for: full, nickname: "Home")
check(eqslFile.contains("<EOH>") && eqslFile.contains("<APP_EQSL_QTH_NICKNAME:4>Home <EOR>")
      && !eqslFile.contains("NOTES"), "eQSL: a header, the record, its QTH Nickname, no Notes")
let eqslRequest = EQSLUpload.request(for: full, user: "N0CALL", password: "p&ss", nickname: "")
let eqslBody = String(decoding: eqslRequest.httpBody!, as: UTF8.self)
check(eqslRequest.url == EQSLUpload.endpoint && eqslRequest.httpMethod == "POST"
      && eqslRequest.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true
      && eqslBody.contains("name=\"EQSL_USER\"\r\n\r\nN0CALL\r\n") && eqslBody.contains("name=\"EQSL_PSWD\"\r\n\r\np&ss\r\n")
      && eqslBody.contains("name=\"Filename\"; filename=\"solidcopy.adi\"") && !eqslBody.contains("APP_EQSL_QTH_NICKNAME"),
      "eQSL: a file upload with the login and an .adi file")

// Both through the shared loop: marked in their own fields, a pause of
// none for the check.
ClubLogUpload.pauseNow = 0
EQSLUpload.pauseNow = 0
ClubLogUpload.token = { "cl_TEST" }
ClubLogUpload.myCall = { "N0CALL" }
EQSLUpload.login = { ("N0CALL", "secret", "") }
var statuses: [Int] = []
let realSend = OneByOneUpload.send
OneByOneUpload.send = { request in
    requests.append(request)
    let status = statuses.isEmpty ? 200 : statuses.removeFirst()
    return (Data(replies.removeFirst().utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
}
requests = []
statuses = [201, 422]
replies = [#"{"status":"created","qsoid":9}"#, #"{"message":"Band is not valid"}"#]
report = await ClubLogUpload.upload([now("K1AAA"), now("K1BBB")], logbook: logbook)
check(requests.count == 2 && UploadService.clubLog.isUploaded(now("K1AAA")) && !UploadService.clubLog.isUploaded(now("K1BBB"))
      && now("K1AAA")["clublog_qso_upload_date"] == QSL.today() && report.text.contains("Club Log: added 1 contact.")
      && report.text.contains("because Club Log said: Band is not valid: K1BBB."), "Club Log upload: \(report.text)")
requests = []
statuses = [403, 201]
replies = ["{}", "{}"]
report = await ClubLogUpload.upload([now("K1BBB"), now("K1CCC")], logbook: logbook)
check(requests.count == 1 && !report.tryAgain && report.text.contains("2 contacts not sent yet"), "Club Log: 403 stops the rest: \(report.text)")
// The refusal names the callsign sent (the pretend profile's here), and
// Club Log's words under "error" aren't lost.
check(report.text.contains("\(ClubLogUpload.myCall()) isn't on the account"), "Club Log: 403 names the callsign: \(report.text)")
if case .stop(let why, false) = ClubLogUpload.answer(status: 403, data: Data(#"{"error":"Callsign not owned"}"#.utf8), call: "N0CALL"),
   why.contains("N0CALL isn't on the account"), why.contains("Club Log said: Callsign not owned.") {} else {
    check(false, "Club Log: 403 with an error key")
}
requests = []
statuses = []
replies = [eqslAdded]
report = await EQSLUpload.upload([now("K1CCC")], logbook: logbook)
check(requests.count == 1 && now("K1CCC")["eqsl_qsl_sent"] == "Y" && now("K1CCC")["eqsl_qslsdate"] == QSL.today()
      && report.ok, "eQSL upload: \(report.text)")
check(UploadService.eqsl.toUpload(logbook.contacts, from: "").allSatisfy { $0.call != "K1CCC" }, "eQSL: a sent contact isn't sent again")
EQSLUpload.login = { ("N0CALL", "", "") }
report = await EQSLUpload.upload([now("K1AAA")], logbook: logbook)
check(report.text.contains("username and password in Settings > Uploads"), "eQSL: no login: says where")
ClubLogUpload.token = { "" }
report = await ClubLogUpload.upload([now("K1AAA")], logbook: logbook)
check(report.text.contains("token in Settings > Uploads"), "Club Log: no token: says where")
OneByOneUpload.send = realSend

// MARK: - Automatic uploads

UserDefaults.standard.removeObject(forKey: AutoUploader.savedKey)
let auto = AutoUploader.shared
auto.logbook = logbook
var told: [String] = []
var uploaded: [[String]] = []
var nextReport = UploadReport(text: "QRZ Logbook: sent.", ok: true)
auto.tell = { told.append($0) }
auto.uploaders = [.qrzLogbook: { contacts, _ in uploaded.append(contacts.map(\.call)); return nextReport },
                  .lotw: { _, _ in check(false, "LoTW isn't turned on"); return nextReport }]
auto.delay = { _ in 3600 }  // the checks run them by hand

check(AutoUpload.allCases.allSatisfy { Settings.autoUpload(.lotw) != $0 || $0 == .byHand }, "by hand unless chosen")
var d = QSO(call: "K1DDD", timeOn: at("20261116", "110000")); d["band"] = "40m"
try! logbook.add(d)
auto.logged(d.id)
check(auto.waitingCount(.qrzLogbook) == 0 && auto.waitingCount(.lotw) == 0, "by hand: nothing waits")

Settings.setAutoUpload(.soonAfterEach, for: .qrzLogbook)
var e = QSO(call: "K1EEE", timeOn: at("20261116", "110500")); e["band"] = "40m"
try! logbook.add(e)
auto.logged(d.id)
auto.logged(e.id)
check(auto.waitingCount(.qrzLogbook) == 2 && auto.waitingCount(.lotw) == 0, "only the service turned on waits")
await auto.run(.qrzLogbook)
check(uploaded == [["K1DDD", "K1EEE"]] && told.isEmpty, "a run goes together, silently when it works")

// Offline: kept, and said once however often it happens.
nextReport = UploadReport(text: "QRZ Logbook: couldn't reach QRZ.", ok: false, tryAgain: true)
auto.logged(d.id)
await auto.run(.qrzLogbook)
check(auto.waitingCount(.qrzLogbook) == 1 && told.count == 1 && told[0].hasPrefix("Automatic upload."),
      "offline: kept for later, and said: \(told)")
// Quitting while it waits loses nothing: the list is saved, and a new
// start (a fresh uploader, as at the next launch) picks it up.
let saved = UserDefaults.standard.dictionary(forKey: AutoUploader.savedKey) as? [String: [String]]
check(saved == ["qrzLogbook": [d.id.uuidString]], "what's waiting is saved: \(String(describing: saved))")
let relaunched = AutoUploader()
relaunched.resumeAfter = 3600
relaunched.logbook = logbook
check(relaunched.waitingCount(.qrzLogbook) == 1 && relaunched.waitingCount(.lotw) == 0,
      "after relaunching, the saved contact waits again")
await auto.run(.qrzLogbook)
check(told.count == 1, "the same problem isn't said again")
// Already uploaded (by hand, meanwhile) or deleted: not sent again.
try! logbook.change([d.id]) { $0["qrzcom_qso_upload_status"] = "Y" }
uploaded = []
await auto.run(.qrzLogbook)
check(uploaded.isEmpty && auto.waitingCount(.qrzLogbook) == 0, "a contact sent meanwhile isn't sent again")
check(UserDefaults.standard.object(forKey: AutoUploader.savedKey) == nil, "nothing waiting: nothing saved")
// Turned off before it ran: nothing goes.
auto.logged(e.id)
Settings.setAutoUpload(.byHand, for: .qrzLogbook)
try! logbook.change([e.id]) { $0["qrzcom_qso_upload_status"] = "" }
await auto.run(.qrzLogbook)
check(uploaded.isEmpty && auto.waitingCount(.qrzLogbook) == 0, "turned off meanwhile: nothing sent")

clearAutoUpload()
UserDefaults.standard.removeObject(forKey: AutoUploader.savedKey)
print("All upload checks passed.")
