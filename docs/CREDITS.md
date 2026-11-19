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

## Hamlib's rigctld, libhamlib and libusb (the radio)

Solid Copy ships three pieces of open-source software, unchanged, inside the
app (Contents/Helpers and Contents/Frameworks), so it can talk to your radio
without Homebrew or any other install:

- **rigctld**, from Hamlib (version 4.7.2 when this was written). It's a
  separate program that Solid Copy starts and talks to over a local
  connection. Its licence is the GNU General Public License, version 2
  or (at your option) any later version (Hamlib's COPYING file), so it
  can ship alongside Solid Copy's GPL-3.0.
- **libhamlib**, Hamlib's radio library, which rigctld uses. Licence: GNU
  Lesser General Public License (Hamlib's COPYING.LIB).
- **libusb** (1.0), which rigctld uses to reach some radios' USB cables.
  Licence: GNU Lesser General Public License, version 2.1 or later.

Their licence texts are in the app's Contents/Resources (Hamlib-COPYING.txt,
Hamlib-NOTICE.txt). Their source code is at https://github.com/Hamlib/Hamlib
(each version's own source is on its release page, such as
https://github.com/Hamlib/Hamlib/releases/tag/4.7.2) and
https://github.com/libusb/libusb. Solid Copy's own source code is
GPL-3.0. rigctld is a separate program that Solid Copy starts, not code
linked into Solid Copy, which is how GPL programs are normally shipped
alongside one another. Hamlib's maintainers were asked (Hamlib-developer
mailing list, 19 November 2026): a maintainer saw no issue, noting the
"or any later version" clause, and said a mention and link back to
Hamlib is welcomed. Solid Copy credits Hamlib, with a link, in its Read
Me and in the notice inside the app.

With thanks to the Hamlib project and its contributors:
https://hamlib.github.io/
