// tools/lotw-check/main.swift
//
// Checks LoTW sync's rules (LoTW.swift), with no internet and no TQSL:
//   - which contacts are uploaded (not yet sent, from the chosen day);
//   - TQSL's command line, and its results read from its log, including
//     the certificate passphrase problem (from a real log, 16 Nov 2026);
//   - the report address (the password's "+" and "&" kept safe);
//   - reading LoTW's report, and its web page when the login is wrong;
//   - matching confirmations: call, band, 30 minutes, mode to choose.
//
// Run it with:  bash tools/check-lotw.sh

import AppKit

func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }
func at(_ adifDate: String, _ time: String) -> Date { QSO.date(adifDate: adifDate, adifTime: time)! }

// What's uploaded.
var old = QSO(call: "W1AW", timeOn: at("19990101", "120000"))
var sent = QSO(call: "K1ABC", timeOn: at("20260101", "120000")); sent["lotw_qsl_sent"] = "Y"
var confirmed = QSO(call: "K2ABC", timeOn: at("20260102", "120000")); confirmed["lotw_qsl_rcvd"] = "Y"
let new = QSO(call: "K3ABC", timeOn: at("20260103", "120000"))
let log = [old, sent, confirmed, new]
check(LoTW.toUpload(log, from: "").map(\.call) == ["W1AW", "K3ABC"], "uploaded: everything not sent or confirmed")
check(LoTW.toUpload(log, from: "2020-01-01").map(\.call) == ["K3ABC"], "from a day on")
let args = LoTW.tqslArguments(file: URL(fileURLWithPath: "/f/a.adi"), location: "Anytown, N0CALL",
                              log: URL(fileURLWithPath: "/f/log.txt"))
check(args == ["-x", "-d", "-u", "-a", "compliant", "-l", "Anytown, N0CALL", "-t", "/f/log.txt", "/f/a.adi"],
      "TQSL's command line")

// TQSL's results, from its log.
let passphrase = """
Mon Nov 16 05:46:19 2026 tqsl_unlock_key: PEM_read_bio_RSAPrivateKey err error:1C800064:Provider routines::bad decrypt
Mon Nov 16 05:48:20 2026 check_tqsl_error: msg=Operator aborted operation
Final Status: TQSLLib Error
"""
if case .failed(let why) = LoTW.uploadResult(fromLog: passphrase) {
    check(why.contains("passphrase"), "the certificate passphrase problem, in words: \(why)")
} else { check(false, "the passphrase problem is a failure") }
check(LoTW.uploadResult(fromLog: "x\nFinal Status: Success (0)\n") == .sent, "success")
check(LoTW.uploadResult(fromLog: "Final Status: No QSOs were processed since some QSOs were duplicates (8)") == .alreadySent,
      "nothing new: all on LoTW already")
check(LoTW.uploadResult(fromLog: "Final Status: Some QSOs were processed (9)") == .someAlreadySent, "some already there")
check(!LoTW.uploadResult(fromLog: "Final Status: LoTW Connection error (11)").uploaded
      && !LoTW.uploadResult(fromLog: "").uploaded, "a connection error, or no status: not uploaded")
// The first live sync (16 November 2026): no certificate yet. TQSL's
// real output; it must not count as "already uploaded".
let noCertificate = """
TQSL Version 2.8.7 [v2.8.7-1-g94933a5c]
There are no valid callsign certificates for callsign N0CALL in entity UNITED STATES OF AMERICA.
Signing aborted.
No QSOs to upload
Final Status: No QSOs to upload(8)
"""
if case .failed(let why) = LoTW.uploadResult(fromLog: noCertificate) {
    check(why.contains("no usable callsign certificate"), "no certificate: a failure, in words: \(why)")
} else { check(false, "no certificate must not count as uploaded") }
check(!LoTW.uploadResult(fromLog: "Final Status: No QSOs to upload(8)").uploaded,
      "code 8 without duplicates: nothing was sent")
// Skipped contacts (the author's first real sync: a swapped grid).
let mismatch = """
Signing using Callsign N0CALL, DXCC Entity UNITED STATES OF AMERICA

Station Location does not match QSO details
The Station Location 'Gridsquare' has value 'FM19JK' while QSO has 'FM19KJ' on line 4
CALL: KB3CFK
QSO_DATE: 19980322
TIME_ON: 202500
BAND: 40m

Station Location does not match QSO details
The Station Location 'Gridsquare' has value 'FM19JK' while QSO has 'FM19KJ' on line 49
CALL: AF4CM
QSO_DATE: 19980407
TIME_ON: 2002

No QSOs to upload
Final Status: No QSOs to upload(8)
"""
let skips = LoTW.skipped(in: mismatch)
check(skips.keys == ["KB3CFK 19980322 202500", "AF4CM 19980407 200200"] && skips.reason.contains("'FM19JK' while QSO has 'FM19KJ'")
      && !skips.reason.contains("on line"),
      "skipped contacts and TQSL's reason read from its output")
check(LoTW.Skipped.key(for: QSO(call: "kb3cfk", timeOn: at("19980322", "202500"))) == "KB3CFK 19980322 202500",
      "a contact's key matches TQSL's")
