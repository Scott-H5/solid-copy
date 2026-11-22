# Credits

Outside material that ships inside Solid Copy, where it's from, and why
Solid Copy may use it.

## The J-38 card picture (macOS/J38Key.jpg)

A photo of a J-38 straight key, offered in Settings > QSL Card ("Use the
J-38 Picture") for anyone without a card picture of their own.

- Photo by Lou Sander, released by him into the public domain, worldwide
  ("Lou Sander grants anyone the right to use this work for any purpose,
  without any conditions").
- Source: Wikimedia Commons, File:J38TelegraphKey.jpg
  (https://commons.wikimedia.org/wiki/File:J38TelegraphKey.jpg), first
  uploaded to the English Wikipedia.
- Downloaded 17 November 2026: 320 by 240 pixels, 55,510 bytes, SHA-1
  2fee837117e275c3f8d9afb60c6fe3604217525b (matching Commons' record).
- No credit is required, so cards carry none; it's given here because
  it's fair.

## Band conditions from HAMQSL.com (fetched, not shipped)

Speech > Say Band Conditions reads N0NBH's (Paul L Herrman's) solar data
feed, https://www.hamqsl.com/solarxml.php, when you ask: solar flux, A
and K indexes, geomagnetic field, noise, and his estimate of each band
by day and night. Nothing of his ships inside Solid Copy.

- His page (https://www.hamqsl.com/solar.html, read 22 November 2026)
  offers the feed for others' use and asks for credit: "Credit to
  HAMQSL.com would be appreciated." Every answer Solid Copy speaks ends
  "From HAMQSL.com, N0NBH".
- It asks for no more than hourly updates, "the update period for the
  flux parameters", so Solid Copy fetches it at most once an hour.
- The page says the feeds may stop if his provider objects; Solid Copy
  then says it couldn't get them, with the last figures it has.

With thanks to N0NBH.

## Hamlib (not shipped with Solid Copy)

Solid Copy doesn't ship Hamlib. Its built-in driver talks to Kenwood and
Elecraft radios directly. For other radios, you run hamlib's rigctld
yourself, from Homebrew or hamlib's own instructions, and choose
"Hamlib NET rigctl" in Settings > Radio. Solid Copy's own source code is
GPL-3.0; Hamlib's licence (GPL-2.0-or-later for rigctld, LGPL for its
library) applies to Hamlib itself, which isn't part of Solid Copy.
Hamlib's source code is at https://github.com/Hamlib/Hamlib.
When Solid Copy shipped a copy of rigctld (up to v1.2), Hamlib's
maintainers were asked (Hamlib-developer mailing list, 19 November 2026):
a maintainer saw no issue, and asked for a mention and link back to
Hamlib. Solid Copy's Read Me and its Help give that link.

With thanks to the Hamlib project and its contributors:
https://hamlib.github.io/
