// CallookClient.swift
//
// Looks up US callsigns with callook.info: a free service with no account,
// built from the FCC's licence database. It knows US calls only, and has
// name, mailing address, grid and location, but not things like email.
//
// A lookup is one request: https://callook.info/W1AW/json, which answers
// with JSON such as:
//   {"status": "VALID", "name": "JOHN Q PUBLIC",
//    "address": {"line1": "225 MAIN ST", "line2": "NEWINGTON, CT 06111"},
//    "location": {"latitude": "41.71", "longitude": "-72.72", "gridsquare": "FN31pr"}}
// "status" is "INVALID" for calls it doesn't know.

import Foundation

enum CallookClient {

    // Looks up a call, or returns nil if callook.info doesn't know it.
    static func lookup(_ call: String) async throws -> LookupResult? {
        guard let path = call.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: "https://callook.info/\(path)/json") else { return nil }
        let data: Data
        do {
            (data, _) = try await LookupNetwork.session.data(for: URLRequest(url: url, timeoutInterval: 10))
        } catch {
            throw LookupError(message: "Couldn't reach callook.info: \(error.localizedDescription)")
        }
        guard data.count <= LookupNetwork.maximumReplyBytes else { return nil }
        return result(from: data, call: call)
    }

    // Turns callook.info's JSON into a lookup result, or nil for "INVALID".
    static func result(from data: Data, call: String) -> LookupResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["status"] as? String)?.uppercased() == "VALID" else { return nil }
        let address = json["address"] as? [String: Any] ?? [:]
        let location = json["location"] as? [String: Any] ?? [:]
        func text(_ dictionary: [String: Any], _ key: String) -> String {
            LookupNetwork.trimmed(dictionary[key] as? String ?? "")
        }

        var fields: [String: String] = [:]
        func set(_ adif: String, _ value: String) { if !value.isEmpty { fields[adif] = value } }

        let name = tidyName(text(json, "name"))
        set("name", name)
        // line2 is "CITY, ST 12345".
        let line2 = text(address, "line2")
        let parts = line2.components(separatedBy: ",")
        if parts.count == 2 {
            set("qth", parts[0].capitalized)
            let stateZip = parts[1].trimmingCharacters(in: .whitespaces).split(separator: " ")
            if let state = stateZip.first { set("state", String(state)) }
        }
        set("gridsquare", text(location, "gridsquare"))
        set("lat", text(location, "latitude"))
        set("lon", text(location, "longitude"))
        set("address", [text(address, "line1").capitalized, line2].filter { !$0.isEmpty }.joined(separator: "\n"))

        let firstName = name.split(separator: " ").first.map(String.init) ?? ""
        return LookupResult(call: call, source: "callook.info", fields: fields,
                            firstName: (json["type"] as? String)?.uppercased() == "CLUB" ? "" : firstName,
                            fetched: Date())
    }

    // The FCC writes names in capitals, sometimes as "LAST, FIRST". This
    // makes them "First Last".
    static func tidyName(_ name: String) -> String {
        var name = name
        let parts = name.components(separatedBy: ",")
        if parts.count == 2 {
            name = parts[1].trimmingCharacters(in: .whitespaces) + " " + parts[0].trimmingCharacters(in: .whitespaces)
        }
        return name.capitalized
    }
}
