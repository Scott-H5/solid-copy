// LookupResult.swift
//
// What a callsign lookup found, in Solid Copy's own terms: ADIF field
// names and values, whichever service it came from.

import Foundation

struct LookupError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// Shared by the lookup services.
enum LookupNetwork {
    // A private network session: nothing is kept on disk (no cache, no
    // cookies), and requests give up after 10 seconds. QRZ replies carry
    // your session key, so they shouldn't be cached.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    // Replies bigger than this are refused. A real lookup is a few
    // kilobytes; anything larger is a mistake or mischief.
    static let maximumReplyBytes = 256 * 1024

    // Each value kept from a reply is cut to this length, so an odd reply
    // can't fill the log with junk.
    static let maximumFieldLength = 500

    static func trimmed(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumFieldLength))
    }
}

struct LookupResult: Codable, Equatable {
    // Every field a lookup can fill (QRZClient and CallookClient). When a
    // logged contact's call is corrected, these are cleared, so the old
    // station's name and place don't stay on it; the new call's lookup
    // fills them again. Add to this when a client fills a new field.
    static let filledFields: Set<String> = [
        "name", "qth", "address", "state", "cnty", "country", "dxcc", "cqz", "ituz",
        "gridsquare", "lat", "lon", "iota", "email", "web", "qsl_via",
        // Worked out from the lookup's position (GreatCircle.swift).
        "distance",
    ]

    // The call that was looked up.
    var call: String
    // Where it came from: "QRZ" or "callook.info".
    var source: String
    // What was found, by lower-case ADIF name: name, qth, state, country,
    // gridsquare, and so on. Only fields with something in them.
    var fields: [String: String]
    // The first name (or nickname), for the spoken summary.
    var firstName: String
    // When it was looked up, so old cached results can be refreshed.
    var fetched: Date

    // Where they are, in words: "Newington, Connecticut" for the US and
    // Canada, otherwise "Lyon, France". Used on screen and in speech.
    var place: String {
        let city = fields["qth"] ?? ""
        let state = fields["state"] ?? ""
        let country = fields["country"] ?? ""
        let region: String
        if !state.isEmpty, ["United States", "Canada", "USA", ""].contains(country) {
            region = USStates.name(for: state) ?? state
        } else {
            region = country
        }
        return [city, region].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    // One line for the screen: "Hiram Percy Maxim, Newington, Connecticut.
    // Grid FN31pr. From QRZ."
    var summary: String {
        var parts: [String] = []
        let who = [fields["name"] ?? "", place].filter { !$0.isEmpty }.joined(separator: ", ")
        if !who.isEmpty { parts.append(who + ".") }
        if let grid = fields["gridsquare"], !grid.isEmpty { parts.append("Grid \(grid).") }
        parts.append("From \(source).")
        return parts.joined(separator: " ")
    }
}

// Two-letter US state and Canadian province codes, as full names, so
// VoiceOver says "Connecticut" rather than "C T".
enum USStates {
    static func name(for code: String) -> String? {
        names[code.uppercased()]
    }

    private static let names: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California",
        "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware", "DC": "District of Columbia",
        "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois",
        "IN": "Indiana", "IA": "Iowa", "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana",
        "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota",
        "MS": "Mississippi", "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada",
        "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York",
        "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma", "OR": "Oregon",
        "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota",
        "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia",
        "WA": "Washington", "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming",
        "PR": "Puerto Rico", "VI": "US Virgin Islands", "GU": "Guam", "AS": "American Samoa",
        // Canada
        "AB": "Alberta", "BC": "British Columbia", "MB": "Manitoba", "NB": "New Brunswick",
        "NL": "Newfoundland and Labrador", "NS": "Nova Scotia", "NT": "Northwest Territories",
        "NU": "Nunavut", "ON": "Ontario", "PE": "Prince Edward Island", "QC": "Quebec",
        "SK": "Saskatchewan", "YT": "Yukon",
    ]
}