if case .failed(let why) = LoTW.uploadResult(fromLog: mismatch) {
    check(why.contains("2 contacts couldn't be signed: KB3CFK on 22 March 1998; AF4CM on 7 April 1998.")
          && why.contains("FM19JK"), "nothing signed, which ones, and why: \(why)")
} else { check(false, "skipped everything must not count as uploaded") }
// The author's first real upload: repeats in the author's own log, and one without a band.
let real = """
Signing using Callsign N0CALL, DXCC Entity UNITED STATES OF AMERICA
Previously Signed QSO detected on line 1044
CALL: VE3OXQ
QSO_DATE: 19990222
TIME_ON: 233000
Previously Signed QSO detected on line 1047
CALL: VE3OXQ
QSO_DATE: 19990222
TIME_ON: 233000
Invalid contact - QSO does not specify a band or frequency on line 2081
CALL: VE6BBP
QSO_DATE: 20251213
TIME_ON: 152627
Attempting to upload 149 QSOs
~/.tqsl/Solid Copy to LoTW.tq8: Log uploaded successfully with result:
File queued for processing
Final Status: Success(0)
"""
let realSkips = LoTW.skipped(in: real)
check(realSkips.keys == ["VE6BBP 20251213 152627"] && realSkips.reason == "Invalid contact - QSO does not specify a band or frequency",
      "a repeat already signed isn't skipped; the one without a band is, with TQSL's reason: \(realSkips.reason)")
check(LoTW.uploadResult(fromLog: real) == .sent, "that upload succeeded")
check(realSkips.named == ["VE6BBP on 13 December 2025"], "the skipped contact is named, since TQSL's reason doesn't")
var many = LoTW.Skipped()
many.named = (1...7).map { "K\($0)A on 1 May 2020" }
check(many.list == "K1A on 1 May 2020; K2A on 1 May 2020; K3A on 1 May 2020; K4A on 1 May 2020; K5A on 1 May 2020; and 2 more",
      "a long list: five, then how many more")
check(LoTW.uploadResult(fromLog: "Previously Signed QSO detected on line 4\nCALL: W1AW\nQSO_DATE: 20260101\nTIME_ON: 1200\n"
                        + "Final Status: No QSOs to upload(8)") == .alreadySent,
      "only repeats left: all on LoTW already")
check(LoTW.uploadResult(fromLog: "Previously Signed QSO detected on line 4\nCALL: W1AW\nQSO_DATE: 20260101\nTIME_ON: 1200\n"
                        + "Invalid contact - QSO does not specify a band or frequency on line 9\nCALL: VE6BBP\n"
                        + "QSO_DATE: 20251213\nTIME_ON: 152627\nFinal Status: No QSOs to upload(8)") == .alreadySent,
      "repeats and one invalid: the repeats count as on LoTW (the invalid one is left out by the skip list)")
check(LoTW.UploadResult.someAlreadySent.uploaded && !LoTW.UploadResult.failed("x").uploaded, "what counts as uploaded")

// The report address.
let url = LoTW.reportRequest(username: "n0call", password: "a+b&c d", since: "")!.absoluteString
check(url.hasPrefix("https://lotw.arrl.org/lotwuser/lotwreport.adi?login=n0call&password=a%2Bb%26c%20d&qso_query=1")
      && url.contains("qso_qslsince=1900-01-01"), "the password is kept whole; first time from the beginning")

// LoTW's report.
let report = """
ARRL Logbook of the World Status Report
<PROGRAMID:4>LoTW
<APP_LoTW_LASTQSL:19>2026-11-10 14:02:33
<eoh>
<CALL:6>vp8xyz <BAND:3>20M <MODE:2>CW <APP_LoTW_MODEGROUP:2>CW <QSO_DATE:8>20261101 <TIME_ON:6>141500
<QSL_RCVD:1>Y <QSLRDATE:8>20261110 <eor>
<CALL:4>W1AW <BAND:3>40M <MODE:3>SSB <APP_LoTW_MODEGROUP:5>PHONE <QSO_DATE:8>20261101 <TIME_ON:4>0100
<QSL_RCVD:1>Y <QSLRDATE:8>20261105 <eor>
<CALL:5>K9XYZ <BAND:3>20M <MODE:3>FT8 <QSO_DATE:8>20261101 <TIME_ON:4>0300 <QSL_RCVD:1>N <eor>
<CALL:5>K8ZZZ <BAND:3>20M <MODE:2>CW <QSO_DATE:8>20261101 <TIME_ON:4>0300 <QSL_RCVD:1>Y <QSLRDATE:8>20261105 <eor>
<APP_LoTW_EOF>
"""
let parsed = try! LoTW.report(from: Data(report.utf8))
check(parsed.lastQSL == "2026-11-10 14:02:33" && parsed.confirmations.count == 3,
      "a report: its last-QSL time, and only confirmed records (\(parsed.confirmations.count))")
