// BandPlanUS.swift
//
// The United States band plan, written into the Band Plans folder the
// first time (BandPlanList), and the folder's README.
//
// Privileges: 47 CFR 97.301 (who may use which frequencies), 97.305(c)
// (which emissions where; CW is allowed everywhere a class has
// privileges, 97.305(a)) and 97.303(h) (60 meters), as amended 14
// January 2026, read 22 November 2026. ITU Region 2 (the 48 states,
// Alaska, Hawaii and the Caribbean territories); Pacific territories in
// Region 3 differ a little on 40 and 75 meters. Technicians and Novices
// on 80, 40 and 15 meters are CW only, and on 10 meters CW and data from
// 28.000 to 28.300 and CW and phone from 28.300 to 28.500.
//
// Activities: well-known frequencies, facts gathered here in our own
// words: WSJT-X's FT8 and FT4 dial frequencies, QRP and SKCC
// frequencies, the NCDXF beacons, SSTV, and calling frequencies. They
// give no privileges; the segments do.
//
// Power limits and the rules on 60 meters, 2200 and 630 meters (notify
// the Utilities Technology Council first) are noted, not checked.

import Foundation

extension BandPlan {
    static let unitedStates = """
    # United States amateur band plan (FCC), for Solid Copy.
    # Privileges from 47 CFR 97.301, 97.303(h) and 97.305 (amended
    # 14 January 2026), ITU Region 2. Edit freely: Solid Copy reads this
    # file each time. Frequencies in MHz; see README.txt for the format.
    name: United States (FCC)
    classes: Extra, Advanced, General, Technician, Novice

    # 2200 and 630 meters: notify the Utilities Technology Council first.
    segment: 0.1357-0.1378 | CW, data, phone, image | Extra, Advanced, General | 2200 meters; 1 W EIRP; notify UTC first
    segment: 0.472-0.479 | CW, data, phone, image | Extra, Advanced, General | 630 meters; 5 W EIRP; notify UTC first

    # 160 meters: every mode is allowed; CW is the custom below 1.843.
    segment: 1.800-2.000 | CW, data, phone, image | Extra, Advanced, General
    usual: 1.800-1.843 | CW
    activity: 1.810 | CW | QRP CW
    activity: 1.840 | data | FT8

    # 80 and 75 meters
    segment: 3.500-3.525 | CW, data | Extra
    segment: 3.525-3.600 | CW, data | Extra, Advanced, General
    segment: 3.525-3.600 | CW | Technician, Novice | 200 W
    segment: 3.600-3.700 | CW, phone, image | Extra
    segment: 3.700-3.800 | CW, phone, image | Extra, Advanced
    segment: 3.800-4.000 | CW, phone, image | Extra, Advanced, General
    activity: 3.550 | CW | SKCC
    activity: 3.560 | CW | QRP CW
    activity: 3.573 | data | FT8
    activity: 3.845 | phone | SSTV
    activity: 3.985 | phone | QRP SSB

    # 60 meters: the 5351.5-5366.5 kHz band and four channels (centre
    # frequencies 5.332, 5.348, 5.373, 5.405; for USB, set the dial
    # 1.5 kHz below). At most 2.8 kHz wide; power limits in 97.313.
    segment: 5.3305-5.3335 | CW, data, phone | Extra, Advanced, General | Channel, centre 5.332; USB dial 5.3305
    segment: 5.3465-5.3495 | CW, data, phone | Extra, Advanced, General | Channel, centre 5.348; USB dial 5.3465
    segment: 5.3515-5.3665 | CW, data, phone | Extra, Advanced, General | The 60 meter band
    segment: 5.3715-5.3745 | CW, data, phone | Extra, Advanced, General | Channel, centre 5.373; USB dial 5.3715
    segment: 5.4035-5.4065 | CW, data, phone | Extra, Advanced, General | Channel, centre 5.405; USB dial 5.4035
    activity: 5.357 | data | FT8

    # 40 meters
    segment: 7.000-7.025 | CW, data | Extra
    segment: 7.025-7.125 | CW, data | Extra, Advanced, General
    segment: 7.025-7.125 | CW | Technician, Novice | 200 W
    segment: 7.125-7.175 | CW, phone, image | Extra, Advanced
    segment: 7.175-7.300 | CW, phone, image | Extra, Advanced, General
    activity: 7.030 | CW | QRP CW
    activity: 7.0475 | data | FT4
    activity: 7.055 | CW | SKCC
    activity: 7.074 | data | FT8
    activity: 7.120 | CW | SKCC, for Technicians and Novices
    activity: 7.171 | phone | SSTV
    activity: 7.285 | phone | QRP SSB

    # 30 meters: no phone; 200 W.
    segment: 10.100-10.150 | CW, data | Extra, Advanced, General | 200 W
    activity: 10.106 | CW | QRP CW
    activity: 10.136 | data | FT8
    activity: 10.140 | data | FT4

    # 20 meters
    segment: 14.000-14.025 | CW, data | Extra
    segment: 14.025-14.150 | CW, data | Extra, Advanced, General
    segment: 14.150-14.175 | CW, phone, image | Extra
    segment: 14.175-14.225 | CW, phone, image | Extra, Advanced
    segment: 14.225-14.350 | CW, phone, image | Extra, Advanced, General
    activity: 14.050 | CW | SKCC
    activity: 14.060 | CW | QRP CW
    activity: 14.074 | data | FT8
    activity: 14.080 | data | FT4
    activity: 14.100 | | NCDXF beacons: listen, don't transmit
    activity: 14.230 | phone | SSTV
    activity: 14.285 | phone | QRP SSB

    # 17 meters
    segment: 18.068-18.110 | CW, data | Extra, Advanced, General
    segment: 18.110-18.168 | CW, phone, image | Extra, Advanced, General
    activity: 18.086 | CW | QRP CW
    activity: 18.100 | data | FT8
    activity: 18.104 | data | FT4
    activity: 18.110 | | NCDXF beacons: listen, don't transmit

    # 15 meters
    segment: 21.000-21.025 | CW, data | Extra
    segment: 21.025-21.200 | CW, data | Extra, Advanced, General
    segment: 21.025-21.200 | CW | Technician, Novice | 200 W
    segment: 21.200-21.225 | CW, phone, image | Extra
    segment: 21.225-21.275 | CW, phone, image | Extra, Advanced
    segment: 21.275-21.450 | CW, phone, image | Extra, Advanced, General
    activity: 21.050 | CW | SKCC
    activity: 21.060 | CW | QRP CW
    activity: 21.074 | data | FT8
    activity: 21.140 | data | FT4
    activity: 21.150 | | NCDXF beacons: listen, don't transmit
    activity: 21.340 | phone | SSTV
    activity: 21.385 | phone | QRP SSB

    # 12 meters
    segment: 24.890-24.930 | CW, data | Extra, Advanced, General
    segment: 24.930-24.990 | CW, phone, image | Extra, Advanced, General
    activity: 24.906 | CW | QRP CW
    activity: 24.915 | data | FT8
    activity: 24.919 | data | FT4
    activity: 24.930 | | NCDXF beacons: listen, don't transmit

    # 10 meters
    segment: 28.000-28.300 | CW, data | Extra, Advanced, General
    segment: 28.000-28.300 | CW, data | Technician, Novice | 200 W
    segment: 28.300-28.500 | CW, phone, image | Extra, Advanced, General
    segment: 28.300-28.500 | CW, phone | Technician, Novice | 200 W; SSB phone
    segment: 28.500-29.700 | CW, phone, image | Extra, Advanced, General | FM from 29.000
    activity: 28.050 | CW | SKCC
    activity: 28.060 | CW | QRP CW
    activity: 28.074 | data | FT8
    activity: 28.180 | data | FT4
    activity: 28.200 | | NCDXF beacons: listen, don't transmit
    activity: 28.385 | phone | QRP SSB
    activity: 28.680 | phone | SSTV
    activity: 29.600 | phone | FM simplex calling

    # 6 meters: CW only below 50.100.
    segment: 50.000-50.100 | CW | Extra, Advanced, General, Technician | CW only
    segment: 50.100-54.000 | CW, data, phone, image | Extra, Advanced, General, Technician
    activity: 50.090 | CW | SKCC and CW calling
    activity: 50.125 | phone | SSB calling
    activity: 50.313 | data | FT8
    activity: 50.318 | data | FT4
    activity: 52.525 | phone | FM simplex calling

    # 2 meters: CW only below 144.100.
    segment: 144.000-144.100 | CW | Extra, Advanced, General, Technician | CW only
    segment: 144.100-148.000 | CW, data, phone, image | Extra, Advanced, General, Technician
    activity: 144.174 | data | FT8
    activity: 144.200 | phone | SSB calling
    activity: 146.520 | phone | FM simplex calling

    # 1.25 meters
    segment: 219.000-220.000 | data | Extra, Advanced, General, Technician | Digital message forwarding only; notify ARRL first
    segment: 222.000-225.000 | CW, data, phone, image | Extra, Advanced, General, Technician, Novice | Novice: 25 W
    activity: 223.500 | phone | FM simplex calling

    # 70 centimeters
    segment: 420.000-450.000 | CW, data, phone, image | Extra, Advanced, General, Technician
    activity: 432.100 | phone | SSB calling
    activity: 446.000 | phone | FM simplex calling

    # 33 and 23 centimeters
    segment: 902.000-928.000 | CW, data, phone, image | Extra, Advanced, General, Technician
    segment: 1240.000-1300.000 | CW, data, phone, image | Extra, Advanced, General, Technician
    segment: 1270.000-1295.000 | CW, data, phone, image | Novice | Novice: 5 W
    activity: 1294.500 | phone | FM simplex calling

    """

    static let readme = """
    Band plans for Solid Copy

    Each .txt file here is one country's band plan. Choose which one in
    Settings > Band Plan; Window > Band Plan (Command-6) shows it, and the
    out-of-band warning checks the radio against it. Solid Copy reads the
    files each time, so a change works at once. One setting per line; a #
    starts a comment. Frequencies are in MHz.

    name: United States (FCC)                 required, what menus say
    classes: Extra, Advanced, General, ...    required, every license class
    segment: 14.000-14.025 | CW, data | Extra | a note (optional)
    activity: 14.074 | data | FT8
    usual: 1.800-1.843 | CW                   where a mode is the custom

    A segment says which classes may use a range, and for what: CW, data,
    phone, image. The same range can come again for other classes with
    other modes. "all" means every class. An activity is a frequency where
    something usually happens (FT8, a calling frequency); it gives no
    privileges, and its mode can be left empty. A usual line says where
    one mode is the custom though others are allowed (CW low on 160
    meters): a frequency typed in Callsign gets that mode.

    To add another country, copy the United States file, change its name,
    classes and segments, and save it here with a new file name.

    """
}
