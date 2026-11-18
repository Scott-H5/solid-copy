// tools/lookup-check/main.swift
//
// Checks the callsign lookup code without a QRZ account:
//   - reads sample QRZ replies (a paid-subscription lookup, a free-account
//     login, an expired session, "not found") and checks the fields;
//   - reads a sample callook.info reply;
//   - with --live, also asks callook.info about W1AW (the ARRL's station),
//     which needs the internet but no account.
//
// Run it with:  bash tools/check-lookups.sh [--live]

import Foundation

func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }

// A QRZ lookup reply, shaped like QRZ's documentation.
let qrzXML = """
<?xml version="1.0" encoding="utf-8" ?>
<QRZDatabase version="1.34" xmlns="http://xmldata.qrz.com">
  <Callsign>
    <call>W1AW</call><fname>Hiram Percy</fname><name>Maxim</name><nickname>Hi</nickname>
    <addr1>225 Main St</addr1><addr2>Newington</addr2><state>CT</state><zip>06111</zip>
    <country>United States</country><land>United States</land><dxcc>291</dxcc>
    <lat>41.714775</lat><lon>-72.727260</lon><grid>FN31pr</grid><county>Hartford</county>
    <cqzone>5</cqzone><ituzone>8</ituzone><email>w1aw@example.org</email><qslmgr>via bureau</qslmgr>
  </Callsign>
  <Session><Key>2331uf894c4bd29f3923f3bacf02c532d7bd9</Key><Count>123</Count>
    <SubExp>Wed Jan 1 12:34:03 2027</SubExp><GMTime>Sat Nov 14 20:00:00 2026</GMTime></Session>
</QRZDatabase>
"""
let reply = QRZReply.parse(Data(qrzXML.utf8))
check(reply.callsign["call"] == "W1AW" && reply.session["key"]?.hasPrefix("2331") == true, "QRZ reply: callsign and session read")
let result = QRZClient.result(from: reply.callsign, call: "W1AW")
check(result.fields["name"] == "Hiram Percy Maxim" && result.firstName == "Hi", "QRZ: full name, and nickname for speech")
check(result.fields["gridsquare"] == "FN31pr" && result.fields["dxcc"] == "291" && result.fields["cqz"] == "5"
      && result.fields["qth"] == "Newington" && result.fields["qsl_via"] == "via bureau", "QRZ: grid, DXCC, zone, city, QSL via mapped to ADIF")
check(result.fields["address"] == "225 Main St\nNewington, CT 06111\nUnited States", "QRZ: address built line by line")
check(result.place == "Newington, Connecticut", "state spoken in full: \(result.place)")
check(result.summary == "Hiram Percy Maxim, Newington, Connecticut. Grid FN31pr. From QRZ.", "summary line: \(result.summary)")

let freeLogin = QRZReply.parse(Data("<QRZDatabase><Session><Key>abc</Key><SubExp>non-subscriber</SubExp></Session></QRZDatabase>".utf8))
check(freeLogin.session["subexp"] == "non-subscriber", "QRZ free-account login reads")
let expired = QRZReply.parse(Data("<QRZDatabase><Session><Error>Session Timeout</Error></Session></QRZDatabase>".utf8))
check(QRZClient.sessionExpired(expired.session), "QRZ expired session is noticed")
let notFound = QRZReply.parse(Data("<QRZDatabase><Session><Key>abc</Key><Error>Not found: XX9XX</Error></Session></QRZDatabase>".utf8))
check(notFound.callsign.isEmpty && !QRZClient.sessionExpired(notFound.session), "QRZ 'not found' isn't mistaken for an expired session")
check(QRZClient.formEncode(["password": "a&b=c d+é", "username": "N0CALL"]) == "password=a%26b%3Dc%20d%2B%C3%A9&username=N0CALL",
      "QRZ request body escapes passwords safely")

let callookJSON = """
{"status":"VALID","type":"PERSON","current":{"callsign":"N0CALL","operClass":"EXTRA"},
 "name":"PUBLIC, JOHN Q","address":{"line1":"1 MAIN ST","line2":"ANYTOWN, PA 00000"},
 "location":{"latitude":"42.5","longitude":"-83.0","gridsquare":"EN82"}}
"""
let callook = CallookClient.result(from: Data(callookJSON.utf8), call: "N0CALL")
check(callook?.fields["name"] == "John Q Public" && callook?.firstName == "John", "callook: FCC name tidied")
check(callook?.fields["qth"] == "Anytown" && callook?.fields["state"] == "PA" && callook?.place == "Anytown, Pennsylvania",
      "callook: city and state from the address")
check(CallookClient.result(from: Data(#"{"status":"INVALID"}"#.utf8), call: "X") == nil, "callook: unknown call gives nothing")

check(CallsignLookup.lookupCall(for: "W1AW/P") == "W1AW" && CallsignLookup.lookupCall(for: "VE3/W1AW") == "W1AW"
      && CallsignLookup.lookupCall(for: "K1ABC") == "K1ABC", "calls with / are looked up by their main part")

if CommandLine.arguments.contains("--live") {
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            let live = try await CallookClient.lookup("W1AW")
            check(live?.fields["state"] == "CT", "live callook.info: W1AW is in \(live?.place ?? "?")")
        } catch {
            print("FAIL live callook.info:", error.localizedDescription)
            exit(1)
        }
        semaphore.signal()
    }
    semaphore.wait()
}