check(parsed.confirmations[0].call == "VP8XYZ" && parsed.confirmations[0].band == "20m", "calls and bands as in the log")
do {
    _ = try LoTW.report(from: Data("<html><body><h1>Username/password incorrect</h1></body></html>".utf8))
    check(false, "a web page isn't a report")
} catch {
    check("\(error.localizedDescription)".contains("Username/password incorrect"), "a wrong login: LoTW's words: \(error.localizedDescription)")
}

// Matching.
var vp8 = QSO(call: "VP8XYZ", timeOn: at("20261101", "143000")); vp8["band"] = "20m"; vp8["mode"] = "CW"
var vp8later = QSO(call: "VP8XYZ", timeOn: at("20261101", "150500")); vp8later["band"] = "20m"; vp8later["mode"] = "CW"
var w1awCW = QSO(call: "W1AW", timeOn: at("20261101", "010500")); w1awCW["band"] = "40m"; w1awCW["mode"] = "CW"
var w1awSSB = QSO(call: "W1AW", timeOn: at("20261101", "011500")); w1awSSB["band"] = "40m"; w1awSSB["mode"] = "SSB"
let (changed, unmatched) = LoTW.apply(parsed.confirmations, to: [vp8, vp8later, w1awCW, w1awSSB])
check(changed.count == 2 && changed.contains { $0.id == vp8.id } && !changed.contains { $0.id == vp8later.id },
      "15 minutes apart matches; 50 minutes doesn't")
check(changed.contains { $0.id == w1awSSB.id } && !changed.contains { $0.id == w1awCW.id },
      "between two, the same kind of mode wins over the nearer time")
let done = changed.first { $0.id == vp8.id }!
check(done["lotw_qsl_rcvd"] == "Y" && done["lotw_qslrdate"] == "20261110" && done["lotw_qsl_sent"] == "Y",
      "confirmed, dated, and counted as uploaded")
check(unmatched.map(\.call) == ["K8ZZZ"], "a confirmation for a contact not in the log is reported")
check(LoTW.apply(parsed.confirmations, to: changed + [vp8later, w1awCW]).changed.isEmpty, "confirming again changes nothing")

// Details: where the confirming station was (qso_qsldetail), v1.5.
check(url.contains("qso_qsldetail=yes"), "the report asks for each confirmation's details")
let detailed = """
<APP_LoTW_LASTQSL:19>2026-11-21 10:00:00
<eoh>
<CALL:5>K3ABC <BAND:3>20M <MODE:2>CW <QSO_DATE:8>20261101 <TIME_ON:6>120000 <QSL_RCVD:1>Y <QSLRDATE:8>20261120
<DXCC:3>291 <COUNTRY:24>UNITED STATES OF AMERICA <PFX:2>K3 <CQZ:2>05 <ITUZ:1>8 <STATE:2>pa <CNTY:13>PA,Montgomery
<GRIDSQUARE:4>FN20 <eor>
<CALL:5>K4BAD <BAND:3>20M <MODE:2>CW <QSO_DATE:8>20261101 <TIME_ON:6>120000 <QSL_RCVD:1>Y <QSLRDATE:8>20261120
<CQZ:3>abc <STATE:7>P<A>;x <PFX:20>K4AAAAAAAAAAAAAAAAAA <eor>
"""
let detailReport = try! LoTW.report(from: Data(detailed.utf8))
let k3 = detailReport.confirmations[0].details
check(k3 == ["dxcc": "291", "pfx": "K3", "cqz": "5", "ituz": "8", "state": "PA", "cnty": "PA,Montgomery"],
      "details read and tidied: zone 05 is 5, state upper case, no country name or grid: \(k3)")
check(detailReport.confirmations[1].details.isEmpty,
      "odd or overlong details are ignored: \(detailReport.confirmations[1].details)")

var k3abc = QSO(call: "K3ABC", timeOn: at("20261101", "120500")); k3abc["band"] = "20m"; k3abc["mode"] = "CW"
k3abc["state"] = "NJ"; k3abc["cqz"] = "5"; k3abc["gridsquare"] = "FN20ab"; k3abc["country"] = "United States"
let first = LoTW.apply(detailReport.confirmations, to: [k3abc]).changed
check(first.count == 1 && first[0]["state"] == "PA" && first[0]["pfx"] == "K3" && first[0]["cnty"] == "PA,Montgomery"
      && first[0]["dxcc"] == "291", "LoTW's details replace a lookup's guess")
check(first[0]["gridsquare"] == "FN20ab" && first[0]["country"] == "United States",
      "the grid and the country's name are left alone")
check(LoTW.apply(detailReport.confirmations, to: first).changed.isEmpty, "the same details again change nothing")

// Already confirmed, before details were asked for: the details still come.
var earlier = k3abc; earlier["lotw_qsl_rcvd"] = "Y"; earlier["lotw_qslrdate"] = "20261120"; earlier["lotw_qsl_sent"] = "Y"
let refetched = LoTW.apply(detailReport.confirmations, to: [earlier]).changed
check(refetched.count == 1 && refetched[0]["state"] == "PA", "an old confirmation fetched again gets its details")
print("All LoTW checks passed.")
