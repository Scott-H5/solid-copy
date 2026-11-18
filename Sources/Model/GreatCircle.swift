// GreatCircle.swift
//
// Distance and bearing from your station to theirs: how far, and which
// way to point a beam. Said with the lookup ("1,240 miles north-west"),
// shown on the lookup line with the bearing in degrees, and logged in
// ADIF's DISTANCE (kilometres) for each contact.
//
// Where each station is:
//   - you: the grid square in the profile in use (MY_GRIDSQUARE);
//   - them: their latitude and longitude from the lookup if it has them
//     (QRZ gives the address's position, closer than a grid), otherwise
//     their grid square.
// A grid square stands for its centre: "FN31" is a box about 100 by 200
// miles, so a 4-character grid is good to a few dozen miles, "FN31pr" to
// a few.
//
// The sums are the usual ones for a sphere (haversine for distance, and
// the initial great-circle bearing), with Earth's mean radius, 6,371 km.
// Good to well under one percent, plenty for pointing an antenna.
//
// Miles or kilometres follows the Mac's region setting (System Settings >
// General > Language & Region > Measurement system).

import Foundation

enum GreatCircle {
    struct Position: Equatable {
        var latitude: Double   // degrees, north positive
        var longitude: Double  // degrees, east positive
    }

    // The centre of a Maidenhead grid square of 2, 4, 6 or 8 characters
    // ("FN", "FN31", "FN31pr", "FN31pr45"), or nil if it isn't one.
    static func position(grid: String) -> Position? {
        let text = Array(grid.trimmingCharacters(in: .whitespaces).uppercased())
        guard [2, 4, 6, 8].contains(text.count) else { return nil }
        // Each pair narrows the box: letters A-R (field, 20 x 10 degrees),
        // digits 0-9 (square, 2 x 1), letters A-X (subsquare, 5 x 2.5
        // minutes), digits 0-9 (extended, 30 x 15 seconds).
        let sizes: [(lon: Double, lat: Double, base: Character, count: Int)] = [
            (20, 10, "A", 18), (2, 1, "0", 10), (2.0 / 24, 1.0 / 24, "A", 24), (2.0 / 240, 1.0 / 240, "0", 10),
        ]
        var longitude = -180.0, latitude = -90.0
        var size = (lon: 360.0, lat: 180.0)
        for pair in 0..<(text.count / 2) {
            let step = sizes[pair]
            guard let lonChar = text[pair * 2].asciiValue, let latChar = text[pair * 2 + 1].asciiValue,
                  let base = step.base.asciiValue else { return nil }
            let lonIndex = Int(lonChar) - Int(base), latIndex = Int(latChar) - Int(base)
            guard (0..<step.count).contains(lonIndex), (0..<step.count).contains(latIndex) else { return nil }
            longitude += Double(lonIndex) * step.lon
            latitude += Double(latIndex) * step.lat
            size = (step.lon, step.lat)
        }
        return Position(latitude: latitude + size.lat / 2, longitude: longitude + size.lon / 2)
    }

    // A position from decimal latitude and longitude text, or nil.
    static func position(latitude: String, longitude: String) -> Position? {
        guard let lat = Double(latitude.trimmingCharacters(in: .whitespaces)),
              let lon = Double(longitude.trimmingCharacters(in: .whitespaces)),
              (-90...90).contains(lat), (-180...180).contains(lon), lat != 0 || lon != 0 else { return nil }
        return Position(latitude: lat, longitude: lon)
    }

    static let earthRadiusKm = 6371.0

    // Kilometres along the Earth, and the bearing to set off on (degrees
    // from true north, 0 to 359).
    static func path(from a: Position, to b: Position) -> (km: Double, bearing: Double) {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1, dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let km = 2 * earthRadiusKm * asin(min(1, sqrt(h)))
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        return (km, bearing)
    }

    // The path for a contact: from its MY_GRIDSQUARE to their position
    // (LAT and LON, else GRIDSQUARE), or nil if either end isn't known.
    static func path(for qso: QSO) -> (km: Double, bearing: Double)? {
        path(myGrid: qso["my_gridsquare"], fields: ["lat": qso["lat"], "lon": qso["lon"], "gridsquare": qso["gridsquare"]])
    }

    // The same from your grid and their fields by ADIF name (a lookup's).
    static func path(myGrid: String, fields: [String: String]) -> (km: Double, bearing: Double)? {
        guard let mine = position(grid: myGrid),
              let theirs = position(latitude: fields["lat"] ?? "", longitude: fields["lon"] ?? "")
                ?? position(grid: fields["gridsquare"] ?? "") else { return nil }
        return path(from: mine, to: theirs)
    }

    // "north-west" for a bearing: eight points, each 45 degrees wide.
    static func compass(_ bearing: Double) -> String {
        let names = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
        return names[Int((bearing / 45).rounded()) % 8]
    }

    // Miles unless the Mac is set to metric.
    static var usesMiles: Bool { Locale.current.measurementSystem != .metric }

    // "1,240 miles north-west", for speech. Under 1 mile or km: "nearby".
    static func spoken(km: Double, bearing: Double, miles: Bool = usesMiles) -> String {
        let amount = (miles ? km / 1.609344 : km).rounded()
        guard amount >= 1 else { return "nearby" }
        let unit = miles ? (amount == 1 ? "mile" : "miles") : (amount == 1 ? "kilometre" : "kilometres")
        return "\(Int(amount).formatted()) \(unit) \(compass(bearing))"
    }

    // "1,240 miles, 312 degrees north-west", for the lookup line.
    static func shown(km: Double, bearing: Double, miles: Bool = usesMiles) -> String {
        let words = spoken(km: km, bearing: bearing, miles: miles)
        guard words != "nearby" else { return words }
        return words.replacingOccurrences(of: " \(compass(bearing))", with: ", \(Int(bearing.rounded()) % 360) degrees \(compass(bearing))")
    }
}
