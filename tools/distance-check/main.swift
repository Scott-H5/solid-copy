// tools/distance-check/main.swift
//
// Checks distance and bearing (GreatCircle.swift) against known places:
//   - grid squares to positions (centres), and bad grids refused;
//   - New York to London, a well-known path (about 5,570 km, setting off
//     at about 51 degrees);
//   - an example grid (EM10, central Texas) to W1AW (FN31pr, Newington);
//   - the words said and shown, in miles and kilometres;
//   - a contact's distance from its own fields, preferring lat/lon.
//
// Run it with:  bash tools/check-distance.sh

import Foundation

func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }
func near(_ a: Double, _ b: Double, _ within: Double) -> Bool { abs(a - b) <= within }

// Grids
let fn31pr = GreatCircle.position(grid: "fn31pr")!
check(near(fn31pr.latitude, 41.7292, 0.001) && near(fn31pr.longitude, -72.7083, 0.001),
      "FN31pr is Newington, Connecticut: \(fn31pr)")
let jo01 = GreatCircle.position(grid: "JO01")!
check(near(jo01.latitude, 51.5, 0.001) && near(jo01.longitude, 1, 0.001), "JO01's centre: \(jo01)")
check(GreatCircle.position(grid: "FN")! == GreatCircle.Position(latitude: 45, longitude: -70), "a 2-character field")
let eight = GreatCircle.position(grid: "FN31pr45")!
check(near(eight.latitude, fn31pr.latitude, 0.03) && near(eight.longitude, fn31pr.longitude, 0.05),
      "8 characters lands inside its 6-character square")
for bad in ["", "F", "FN3", "SN31", "FN3Z", "FN31zz", "12AB", "FN31pr4"] {
    check(GreatCircle.position(grid: bad) == nil, "not a grid: \"\(bad)\"")
}
check(GreatCircle.position(latitude: "0", longitude: "0") == nil && GreatCircle.position(latitude: "95", longitude: "1") == nil
      && GreatCircle.position(latitude: "x", longitude: "1") == nil, "nonsense positions refused")

// Paths
let newYork = GreatCircle.Position(latitude: 40.7128, longitude: -74.0060)
let london = GreatCircle.Position(latitude: 51.5074, longitude: -0.1278)
let ny = GreatCircle.path(from: newYork, to: london)
check(near(ny.km, 5570, 15) && near(ny.bearing, 51.2, 1), "New York to London: \(Int(ny.km)) km at \(Int(ny.bearing))°")
let back = GreatCircle.path(from: london, to: newYork)
check(near(back.km, ny.km, 0.001) && near(back.bearing, 288, 1.5), "and back: the same distance, a different bearing")
let home = GreatCircle.path(myGrid: "EM10", fields: ["gridsquare": "FN31pr"])!
check(near(home.km, 2501, 5) && near(home.bearing, 53, 3), "EM10 to W1AW: \(Int(home.km)) km at \(Int(home.bearing))°")
check(GreatCircle.path(myGrid: "", fields: ["gridsquare": "FN31pr"]) == nil
      && GreatCircle.path(myGrid: "EM10", fields: [:]) == nil, "an unknown end: no path")
let precise = GreatCircle.path(myGrid: "EM10", fields: ["lat": "41.714", "lon": "-72.727", "gridsquare": "JO01"])!
check(near(precise.km, home.km, 5), "latitude and longitude are used before the grid")

// Words
check(GreatCircle.compass(0) == "north" && GreatCircle.compass(359) == "north" && GreatCircle.compass(51) == "north-east"
      && GreatCircle.compass(180) == "south" && GreatCircle.compass(292) == "west" && GreatCircle.compass(316) == "north-west",
      "eight compass points")
check(GreatCircle.spoken(km: ny.km, bearing: ny.bearing, miles: true) == "3,461 miles north-east",
      "said in miles: \(GreatCircle.spoken(km: ny.km, bearing: ny.bearing, miles: true))")
check(GreatCircle.spoken(km: ny.km, bearing: ny.bearing, miles: false) == "5,570 kilometres north-east"
      || GreatCircle.spoken(km: ny.km, bearing: ny.bearing, miles: false).hasSuffix("kilometres north-east"),
      "said in kilometres: \(GreatCircle.spoken(km: ny.km, bearing: ny.bearing, miles: false))")
check(GreatCircle.shown(km: ny.km, bearing: ny.bearing, miles: true) == "3,461 miles, 51 degrees north-east",
      "shown with degrees: \(GreatCircle.shown(km: ny.km, bearing: ny.bearing, miles: true))")
check(GreatCircle.spoken(km: 0.4, bearing: 10) == "nearby" && GreatCircle.spoken(km: 1.7, bearing: 90, miles: true) == "1 mile east",
      "very close: nearby; one mile, singular")

// A contact
var qso = QSO(call: "W1AW", timeOn: Date())
qso["my_gridsquare"] = "EM10"
qso["gridsquare"] = "FN31pr"
check(GreatCircle.path(for: qso).map { near($0.km, home.km, 0.001) } == true, "a contact's own fields give its path")
print("All distance checks passed.")
