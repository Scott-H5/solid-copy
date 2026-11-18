// QRZClient.swift
//
// Looks up callsigns with QRZ.com's XML data service.
//
// How the service works (https://www.qrz.com/docs/xml/current_spec.html):
//   1. Log in with your QRZ username and password. QRZ answers with a
//      session key, and says whether your account has an XML subscription.
//   2. Ask for a callsign, sending the session key instead of the password.
//   3. Session keys expire. When QRZ says so, log in again and retry.
//
// Free and paid accounts: any QRZ account can use the service, but without
// an XML subscription QRZ returns only a few fields (mostly the name).
// Paid subscriptions return everything: address, grid, zones, and more.
// Solid Copy uses whatever comes back, and doesn't treat missing fields
// as errors.
//
// Privacy: requests are sent with POST over HTTPS, so your password and
// session key travel inside the encrypted request body, not in the web
// address. The program identifies itself as "SolidCopy" plus its version,
// as QRZ asks, and sends nothing about you beyond your login.

import Foundation

@MainActor
final class QRZClient {
    static let endpoint = URL(string: "https://xmldata.qrz.com/xml/current/")!

    static var agent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "SolidCopy-\(version)"
    }

    struct LoginInfo {
        // True with an XML subscription (all fields); false for a free
        // account (a few fields).
        let hasSubscription: Bool
        // QRZ's own words about the subscription, such as an expiry date
        // or "non-subscriber".
        let subscription: String
    }

    private var sessionKey: String?

    // Logs in, and keeps the session key for lookups.
    @discardableResult
    func login(username: String, password: String) async throws -> LoginInfo {
        sessionKey = nil
        guard !username.isEmpty, !password.isEmpty else {
            throw LookupError(message: "Add your QRZ username and password in Settings.")
        }
        let reply = try await post(["username": username, "password": password, "agent": Self.agent])
        if let error = reply.session["error"], !error.isEmpty {
            throw LookupError(message: "QRZ: \(error)")
        }
        guard let key = reply.session["key"], !key.isEmpty else {
            throw LookupError(message: "QRZ didn't send a session key.")
        }
        sessionKey = key
        let subscription = reply.session["subexp"] ?? ""
        let free = subscription.isEmpty || subscription.lowercased().contains("non-subscriber")
        return LoginInfo(hasSubscription: !free, subscription: subscription)
    }

    // Looks up a call. Returns QRZ's fields (lower-case names, as QRZ spells
    // them), or nil if QRZ doesn't know the call.
    func lookup(_ call: String, username: String, password: String) async throws -> [String: String]? {
        if sessionKey == nil {
            try await login(username: username, password: password)
        }
        var reply = try await post(["s": sessionKey ?? "", "callsign": call, "agent": Self.agent])
        if Self.sessionExpired(reply.session) {
            try await login(username: username, password: password)
            reply = try await post(["s": sessionKey ?? "", "callsign": call, "agent": Self.agent])
        }
        if !reply.callsign.isEmpty {
            return reply.callsign
        }
        if let error = reply.session["error"], !error.isEmpty {
            if error.lowercased().hasPrefix("not found") { return nil }
            throw LookupError(message: "QRZ: \(error)")
        }
        return nil
    }

    // QRZ says a session has ended by leaving out the key, or with an
    // error mentioning the session.
    nonisolated static func sessionExpired(_ session: [String: String]) -> Bool {
        let error = (session["error"] ?? "").lowercased()
        return session["key"] == nil || error.contains("session")
    }

    // Turns QRZ's fields into a lookup result with ADIF field names.
    nonisolated static func result(from qrz: [String: String], call: String) -> LookupResult {
        func value(_ name: String) -> String { LookupNetwork.trimmed(qrz[name] ?? "") }
        var fields: [String: String] = [:]
        func set(_ adif: String, _ text: String) { if !text.isEmpty { fields[adif] = text } }

        let first = value("fname")
        set("name", [first, value("name")].filter { !$0.isEmpty }.joined(separator: " "))
        set("qth", value("addr2"))
        set("state", value("state"))
        set("cnty", value("county"))
        // "land" is the DXCC entity (what ADIF COUNTRY means); "country" is
        // the mailing country. They're usually the same.
        set("country", value("land").isEmpty ? value("country") : value("land"))
        set("dxcc", value("dxcc").isEmpty ? value("ccode") : value("dxcc"))
        set("gridsquare", value("grid"))
        set("lat", value("lat"))
        set("lon", value("lon"))
        set("cqz", value("cqzone"))
        set("ituz", value("ituzone"))
        set("iota", value("iota"))
        set("email", value("email"))
        set("web", value("url"))
        set("qsl_via", value("qslmgr"))
        let cityLine = [[value("addr2"), value("state")].filter { !$0.isEmpty }.joined(separator: ", "),
                        value("zip")].filter { !$0.isEmpty }.joined(separator: " ")
        set("address", [value("addr1"), cityLine, value("country")].filter { !$0.isEmpty }.joined(separator: "\n"))

        let nickname = value("nickname")
        let firstName = nickname.isEmpty ? (first.split(separator: " ").first.map(String.init) ?? "") : nickname
        return LookupResult(call: call, source: "QRZ", fields: fields, firstName: firstName, fetched: Date())
    }

    // MARK: - Talking to QRZ

    private func post(_ parameters: [String: String]) async throws
        -> (callsign: [String: String], session: [String: String]) {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncode(parameters).utf8)
        let data: Data
        do {
            (data, _) = try await LookupNetwork.session.data(for: request)
        } catch {
            throw LookupError(message: "Couldn't reach QRZ: \(error.localizedDescription)")
        }
        guard data.count <= LookupNetwork.maximumReplyBytes else {
            throw LookupError(message: "QRZ sent an unexpectedly large reply.")
        }
        return QRZReply.parse(data)
    }

    // "a=1&b=2", with everything but letters, digits and -._~ escaped.
    nonisolated static func formEncode(_ parameters: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters.sorted { $0.key < $1.key }.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&")
    }
}

// Reads QRZ's XML reply, which looks like:
//   <QRZDatabase>
//     <Callsign><call>W1AW</call><fname>Hiram</fname>...</Callsign>
//     <Session><Key>abc123</Key><SubExp>...</SubExp><Error>...</Error></Session>
//   </QRZDatabase>
// and returns the fields inside <Callsign> and <Session>, with lower-case
// names.
final class QRZReply: NSObject, XMLParserDelegate {
    private var callsign: [String: String] = [:]
    private var session: [String: String] = [:]
    private var section: String?
    private var text = ""

    static func parse(_ data: Data) -> (callsign: [String: String], session: [String: String]) {
        let reader = QRZReply()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        return (reader.callsign, reader.session)
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "Callsign" || name == "Session" { section = name }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        if name == section {
            section = nil
        } else if section == "Callsign" {
            callsign[name.lowercased()] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if section == "Session" {
            session[name.lowercased()] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        text = ""
    }
}
