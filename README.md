# Solid Copy

A ham radio logging app for the Mac, designed from the start for
VoiceOver and the keyboard.

"Solid copy" is ham shorthand for "I received everything."

## Status

Solid Copy is an everyday logger, used on the air with VoiceOver. It:

- logs a contact from the keyboard alone, starting in the Callsign field
- fills in name, QTH and grid from QRZ (or callook.info)
- reads frequency, band, mode and power from the radio, through its own
  built-in driver for Kenwood and Elecraft radios, or hamlib's rigctld for
  others (tested with the Kenwood TS-590SG and Elecraft KX3)
- uploads to LoTW, QRZ Logbook, Club Log and eQSL, automatically if you
  like, and brings LoTW and QRZ confirmations back
- warns about dupes, and says each contact's country and whether it's a
  new one, band or mode
- runs contests (ARRL Field Day and SKCC's sprints), with serial
  numbers, scores, and CW messages through a WinKeyer
- tracks QSLs and parks, shows spots, and makes an electronic QSL card
  you can send by email
- tracks awards: DXCC, WAS, WAZ and WPX (worked, confirmed and still
  needed, on each band and mode), SKCC Centurion, Tribune and Senator,
  and POTA parks hunted
- works FT8 and other digital modes with WSJT-X: its decodes in a list
  VoiceOver reads, Return to answer a station, alerts for needed
  stations in the background, and contacts WSJT-X logs
  arriving in your log
- shares the radio with programs such as WSJT-X (Hamlib NET rigctl),
  with safeguards when they transmit
- turns the antenna through hamlib's rotctld: to the station you're
  logging, the long path, or a heading you type
- shows the band plan for your license class (the United States plan
  from the FCC's rules to start), warns when the radio is outside your
  privileges, and gives the band conditions from HAMQSL.com
- keeps separate logs, imports ADIF, ADX and log files in the SQL
  format (.sql), exports ADIF, ADX, CSV and Cabrillo, and backs up to a
  folder you choose

See [docs/PLAN.md](docs/PLAN.md) for where it's headed.

## Installing

Download the zip from the latest release at
https://github.com/Scott-H5/solid-copy/releases and open it. You get a
folder with two things in it: **Solid Copy.app** and this Read Me
(**Solid Copy Read Me.html**). Drag Solid Copy.app to your Applications
folder, then open it. It's signed and notarized, so macOS opens it
without warnings. It needs macOS 14 (Sonoma) or later.

This Read Me is also inside the app: **Help > Solid Copy Help**
(Command-?) opens it in your web browser, with no internet needed, so
it's there in the field too. **Help > Solid Copy on GitHub** opens the
project's page, with the latest version. In the browser, VO-Command-H
moves from heading to heading.

## Testing it

Thank you for trying Solid Copy. What's most useful to hear about is how
it feels to use:

- **Is it intuitive?** Could you find your way around without help, and
  did things work the way you expected?
- **Is it easy to navigate?** With VoiceOver and the keyboard: the
  logging form, the log, the menus and Settings.
- **Does the layout make logging efficient?** Can you log a contact
  quickly, without extra steps?
- **Is saving, changing or editing contacts clear?** Was anything about
  logging a contact, editing one, or deleting one confusing?

If something goes wrong, please say:

- which radio you're using
- your version of macOS (Apple menu > About This Mac)
- what kind of Mac it is (for example, a MacBook Air with an M2)

Reply to the email that invited you, or open an issue at
https://github.com/Scott-H5/solid-copy/issues.

## First setup

The first time Solid Copy opens, with no callsign set, a short sheet asks
for three things:

- **Callsign**: yours, such as W1AW. Every contact you log carries it, and
  the uploads (LoTW, QRZ, Club Log, eQSL) need it.
- **Name**: optional. It's used by the CW messages' {MYNAME}.
- **Grid square**: optional, 4 or 6 characters, such as FN31 or FN31pr. It's
  used for distance and bearing, and for LoTW.

Save keeps them. Skip leaves them empty, and then the sheet doesn't come
back; you can fill them in later under **Settings > Profiles** (callsign
and grid) and **Settings > CW** (name). **Set Up Station…** in Settings >
Profiles shows this sheet again at any time. A profile with a callsign
already never shows the sheet on its own.

Then, to log a contact: type the callsign in the Callsign field and
press Tab through the fields, then Command-Return to log it. The log
keeps every contact as you go. (Settings > Logging Form, **Log a contact
with**, can let plain Return log too; Command-Return only is the
starting choice, so a stray Return never logs. Plain Return then says
"Command-Return logs".)

**Each contact is timed.** Entering the call starts the clock: when you
leave Callsign with a call in it, or pick a spot, that's the contact's
start time. Logging it stops the clock: Command-Return (or Return, if
Settings > Logging Form lets Return log) is its end time. Both are kept
with the contact (Date and Time are the start; End date and End time are
the end), so you can see how long it lasted. Leaving Callsign again with
the same call doesn't restart the clock; a different call does. A call
left in the form for more than 2 hours starts when it's logged instead.
Typing a call and logging it without leaving Callsign gives the same
start and end. Contacts from WSJT-X come with WSJT-X's own start and
end.

## Using it

| Key | What it does |
| --- | --- |
| Tab, Shift-Tab | Move between Callsign, Name, RST sent, RST received (and any other fields you add in Settings) |
| Command-Return | Log the contact (its end time) and go back to Callsign (plain Return too, if Settings > Logging Form says so) |
| Escape or Command-K | Clear the form |
| Command-L | Go to Callsign |
| Command-I | Go to the newest contact in the log |
| Command-comma | Settings |
| Command-0 | Bring back the logging window if it was closed (so does clicking Solid Copy in the Dock) |
| Command-1 | Spots (who's on the air); see Spots below |
| Command-backtick, Shift-Command-backtick | Next and previous window (the logging window, Spots and Settings) |
| Command-F | Search the log (every word, in any field); Return or Down goes to the matches, Escape clears |
| Option-Command-F | Show only contacts with the call in the form (or the selected call); Escape shows all |
| Up, Down (in the log) | Move between contacts |
| Return or Command-E (in the log) | Edit the selected contact |
| Return / Command-Return / Command-S (in Edit Contact) | Save (in QSO notes, Return starts a new line) |
| Escape (in Edit Contact) | Cancel |
| (in Edit Contact) | QSL statuses and "via" are menus in words (Yes, No, Requested ...; Bureau, Direct ...), and QSL dates are typed like 2025-12-17 |
| Shift-Up, Shift-Down (in the log) | Select several contacts |
| Command-C (in the log) | Copy the selected contacts |
| Command-V (in the log or the form) | With contacts on the clipboard, paste them into the open log (Command-Z takes a paste out) |
| Command-N, Shift-Command-N | New log, new test log |
| F1 to F8 | Send CW messages 1 to 8 through the WinKeyer (CW menu) |
| Escape (while CW is sending) | Stop sending |
| Left, Right (in the log) | Choose a column; says its name and the selected contact's value ("Date (UTC), 2026-11-16") |
| Option-Command-Left, Option-Command-Right (in the log) | Move the chosen column; says where it went ("Date (UTC), now column 2 of 8"). Call stays first. The order is saved |
| Delete or Command-Delete (in the log) | Delete the selected contacts |
| Up Arrow (in an empty Callsign) | Correct the last contact: it comes back into the form; Up and Down go to older and newer ones; Command-Return saves the change to that contact (or Return, as Settings > Logging Form says), Escape leaves it as it was |
| Command-Z | Undo: right after logging, takes the contact back out of the log and puts it in the form to fix; after clearing, brings the form back; in the log, puts a deleted contact back |
| Shift-Command-Z | Redo |
| Escape (in the log) | Go back to Callsign |
| Tab, Shift-Tab (on the form, with QSO notes added in Settings) | QSO notes isn't a Tab stop: click in it or reach it with VoiceOver. Return logs the contact, as in every form field |
| Tab (in the log) or Option-Command-I | Go to the details of the selected contact |
| Shift-Tab (in the log) | Go back to the form's last Tab stop |
| Up, Down (in the details) | Move between fields |
| Command-C (in the details) | Copy the selected field's value |
| Escape, Tab or Shift-Tab (in the details) | Go back to the log |

The log's columns start in the order Call, Name, Date, Time, Band, Frequency, Mode,
RST Sent, RST Received, Country, QSO notes. Every other field is in the
details panel under the log.

**QSO notes** is for your own use. It is never uploaded to LoTW, QRZ Logbook,
Club Log or eQSL, and it is left out of exports unless you tick Include QSO
notes. The Comment field is different: it goes out with the contact, so use
it only for what you want the other station and the services to see.

## Operating profiles

A profile, such as **Home** or **Portable**, is a logging form plus your
station's details (callsign, grid, state, county, radio, park, summit…),
which are added to every contact logged with it. Switch with the
**Profile** menu or **Option-Command-1, 2, 3…**; the window title says
which is in use. **Settings > Profiles** (Command-comma, then Command-2) adds,
renames and deletes profiles and holds each one's station details.
Portable starts with Band, Mode, Frequency and Power on the form, for when
the radio or the internet isn't there, with Power starting at 5 watts.

**New Profile** is a menu: a copy of the profile in use, or a fresh one
from a template: Home, Portable, POTA activation (their park, for park to
park), SOTA activation (their summit), Field Day (their class and section)
or State QSO Party (their county or state). A template sets the form; your
station comes from the profile in use, without its park or summit. Change
anything afterwards in Logging Form.

## Parks

Park fields search POTA's list of every park, kept on your Mac, so they
work in a park with no internet: **POTA park** (theirs) on the logging form
and in Edit Contact, and **My POTA park** in Settings > Profiles (and Edit
Contact). Type a reference ("US-13"), part of
a name ("big poc") or a state ("pennsylvania state", or "PA"). After a
pause you hear how many parks match. **Down and Up Arrow** go through
them, each said in full ("US-1333, Big Pocono State Park, Pennsylvania. 1
of 3"). Leaving the field with only one match takes it. Return won't log
a contact whose park is still a search: it says how many match. For a
two-fer, put a comma between parks ("US-1333,US-1334").

**Hunting a park you tuned to yourself.** You don't have to pick the spot
in the Spots window. When you leave Callsign, Solid Copy checks POTA's
spots, and if that call is spotted at a park in the last hour, the park
goes into the contact and is said with the lookup: "W3XYZ, Ann, Pennsylvania, at
park US-1333, Big Pocono State Park, Pennsylvania". It's in POTA park if
that's on your form, so you can change it, and in the contact either way.
Change the call and the park comes out again. A park you typed, or one
from a spot you picked, is never replaced. This needs the internet; the
spots are fetched at most every 90 seconds.

**Past hunts.** In Edit Contact (Command-E on a contact), POTA park
searches the park list the same way, so you can add the parks of earlier
contacts and they count in Window > Awards.

The list (about 106,000 parks, 10 MB) is fetched the first time you use
a park field, and again when it's a month old. **Settings > Lookup > Get
the Park List Now** fetches it whenever you like.

RST sent and RST received take only digits, with a plus or minus in
front: 59, 599, or -12 for FT8. Anything else beeps and isn't entered.

A contest profile (one with Contest on its form) or a park activation
(one with your park) warns of a dupe when you leave Callsign: "Dupe:
W1AW worked on 20 meters CW at 14:32 UTC", said first, with the dupe
sound, and shown on the lookup line. You can still log it.

## Spots

**Window > Spots** (Command-1) lists who's on the air, newest first, one
line each, from POTA ("W1AW, 14.062 CW, US-1333 Big Pocono State Park,
Pennsylvania, 3 minutes ago, worked today") and, once you turn it on in
**Settings > Spots**, a DX cluster ("VP8XYZ, 14.025 CW, Falkland Islands,
needed: new country, 2 minutes ago. CQ CQ up 2, spotted by K1ABC"). It
updates while the window is open (POTA each minute, the cluster every
10 seconds at most); a new list never moves you or talks. If it changes
too fast to follow, the **Refresh** pop-up shows new spots every 15, 30
or 45 seconds or every minute instead of **Live**; a filter you change
still shows at once.

| Key | What it does |
| --- | --- |
| Up, Down | Move between spots |
| Return | Use the spot: tunes the radio to it (frequency and mode), puts its call and park in the logging form, and goes there. Add the reports and press Return to log |
| Escape | Back to the logging window (Spots stays open) |
| Tab | To the filters: Source (POTA, DX cluster), Band (all bands, your radio's current band, or any one band), Mode (CW, phone, data), Refresh (Live, or every 15, 30 or 45 seconds or minute), Hide spots worked today, DX: needed only, and DX: heard near me |

"Worked today" follows POTA's rule: that park, on that band and mode,
this UTC day. Command-backtick moves between Spots, the logging window
and Settings.

**DX cluster.** A cluster node passes on spots from hams everywhere,
thousands an hour. Turn it on in **Settings > Spots** and choose a node:
VE7CC (dxc.ve7cc.net, port 23) to start with, W3LPL, K3LR, or any other
by its address and port. Solid Copy logs in with the callsign in the profile in
use, only while the Spots window is open, and reconnects if it drops.
Each DX spot says its country (from cty.dat, fetched from
country-files.com and refreshed monthly) and whether you need it: a new
country, or a new band or mode for one, worked out from your log. A
spot's mode is worked out from its comment or where it is on the band.
**DX: needed only** leaves just those. Many nodes (VE7CC among them)
send only spots typed by people unless asked: **Include skimmer spots**
adds CW stations heard by the Reverse Beacon Network's receivers, and
**Include FT8 and FT4 spots** adds those. Both make many more spots, so
they start off. A station spotted by several skimmers says so ("heard
by 12": the more, the stronger and wider it's heard). **DX: heard near
me** keeps only spots from spotters on your own continent (from your
callsign in the profile in use), the ones you're likely to hear too.
**SOTA** spots come from the DX cluster: a cluster spot whose comment
names a summit ("W4C/CM-001") is listed as a SOTA spot, with its summit,
and the Source filter can show just those. Return on one fills in their
summit (SOTA summit). Only spots posted to the cluster are seen, so it's
most SOTA activations, not all: SOTA's own API doesn't allow AI-assisted
software without SOTA's approval (its terms, at api-db2.sota.org.uk/docs).
SOTA's database takes ADIF uploads, so File > Export ADIF makes your
SOTA log (it has MY_SOTA_REF and SOTA_REF).

## Settings

Settings (Command-comma) is laid out like System Settings: a list of
sections down the left (Lookup, Profiles, Logging Form, Log Columns,
Radio, Speech, Spots, Uploads, Clubs, Backups, CW, QSL Card, Band Plan) and the chosen section on the right,
scrolling if it's tall. Command-1 to Command-9 go straight to a section. In the list, Up and Down
choose a section and Return or Right Arrow go into it; Tab goes round the
section and back to the list. Escape or Command-W closes Settings.

## Speech

Solid Copy talks through VoiceOver, so its messages reach a braille
display too, and nothing is said when VoiceOver is off. Three kinds of
message come often and can talk over a contact you're copying, so
**Settings > Speech** lets you choose how much each says:

| Message | Choices |
| --- | --- |
| Callsign lookups | Say everything, name only, sound only, or nothing |
| Logging a contact | Say everything, just "Logged", or sound only |
| Radio changes you make | Say everything, or sound only |
| Radio lost or back | Its tone and the words, or the tone only |

Errors and warnings are always said in full. The **Speech** menu brings
back what you turned down, whenever you want it:

| Key | What it does |
| --- | --- |
| Option-Command-period | Quiet Mode: lookups, logging and radio changes down to sounds, until you turn it off (for a pile-up, say) |
| Option-Command-N | Say the name and place for the call in the form (looks it up if it hasn't been) |
| Option-Command-L | Say the last contact logged |
| Option-Command-C | Say the contest log's score (see Contests) |
| Option-Command-B | Show the band conditions (below) |
| Command-R (Radio menu) | Say what the radio is doing |

Most sounds are ones every Mac has: Glass for logged, Pop for a lookup
found, Bottle for not found, Tink for a radio change, Basso for a
problem. The moments that must stand out have Solid Copy's own sounds,
made so they sound like nothing else on the Mac, and nothing like a CW
signal or sidetone:

- **A dupe**: two short low buzzes.
- **Needed**: two quick bells going up, for a call you type that's a
  new country, band or mode, and for a needed DX spot as it comes in.
- **The radio**: two falling notes when it's lost, two rising when it's
  back.

Choose the dupe and needed sounds in **Settings > Speech**, under
Sounds (Solid Copy's others, any Mac sound, or none; choosing one plays
it). **Needed sound for DX spots** is New countries only to start with
(a young log needs nearly every band and mode), New country, band or
mode, or No sound. A spot plays it once per call and band, and at most
every 30 seconds, while the Spots window is getting spots. These sounds
play whatever the speech levels say, Quiet Mode too.

Logging a contact with no band (most often because the radio dropped
without your noticing) gives the warning sound and "No band": type the
band or frequency, or press Return again to log it anyway. A frequency
typed without a band fills the band in by itself.

### Band conditions

**Speech > Band Conditions…** (Option-Command-B) opens a window with how
the bands are, from N0NBH's solar data at HAMQSL.com, a line each, so you
can read it with VoiceOver at your own pace; OK (Return) closes it, and
Copy puts it on the clipboard:

```
Now, daytime here: 80 to 40 meters good, 30 to 20 good, 17 to 15 fair, 12 to 10 poor.
Tonight: 17 to 15 poor.
Solar flux 99, A index 6, K index 0.
Geomagnetic field inactive, noise S0 to S1.
From HAMQSL.com, N0NBH, updated 1814 UTC.
```

- Day or night is by the sun at the grid in your profile (or 6 am to 6
  pm by the Mac's clock without one), and the other half of the day is
  said only where it differs.
- VHF openings (E skip, aurora) are said only when N0NBH reports one.
- N0NBH updates the figures about once an hour and asks that they're
  fetched no more often, so Solid Copy fetches them at most hourly, and
  only when you ask ("Getting band conditions" while it does).
- If HAMQSL.com can't be reached, the window says so and shows NOAA's
  figures instead (the Space Weather Prediction Center's solar flux and
  K index, with when each was measured), and N0NBH's last ones with how
  old they are. NOAA makes no band-by-band estimate, so there's none
  then. A failure is in Window > Activity.

## The radio

Solid Copy reads frequency, band, mode and power from the radio. For
Kenwood and Elecraft radios (TS-590S, TS-590SG, K3, KX3, KX2) it uses its
own built-in driver, which talks to the radio's USB port directly, so
nothing else needs installing. Any other radio works through hamlib's
`rigctld`, which you run yourself (see "Hamlib NET rigctl" below).

Add your radios in **Settings > Radio** (Command-comma, Command-5):
**New Radio**, then its connection, manufacturer, model, USB port and
speed (the TS-590SG uses 115200, the KX3 38400). One radio is in use at a
time, whatever the profile.

- **Band scan** (Radio > Band Scan, Control-Command-C) starts the radio's
  own band scan; press it again to stop. It says when it starts and stops
  (with the frequency it stopped on), not at each step. The TS-590 only,
  through the built-in driver. The scan's speed is set on the radio, with
  the knob that also sets RIT and XIT; Solid Copy has no command for it.
- **Switch radios** in the middle of a session: **Control-Command-1, 2…**
  (the Radio menu lists them), or the radio pop-up under the clocks.
- The radio pop-up's label is the radio and what it's doing:
  "Kenwood TS-590SG: 7.025241 MHz, CW, 40m, 5 W, menu button". Its menu
  has your radios, No Radio, and Radio Settings.

- The form's radio fields fill in as you tune. Type in one and yours is
  kept until the form is cleared. Fields not on the form are still
  logged from the radio.
- **Command-R** (Radio > Radio Status) says frequency, mode, filter, band
  and power, or what's wrong. **Option-Command-R** (Radio Details) says
  the line at the bottom of the window: keyer speed, RIT, XIT, split,
  AGC, preamp and attenuator (whichever the radio reports).

### Driving the radio from the keyboard

| Keys | What they do |
|---|---|
| Command-T | Go to the tuning control at the bottom of the window |
| Up, Down (in the tuning control) | Tune 100 Hz |
| Shift-Up, Shift-Down | Tune 10 Hz |
| Option-Up, Option-Down | Tune 1 kHz |
| Tab (in the tuning control) | On to Offset (RIT or XIT), Power, RF gain and Squelch (only in FM), whichever the radio has; then back to Callsign |
| Up, Down (in the Offset control) | Offset 10 Hz; with Option, 100 Hz |
| Delete (in the Offset control) | Clear the offset to 0 |
| Up, Down (in Power) | 1 watt; with Shift a tenth, with Option 5 (up to the radio's most) |
| Up, Down (in RF gain or Squelch) | 5 percent; with Shift 1, with Option 20 |
| Escape (in any of them) | Back to Callsign |
| Control-Command-Up, Down Arrow | Band up and down ("20 meters, 14.03 megahertz, CW"): the radio's own band keys, or back to where you last were on that band, or a usual spot for the mode |
| Control-Command-W | Dual watch on and off (KX3). Not D: Control-Command-D is macOS's Look Up |
| Option-Command-S | Say the S-meter ("S 7", "S 9 plus 10 dB") |
| 14060 or 7.0255, then Return, in Callsign | Tune there (1000 or more is kHz, less is MHz), in the band plan's usual mode there (below) |
| CW, USB, LSB, SSB, AM, FM, RTTY or DATA, then Return, in Callsign | Change mode (SSB is LSB below 10 MHz, USB above, and USB on 60 meters) |
| 14.050 CW, 7200 LSB or CW 14050, then Return, in Callsign | Tune there in that mode: "14.05 megahertz, CW, 500 hertz" |
| Control-Command-M | Next mode |
| Control-Command-] and [ | Wider and narrower filter |
| Control-Command-= (or +) and - | Keyer faster and slower |
| Control-Command-P | Preamp on and off |
| Control-Command-A | Attenuator on and off |
| Control-Command-G | AGC: slow, medium, fast, off (the speeds the radio has) |
| Control-Command-B | Noise blanker on and off |
| Control-Command-N | Noise reduction on and off |
| Control-Command-K | Audio peak filter on and off (KX3) |
| Control-Command-R | RIT on and off |
| Control-Command-X | XIT on and off |
| Control-Command-S | Split on and off |
| Control-Command-V | Swap VFOs (or use the other VFO) |

The tuning control is a slider to VoiceOver ("Tuning, 7025.30
kilohertz"); each change is spoken, including turns of the radio's own
knob while you're there. Each command says what the radio actually did
("CW, 500 hertz", "Keyer 22 words per minute", "Preamp 12 dB"), or that
the radio can't ("Elecraft KX3 didn't change its AGC"). If VoiceOver's Quick Nav
is on, it takes the arrow keys; VO-Up and VO-Down tune instead.
- Changes are spoken once, naming the radio: "Kenwood TS-590SG
  connected…", "Elecraft KX3 off or unplugged", "… not answering".
- Solid Copy never gives up: switch the radio on before or after it, off
  and on again, or unplug and replug it, and it reconnects by itself.
  Radio > Reconnect Radio starts afresh if you ever want to.
- A radio that stops answering through the built-in driver has its port
  closed and opened again every few seconds until it answers, since a
  port can go stale while staying open (repeated VoiceOver restarts with
  a USB braille display did it to a TS-590).
- A missed answer or two isn't called a lost radio: Solid Copy says
  "lost" only after 4 seconds without one. Restarting VoiceOver with a
  USB braille display plugged in can make the radio miss a second's
  read, which before version 1.1.2 was announced as lost, then back.
- Programs such as WSJT-X can use the radio through Solid
  Copy while you log: see "Sharing the radio with other programs" below.
  The built-in driver holds the radio's USB port itself, so a rigctld
  you run can't open that radio at the same time.

### Hamlib NET rigctl: a rigctld you run yourself

**Settings > Radio > Connect through** has **Hamlib NET rigctl** for a
rigctld you run yourself, from hamlib, on this Mac or another one. Set its **IP address**
(127.0.0.1 is this Mac) and **Network port** (4532 is rigctld's usual
port). Solid Copy then uses that rigctld and nothing else.

To get hamlib, install it with Homebrew (see https://brew.sh for
installing Homebrew):

```bash
brew install hamlib
```

Then start rigctld for your radio. These are the TS-590SG (model 2037,
115200 baud) and the KX3 (model 2045, 38400 baud); use your radio's
model number and the port from Settings > Radio:

```bash
rigctld -m 2037 -r /dev/cu.usbserial-XXXX -s 115200 -t 4532
```

Leave that running while you log. Hamlib's own instructions, and its
full list of radios, are at https://hamlib.github.io/.

To change from the built-in driver to a rigctld you run without
restarting anything: choose Hamlib NET rigctl in Settings > Radio first
(that lets go of the radio's port), then start rigctld. To go back, quit
rigctld (Control-C) first, then choose the built-in driver.

### Sharing the radio with other programs

**Settings > Radio > Share the radio with other programs** lets
programs that can use Hamlib NET rigctl, such as WSJT-X, use
the radio through Solid Copy while you keep
logging, with no rigctld to run and no switching. Solid Copy answers
them the way hamlib's rigctld would.

In the other program, choose the radio **Hamlib NET rigctl**, with the
network server **127.0.0.1** and port **4532**. That's all.

- It works while the radio in use connects through the built-in driver.
  (With Hamlib NET rigctl, the rigctld you run shares the radio itself.)
- Only programs on this Mac can connect; nothing on your network can.
- They can tune the radio, change its mode and VFO, and turn split on
  and off.
- **Let them transmit** (under it, off until you turn it on) lets them
  key the radio too (PTT). On the TS-590 they transmit from its data
  input, the USB audio they play; set the program's PTT method to CAT.
  Turning it on or off works at once, even for programs already
  connected. Try it into a dummy load first.
- Solid Copy keeps the radio from being left on the air. It goes back to
  receive if the program that keyed it goes (quits, crashes, loses its
  connection), if sharing or Let them transmit is turned off, if you
  choose another radio, when Solid Copy quits, and after 5 minutes of
  one transmission. Each of those is said.
- One program transmits at a time. A program's first transmission is
  said ("A program is transmitting through Solid Copy"); later ones
  aren't, since FT8 keys every 15 seconds. A program saying "receive"
  never cuts off you transmitting with your own microphone.
- If another program, such as a rigctld, already has port 4532, Solid
  Copy says so and doesn't share the radio.
- A short pause in the radio's answers (restarting VoiceOver with a USB
  braille display does it) isn't passed on: for up to 90 seconds,
  programs get the last reading, and a frequency or mode change is held
  and sent when the radio answers again, so WSJT-X doesn't stop and ask
  to set the radio up again. Transmitting is never held: it's refused
  until the radio answers. Window > Activity lists each such pause and
  how long it lasted.
- Solid Copy says when a program connects ("A program connected to the
  radio through Solid Copy") and when it goes. Window > Activity lists
  those, and when sharing starts and stops.

### The rotor

Solid Copy can turn your antenna through hamlib's **rotctld**, which you
run for your rotor as you would rigctld for a radio. Turn on **Use a
rotor through rotctld** in Settings > Radio; leave the address empty for
this Mac at rotctld's usual port, 127.0.0.1:4533. Start rotctld with
your rotor's model number and its port, for example:

```bash
rotctld -m <your model> -r /dev/cu.usbserial-XXXX
```

`rotctld -l` lists the models. To try it with no rotor, hamlib's
pretend rotor is model 1:

```bash
rotctld -m 1
```

The commands are in the Radio menu, all Control-Shift-Command and a
letter:

| Command | Keys | What it does |
|---|---|---|
| Turn Rotor to Station | Control-Shift-Command-T | Points at the call in the logging form, from your grid (Settings > Profiles) to where its lookup puts it |
| Turn Rotor Long Path | Control-Shift-Command-L | The other way round the world |
| Turn Rotor To… | Control-Shift-Command-E | A heading you type, 0 to 360 degrees |
| Rotor Heading | Control-Shift-Command-H | Says where it's pointing |
| Stop Rotor | Control-Shift-Command-S | Stops it at once |

A turn is said as it starts ("Turning from 120 to 285 degrees, west")
and when it's over: "Rotor at 285 degrees, west", or, if the rotor
stops short or stalls, where it stopped. Each turn is listed in Window >
Activity too. The rotor only turns when you choose one of these
commands; nothing turns it by itself. A contact you log while a rotor is
set up gets the antenna's heading in Antenna azimuth (ADIF's ANT_AZ),
if you haven't filled that in.

### WSJT-X decodes

**Window > WSJT-X Decodes** (Command-4) shows what WSJT-X is decoding,
newest first, one line each, so VoiceOver reads a whole decode at once:

- "W1AW calling CQ, United States, grid FN31, -12 dB, 14:30:15, new
  country"
- "To you, from K1ABC: -08, -15 dB, 14:30:30" (a station calling you is
  also said aloud, wherever you are)
- "K1ABC to W1AW: RR73, -3 dB, 14:30:45"

WSJT-X runs as usual and does the decoding; you rarely need its window.
Each line says the station's country, and whether it's a new country,
band or mode for you, or worked before. Tab reaches the filters: **CQs
only**, **Needed only** and **Hide stations worked before**, then
**Refresh**. The status line above the list says WSJT-X's frequency and
mode, and whether it's transmitting.

On a busy band FT8 brings 20 or more decodes every 15 seconds. If that's
too fast to follow, **Refresh** shows new decodes every 15, 30 or 45
seconds or every minute instead of as they arrive (Live). A station
calling you is still said the moment it's decoded, and a filter you
change, or WSJT-X clearing its decodes, shows at once. The choice is
remembered.

Solid Copy listens for WSJT-X while the window is open (or all the
time: see below), at 127.0.0.1 port 2237, which is what WSJT-X sends to unless you've changed it
(WSJT-X's Settings > Reporting, UDP Server). Only one program can listen
there; if another has the port, the window says so.

If the status line names WSJT-X but no decodes come, WSJT-X isn't
decoding, which its own window shows by an empty Band Activity:

- WSJT-X's **Monitor** (VoiceOver calls it a checkbox) must be on. Its
  Settings > General > **Monitor off at startup** leaves it off each
  time WSJT-X opens.
- The radio's audio to the Mac must not be too loud: on the TS-590SG,
  menu 72 (USB audio output level) at 5 clipped; 2 worked.
- If WSJT-X still decodes nothing, quit it fully (Option-Command-Escape
  to force it if needed) and open it again.

While WSJT-X is running (and this window is open), a contact you log
with the radio in a data mode (the TS-590's USB-D, say) gets WSJT-X's
mode: FT8, or FT4 (ADIF mode MFSK, submode FT4) and so on. The radio
alone can only say "data", not which digital mode.

**Return** on a decode answers that station: WSJT-X calls it, exactly
as if you'd double-clicked the decode in WSJT-X's own window, and runs
its usual sequence of messages. Solid Copy then says "WSJT-X is calling
W1AW", or, if WSJT-X didn't take it, what to check. **Stop
Transmitting** (Command-period, while this window is in front) stops
WSJT-X at once. For both, WSJT-X's **Settings > Reporting > Accept UDP
requests** must be on.

Transmitting goes through your radio setup as usual: with Solid Copy
sharing the radio, **Let them transmit** must be on (Settings > Radio),
and WSJT-X's own Enable Tx decides whether it actually transmits.

**Contacts you log in WSJT-X** (its Log QSO window, or automatically, if
you've set it to) go straight into the Solid Copy log that's open: call,
grid, reports, band, frequency, mode and times, as WSJT-X sent them, with
your profile's rig, county and so on filling in what WSJT-X doesn't know,
and the name and QTH from your callsign lookup. Solid Copy says "Logged
KJ5IUY from WSJT-X", even with WSJT-X in front, and the contact uploads
like any other (never from a test log). One already in the log isn't
added again. This works while the WSJT-X Decodes window is open, or
all the time with the setting below; WSJT-X keeps its own log too
(wsjtx_log.adi), which File > Import… reads if a contact was missed.

**Listening in the background.** Settings > Radio, **Listen for WSJT-X
all the time**: Solid Copy listens from the moment it opens, so every
contact you log in WSJT-X goes into the open log, with the decodes
window closed. Only the contacts WSJT-X logs are added, never its
decodes. With it, **Alert me with the decodes window closed** (on unless
you turn it off) tells you, with the needed sound:

- a station calling you: "K1ABC is calling you in WSJT-X: FN42";
- a needed station: "Needed: VP8ABC, Falkland Islands, new country, 20
  meters" (a new country, or one new on this band or in data modes, in
  the open log). A decode carries a grid, not a state, so a needed state
  can't be told from one. Each needed station is told once per band an
  hour, and what one FT8 period brings comes together.

With Solid Copy in front VoiceOver says it; with another app in front
(WSJT-X, say) it's a Mac notification, which VoiceOver reads. macOS asks
once to allow Solid Copy's notifications (System Settings >
Notifications > Solid Copy changes it later). Window > Activity lists
every alert. With the decodes window open, the window does the telling,
as before.

## Choosing the form and the columns

**Settings > Logging Form** (Command-comma, then Command-3) lists every
field you can put on the profile in use's form after Callsign; the
Starting value field below it sets what the selected field starts as.
**Settings > Log Columns** (Command-4) lists the log's columns. In the
log, VoiceOver says each cell with its own column's heading ("Country,
United States"), however far along the row it is: the table gives
VoiceOver its headings, so they stay right when the row scrolls
sideways. End dates and times read as the Date and Time columns do
(2026-11-22, 1949), not as ADIF's raw numbers.

In either list, Space
shows or hides the selected item, which stays where it is, and
Option-Command-Up and Down move it past the next item in use. QSL
statuses and dates (cards, LoTW, eQSL, QRZ Logbook) aren't offered for
the form, since nobody knows them while logging: the QSL menu, syncing
and Edit Contact set them.
On the form, a field can be on screen without being a Tab stop: Make Tab
Stop and Remove Tab Stop are in the Actions rotor (VO-Command-Space) and
the shortcut menu. Name starts as not a Tab stop, because lookups fill it
in. Changes show at once. Drag a column heading to change the order; Solid Copy
remembers it.

## Building

You need Xcode and XcodeGen (`brew install xcodegen`), and your Apple
Developer team ID in a file named `team.txt` in this folder. From the
folder you cloned (or downloaded) Solid Copy into:

```bash
bash build.sh install
```

If you have a Developer ID certificate for that team, the installed copy
is signed with it, like the downloads, so switching between a copy you
built and a downloaded one doesn't ask for your password to read your
saved logins. Without one, the build keeps its own development signature.

That builds the app, quits Solid Copy if it's open, and installs it as
`/Applications/Solid Copy.app`. It doesn't open it: open it yourself from
the Dock or Spotlight, so it comes up in front and never takes focus
while you're typing somewhere else.

## Dupes, countries and "needed"

When you leave Callsign:

- **Dupes.** The same call on the same band and mode today (CW, phone
  and data counted as one mode each) gets a warning, with the warning
  sound, before the lookup: "Dupe: W 1 A W already worked today on 20
  meters CW at 14:32 UTC." You can still log it. In a contest log the
  contest's rule is used instead, and on a park activation the park's.
- **Country and needed.** The call's country (DXCC entity) comes from
  cty.dat, the country list nearly every logger uses (fetched monthly).
  If you need it, you hear it with the lookup: "needed: new country",
  "new band" or "new mode", counted from the log that's open. The
  country is said on its own when the lookup gives no place, and it goes
  in the contact's Country when the lookup doesn't fill it.

## Band plan

**Settings > Band Plan** has your **license class** and the **band plan**
(the United States one, from the FCC's Part 97 rules as amended in
January 2026, to start). **Window > Band Plan** (Command-6) shows it as a
list, low to high, one line each:

```
14.000 to 14.025 MHz, 20 meters: CW and data. Extra only.
14.074 MHz, 20 meters: FT8.
14.150 to 14.175 MHz, 20 meters: CW, phone and image. Extra only.
```

- **Band**, **Class** and **Mode** narrow it. Class starts on your
  license class, and then shows only the segments yours may use, and the
  activities inside them.
- Activities are where things usually happen (FT8 and FT4, QRP and SKCC
  frequencies, the NCDXF beacons, SSTV, calling frequencies); they give
  no privileges.
- The line above the list says where the radio is: "Radio: 14.074 MHz:
  CW and data for Extra. FT8." The line for it is selected when the
  window opens. The same line ends with the warning's setting ("Warnings
  for Extra (Settings > Band Plan)", or "No warnings: choose your license
  class in Settings > Band Plan"): the window's Class pop-up only narrows
  the list.
- **Return** tunes the radio there: an activity's frequency, or 5 kHz
  into a segment (never its edge). Escape goes back to logging.

**The out-of-band warning.** With a license class chosen and **Warn when
the radio is outside my privileges** on, Solid Copy plays the warning
sound and says so when the radio settles somewhere that isn't yours:
"Outside your Extra privileges: 14.352 MHz. Nearest: 14.225 to 14.350",
or "Phone isn't allowed at 14.100 MHz for Extra; here it's CW and data.
Phone: 14.150 to 14.350". It waits until the radio has stayed there 1.5
seconds, says it once, and is quiet far from any band (broadcast
listening). While WSJT-X is working, the radio counts as in a data mode
even in plain USB. It's about where the radio is: Solid Copy can't tell
listening from transmitting. Window > Activity lists each warning.

**A frequency typed in Callsign gets the usual mode there** (Settings >
Radio, on to start): CW where phone isn't allowed, SSB on the usual
sideband where it is (LSB below 10 MHz, USB above and on 60 meters), data
on FT8 and FT4 frequencies, and FM on FM calling frequencies. On 160
meters, where every mode is allowed, CW is the custom below 1.843 MHz.
Already in a data mode where data is allowed, the radio stays in it.
Above 6 meters, where FM and SSB share the bands, the mode is left as it
is. To choose the mode yourself, type it with the frequency: "14.050 CW".

**Other countries.** A band plan is a text file in the Band Plans folder
(Settings > Band Plan > **Show Band Plan Files**, with a README on the
format), so another country's plan can be added as a file, and it's then
in the Band plan pop-up. There's no official list to download them from,
so Solid Copy comes with the United States plan.

## Awards

**Window > Awards** (Command-5) shows how far your log is towards these
awards, one line each:

- **DXCC** (ARRL): countries. 100 confirmed earns it.
- **WAS** (ARRL): the 50 US states. DC counts as Maryland, so it isn't
  listed.
- **WAZ** (CQ): the 40 CQ zones.
- **WPX** (CQ): different callsign prefixes. 400 earns it for mixed
  modes, 300 for one mode.
- **SKCC Centurion, Tribune and Senator** (Straight Key Century Club):
  members worked on CW (below).
- **POTA Hunter** (Parks on the Air): different parks worked (below).

For example: "WAS: 38 states worked, 31 confirmed, 19 more confirmed for
the award." Only contacts confirmed by LoTW or a paper card count as
confirmed, as ARRL and CQ count them; eQSL and QRZ Logbook confirmations
don't.

Return goes from an award to its list, one line per country, state,
zone or prefix: "Utah: not worked", "Texas: worked, not confirmed, 2
contacts", "Ohio: confirmed by LoTW, 5 contacts". Tab moves to Band (all
bands, or one), Mode (mixed, CW, phone or digital) and Show (still
needed, worked but not confirmed, not worked, confirmed, or all), then
to the list. Escape goes back to the logging window. The counts change
as you log, and your choices are remembered.

Where each contact counts comes from, best first: what LoTW sent with
its confirmation (see LoTW, below), then the state, CQ zone and WPX
prefix in the contact (from a lookup or typed), then the call itself.
A call's zone is only worked out from its country when the whole
country is one zone, so a US contact with no CQ zone isn't counted for
WAZ until it has one.

### SKCC awards

The SKCC awards count members, and need no QSL. They use SKCC's member
list (turn on SKCC numbers in Settings > Clubs), which says when each
member joined and reached each level, and your callsign from Settings >
Profiles. A member counts if the contact was made by SKCC's rules on
that day:

- **Centurion:** 100 different members, both of you members that day.
- **Tribune:** 50 different Centurions, Tribunes or Senators, worked
  once you were a Centurion and they were too. Tx2 is 100, Tx3 150, and
  so on.
- **Senator:** once you're Tribune x8, 200 different Tribunes or
  Senators worked after your Tx8 day.

For example: "SKCC Tribune: 120 members count, enough for Tx2; 30 more
for Tx3." Each member counts once, by SKCC number, and only CW contacts
count (the log doesn't know your key, so a straight key, bug or cootie
is taken on trust). The member's number comes from the contact's SKCC
number, or the member list by call. In the list, a member that doesn't
count says why: "W1XYZ, SKCC 2345: doesn't count, you weren't a
Centurion yet, 1 contact". In Show, Confirmed is the members that
count and Still needed the ones that don't. Members who have since
become silent keys still count.

### POTA Hunter

POTA Hunter counts the different parks you've worked, on any band or
mode, towards POTA's levels: Bronze 10, Silver 20, Gold 30, Platinum 40,
Diamond 50, Sapphire 75, then every 100 parks to 1000, then 1500 and
2000. For example: "POTA Hunter: 63 parks worked, enough for Diamond; 12
more for Sapphire." Its list has each park, named from POTA's park list:
"US-1333, Big Pocono State Park, Pennsylvania: worked, 3 contacts".

The parks come from each contact's park (POTA_REF, or SIG POTA with its
SIG_INFO). A two-fer counts each park, and an old US reference such as
K-1333 counts as POTA's US-1333. This is your own count: pota.app gives
hunters credit from the activators' uploaded logs, so its count is the
official one, and a park may not show there until the activator
uploads.

## Callsign lookups

Open **Solid Copy > Settings…** (Command-comma), enter your QRZ.com
username and password, and press **Save and Test**. The password is kept
in the Keychain. A free QRZ account gives only a few fields (mostly the
name); a paid XML subscription gives everything. callook.info, free and
with no account, can fill in US calls. Settings also has your own
callsign and grid square, added to each new contact.

When you leave the Callsign field, the call is looked up. The result is
shown under the form and spoken once, for example "W 1 A W, Hiram,
Newington Connecticut, 282 miles north-east, worked 3 times before."
Focus doesn't move.

**Distance and bearing** come from the grid square in your profile (My
grid square, Settings > Profiles) to the station's position from the
lookup (its latitude and longitude, or its grid). The line also gives the
bearing in degrees, for pointing an antenna ("282 miles, 53 degrees
north-east"). Miles or kilometres follows your Mac's region setting. Each
contact keeps the distance in kilometres (ADIF's DISTANCE).

## Club numbers

SKCC, FISTS, LICW and CWops numbers each have a field, and so do up to
five other clubs you add (**Settings > Clubs**: name them, such as "NAQCC
number"). Put the ones you use on the form in Settings > Logging Form.
These fields hold the other station's number. A club field named for a
club that's built in (SKCC, FISTS, LICW, CWops) isn't used, since it
would put that club in the lists twice. Your own numbers go in Exchange
sent (Settings > Logging Form) or on your QSL card (Settings > QSL Card).

When you leave Callsign, empty club fields are filled in, and the
numbers are said with the lookup ("..., SKCC 12345 Tribune, worked
twice before"):

- **SKCC** from SKCC's own member list. Solid Copy keeps a copy (about
  2 MB, fetched again each week; Settings > Clubs has Fetch SKCC List
  Now). It's the authority, so a member's newest award letter (C
  Centurion, T Tribune, S Senator) is the one logged.
- **Everything else** from your log: the last contact with the same call
  that has the number. FISTS and LICW publish no member lists, so this is
  how they're filled: log a regular's number once, and it's there next
  time.

**Checking a copied number.** An SKCC number you type is checked against
the call when you leave the field (or leave Callsign, if you typed the
number first). If it belongs to someone else, you hear the warning sound
and whose number it is: "SKCC 12345 is W 1 A B C. W 1 A B D isn't in
SKCC's list." One of the two was miscopied, and a lookup alone can't
tell you, because a miscopied call is often a real call. You can still
log it as it is; SKCC's list may be a few days behind.

## QSLs

A QSL is the other station's confirmation of a contact: a paper card,
or LoTW, eQSL or QRZ Logbook. The details panel (Tab in the log) says it
in one line, right after the time: "QSL: Confirmed: card 17 December
2025, LoTW 23 April 2022. Uploaded to QRZ Logbook." Each QSL field below
it is in words ("Card received: Yes", not "Y").

The **QSL** menu works on the contacts selected in the log (and the
log's shortcut menu, VO-Shift-M, has the same marks):

- **Card Requested**: they asked you for a card.
- **Card Sent** (Shift-Command-S): dated today. A request becomes sent.
- **Card Received** (Shift-Command-R): dated today.
- **Show Confirmed**, **Show Not Confirmed**, **Show Card Requests**:
  narrow the log. Escape shows the whole log again.

A mark on contacts that all have it already takes it off, and Command-Z
undoes any of them. Select several contacts (Shift-Up, Shift-Down) to
mark them all at once.

Importing a log file in the SQL format keeps cards received ("CardC"), LoTW and QRZ
Logbook confirmations, and QRZ Logbook uploads.

### Scanned cards

**QSL > Attach Cards from a Folder…** takes a folder of scanned cards
(PDFs or pictures), each named by callsign ("W1AW.pdf"; "W1AW 2.pdf"
for a second one), and attaches each to its contact. A call with
several contacts gets the card only if just one of them is already
marked card received; otherwise the summary lists it, so you can choose
the contact yourself. Cards are copied into a QSL Cards folder beside
the log, so the folder you chose can be moved or deleted afterwards, and
each card counts as received. The text of a searchable scan is kept with
the contact, so Command-F finds words on a card ("Pottawatomie"). Edit >
Undo takes the whole lot back off.

For the contact selected in the log:

- **Open Card** (Shift-Command-O): opens it in Preview, where VoiceOver
  reads the scan's text. Also in the log's shortcut menu.
- **Attach Card…**: one card, for a contact the folder couldn't match.
- **Remove Card**: takes it off (still counted as received).

What the other operator wrote on their card goes in **Their card's
message**, in Edit Contact (Return on a contact).

### Your electronic QSL card

**QSL > Send QSL Card** (Shift-Command-K, also in the log's shortcut
menu) makes your QSL card for the selected contact. It's a PDF the size
of a paper card (5.5 by 3.5 inches), with real text VoiceOver reads in
Preview, and it prints. It's saved in a Sent Cards folder beside the log
and attached to a new Mail message, addressed to them if the log has
their email. The message also holds the card's text, for anyone whose
mail can't show the PDF. Check it and send it yourself. Once Mail has the
card, the contact is marked Card sent, by electronic means, dated today;
Edit > Undo takes the mark back. A contact already marked sent (a paper
card) keeps its mark.

Set the card up in **Settings > QSL Card** (or **QSL > QSL Card
Settings…**):

- **Fields on the card**: which, and in what order, in the same kind of
  list as Logging Form (Space shows or hides; Option-Command-Up and Down
  move). Yours, such as your grid square, go at the top with your
  details; the rest describe the contact, read as one paragraph:
  "Date: 14 November 2026. Time: 14:32 UTC. Band: 40m. ..."
- **Your name**, **Your town or QTH**, **Another line**: up to three
  lines under your call, such as your club numbers.
- **Message, when the contact has none**: the contact's QSL message is
  used if it has one.
- **Picture**: one picture behind the text (a straight key, your shack),
  kept faint so the text stays clear, and **What the picture shows**, a
  description that's the picture's alternative text in the PDF and the
  card's last line. No picture of your own? **Use the J-38 Picture**
  puts Solid Copy's photo of a J-38 straight key there, described for
  you. It's public domain (photo by Lou Sander; see docs/CREDITS.md), so
  cards need no credit line.
- **Show Sample Card**: a card for a made-up contact, opened in Preview,
  so you can hear and see the result without sending anything.

The card is one column, read top to bottom: your call, your lines, "To
Hiram, W1AW", the contact, the message, "73". If the fields you choose
don't fit, the text gets smaller, then the card gets taller; nothing is
ever cut off.

### LoTW

**QSL > Sync with LoTW** (Shift-Command-L) uploads the contacts LoTW
doesn't have yet, then gets your new confirmations, saying each step as
it starts and ending with a summary. Set it up in **Settings > Uploads**,
under Logbook of the World:

- **LoTW username and password**: your LoTW website login, for
  confirmations. The password is kept in the Keychain.
- **TQSL station location**: the name of the location in TQSL to sign
  with, exactly as TQSL shows it ("Anytown, N0CALL").
- **Upload contacts from**: a day like 2020-01-01, or empty for every
  contact.
- **Upload automatically**: see [Automatic uploads](#automatic-uploads).
- **Choose Folder for TQSL…**: a folder (a new one in Documents is
  fine) where Solid Copy leaves the contacts for TQSL and TQSL leaves its
  log. Solid Copy is sandboxed, so it needs a folder you chose.
- **Install TQSL Script…**: once. A Save dialog opens in the one folder
  macOS lets a sandboxed app run scripts from; press Save. The script
  (two lines) only starts TQSL with what Solid Copy passes it. Delete it
  from that folder to stop.

Uploads need TQSL (the ARRL's TrustedQSL) installed with your callsign
certificate. TQSL signs and sends; it skips anything LoTW already has,
so nothing is sent twice. If your certificate has a passphrase, TQSL asks
for it in its own window; if TQSL can't unlock the certificate, the
summary says so and nothing is marked uploaded. Contacts TQSL won't sign
(a band that isn't a band, say) are left unmarked, with TQSL's reason.
Confirmations are matched to contacts by call and band, within 30
minutes; any that match nothing in your log are listed.

Each confirmation also brings where the other station was, from the
location they signed with in TQSL: their state, county, CQ and ITU
zones, DXCC entity, WPX prefix and IOTA island. These are what LoTW gives
award credit for, so they replace what a callsign lookup filled in (a
lookup gives where someone lives today, which may not be where they
operated from). The first sync after updating Solid Copy gets all your
confirmations again, once, so older ones get these details too; it can
take a minute.

### QRZ Logbook

**QSL > Sync with QRZ Logbook** (Shift-Command-U) sends the contacts
your QRZ logbook doesn't have yet, one at a time, and marks each one QRZ
has as uploaded (Uploaded to QRZ Logbook, with the day). Then it gets
the contacts QRZ says are confirmed and marks them in your log (QRZ
Logbook confirmed, with the day), matched as LoTW's are: the same call
and band, within 30 minutes. Any that match nothing in this log are
listed. It needs a QRZ subscription. Set it up in **Settings > Uploads**, under QRZ Logbook.
**QSL > QRZ Logbook API Key…** goes straight to the key field (and
Sync with QRZ Logbook takes you there itself if no key is saved yet);
paste the key and press Return. **QSL > Upload Settings…** opens the
whole Uploads section.

- **API key**: your logbook's key. On qrz.com, open your logbook, then
  its Settings; copy the key and paste it here. It's kept in the
  Keychain.
- **Upload contacts from** and **Upload automatically**, as for LoTW.

A contact QRZ already has counts as uploaded. One QRZ refuses (a date
outside the logbook's, or a station callsign that isn't the logbook's)
is listed with QRZ's reason and left unmarked. If the internet is down,
or the key isn't allowed, it stops and says so. Notes and card scans
aren't sent.

### Club Log

**QSL > Upload to Club Log** sends the contacts Club Log doesn't have
yet, about one a second (Club Log allows 60 a minute), and marks each
one it has (Uploaded to Club Log, with the day). Set it up in **Settings >
Uploads**, under Club Log; **QSL > Club Log Token…** goes straight to the
token field.

- **Token**: on clublog.org, open Settings, then the API tab. Give the
  token a label (Solid Copy), leave Test mode unticked, and choose
  Create token. Copy it at once (Club Log shows it only once), paste it
  here, and press Return. It's kept in the Keychain.
- **Upload contacts from** and **Upload automatically**, as for LoTW.

Each contact goes under its own My callsign (or your profile's, if it has
none), which must be on the token's Club Log account. A contact Club Log
refuses is listed with Club Log's reason. A token Club Log doesn't
accept, or a callsign not on its account, stops the upload at once: Club
Log can block your internet address for a while if a program keeps
sending a failing request. The message names the callsign that was sent,
so you can tell whether My callsign is wrong or Club Log's account is
missing it (on clublog.org, the account's callsigns are under Settings).

### eQSL

**QSL > Upload to eQSL** sends the contacts eQSL doesn't have yet, one a
second, and marks each one it has (Uploaded to eQSL, with the day). Your
card's message is the contact's QSL message. Set it up in **Settings >
Uploads**, under eQSL; **QSL > eQSL Login…** goes straight there.

- **Username** and **Password**: your eQSL login (the username is
  usually your callsign). The password is kept in the Keychain.
- **QTH Nickname**: only if you have more than one eQSL account under
  the same callsign. Type the nickname of the one to use, as your eQSL
  profile names it.
- **Upload contacts from** and **Upload automatically**, as for LoTW.

A contact eQSL refuses (a mode it doesn't take, no band, a date your
account doesn't cover) is listed in plain words. A wrong login stops the
upload.

### Uploading just some contacts

In the log, the shortcut menu (VO-Shift-M, or Control-click) has
**Upload to LoTW**, **Upload to QRZ Logbook**, **Upload to Club Log** and
**Upload to eQSL**: just the selected
contacts, now, even ones already sent (you chose them). It says how it
went.

### Reading or copying an upload message again

Every message window (an upload, an import, an export) has a **Copy**
button after OK: Tab to it and press Space, and the whole message is on
the clipboard, ready to paste into an email or a note.

An automatic upload, or one from the log's shortcut menu, only speaks
its message. **QSL > Show Last Upload Message** shows the last upload or
sync message again in a window you can read word by word, with Copy.

### Automatic uploads

Each service's **Upload automatically** (Settings > Uploads) is one of:

- **By hand** (the starting choice): only when you ask.
- **Soon after each contact**: half a minute after you log it, so the
  lookup has filled it in and a quick correction goes with it.
- **Five minutes after the last contact**: a run of contacts goes up
  together, with any corrections. Best for LoTW, which can't change a
  contact once it has it.

Only contacts you log on the form while Solid Copy is open go up this
way; older ones and imports wait for Sync or Upload. When it works you
hear nothing, so logging isn't interrupted. A problem is said once, with
the warning sound. Without internet, the contacts wait and go with the
next contact, or ten minutes later. Quitting while contacts wait is
fine: they go half a minute after you next open Solid Copy.

## CW through a WinKeyer

Solid Copy can send CW through a K1EL WinKeyer (tested with a WinKeyer
Mini). Set it up in **Settings > CW** (the last section): the WinKeyer's
port, the speed, your name, and the eight messages.

- **CW > Connect WinKeyer** opens it. Only one app can have the
  WinKeyer at a time, so quit any other app using it first; if one has
  it, you hear so. Solid Copy never connects by itself, and lets go when it
  quits (the WinKeyer goes back to its own settings).
- **F1 to F8** send the messages. The CW menu lists each one, so reading
  the menu reminds you what each key sends.
- **Escape** stops CW that's being sent. When nothing is sending, Escape
  clears the form as always.
- **Control-Command-= and -** (Keyer Faster and Slower) change the
  WinKeyer's speed while it's connected, instead of the radio's keyer.

Each profile has its own messages: Settings > CW edits the ones for the
profile in use. A profile made from the **Field Day** template starts
with Field Day's (F1 CQ FD, F2 their call and your class and section,
F3 TU and your call, and so on).

Messages can use fill-ins: {MYCALL}, {MYNAME}, {MYSTATE} are yours;
{NR} is your serial number for this contact (see Serial numbers); {SENT} is your exchange, from Exchange sent on the form (Field
Day's class and section, "1D MDC"); {CALL}, {NAME}, {STATE}, {SKCC} are theirs, from the form (or the
lookup and SKCC's list); {RST} is the report you're sending, or 599. One
with nothing to fill it is left out. F1 starts as CQ, F2 as an exchange
(their call, RST, your name and state), F3 as TU and your call; change
any of them. (SKCC's own events require a mechanical key,
so keyer messages aren't for those.)

Sending CW keys your radio. Try new messages with the WinKeyer
unplugged from the radio, or into a dummy load.

## Contests

Contests are plain text files in Solid Copy's Contests folder (**File >
Contests > Show Contest Files** opens it, with a README explaining the format). A
change to a file, or a new file, works at once, with no new version of
Solid Copy. ARRL Field Day's file and SKCC's events are there to start:

```
name: ARRL Field Day
id: ARRL-FIELD-DAY
exchange: class and section
serial: no
dupes: band and mode
messages: CQ FD {MYCALL} {MYCALL} FD | {CALL} {SENT} | TU {MYCALL} FD | ...
submit: dupe sheet
```

Only name and id are needed. **exchange** lists what they send (name,
state, county, rst, zone, grid, skcc, member and others, or any field's
ADIF name); **serial: yes** adds Serial sent and received; **dupes** is
once, band, or band and mode (modes grouped as CW, phone and digital);
**messages** are the CW messages, split by |; **submit: dupe sheet**
offers Field Day's dupe sheet in File > Export….

### Scores, and SKCC's events

A contest file can say how it's scored, and then **File > Contests >
Contest Score…** shows the open contest log's totals (with a Copy
button), and **Speech > Say Contest Score** (Option-Command-C) says
them: "SKCC Sprint: 7 contacts (1 dupe not counted). 5 multipliers. 1
Centurion, 5 points. 1 Tribune, 10 points. 2 Senators, 30 points. NX1K:
2 bands, 50 points. Score 130." The lines, all optional:

```
points: 1                          each contact that isn't a dupe
multipliers: spc                   different values of a field multiply
skcc bonus: C 5, T 10, S 15        once per station, by their SKCC letter
bonus station: KS1KCC 25 per band  or "25 once"; commas for more
grid bonus: 5                      each different 4-character grid
name bonus: /BD 30                 each station whose name ends /BD
```

The score is points times multipliers (just the points without a
multipliers line), plus the bonuses. A call signing /4 or /P is the
same station for the bonuses.

Solid Copy comes with files for SKCC's regular events: **SKCC Sprint**
(SKS), **Sprint Europe** (SKSE), **Asia Sprint** (SKSA), **Weekend
Sprintathon** (WES), the **QSO Party** and the **Slow Speed Saunter**.
Each file's comments give its times, rules and where to submit. They're
added to your Contests folder once: if you delete or change one, it's
left that way. SKCC asks for your totals in a web form rather than a
log, and Contest Score… gives you those totals in the form's order.

- The exchange is RST sent and received, SPC (state, province, or the
  country's code outside the US and Canada), name and SKCC number. A
  lookup fills in the state and name, and the SKCC member list the
  number with its C, T or S, so often you only type the RST.
- Put your own exchange in Exchange sent on the profile: "PA SAM 12345T".
- SKCC's events are for a straight key, bug or sideswiper, so their
  files have no CW messages for the keyer.
- The SKS special station changes every month: edit **bonus station**
  in "SKCC Sprint.txt" before each sprint. WES's monthly theme bonus is
  yours to add, as SKCC asks.
- Start a log for each event (File > New Log > New Contest Log…): the
  score counts every contact in the log.

- **File > New Log > New Contest Log…** offers each contest file, and "Other: use
  a profile" for a contest with no file. A contest log comes with a
  profile built from the file (its form and messages), brings it back
  whenever it's opened, and warns of dupes by the contest's rule over
  the whole log.
- **File > Contests > Save Profile as Contest…** writes the profile in use as a
  contest file: a contest set up by hand, kept or shared.
- **File > Export…, Dupe sheet** lists the calls worked by band and
  mode, headed with the contest and your call: what ARRL asks for with
  a Field Day entry. (ARRL treats a Cabrillo log as optional for Field
  Day and publishes no Field Day layout, so there's none yet.)

## Serial numbers

Put **Serial sent** on a profile's form (Settings > Logging Form) and it
counts itself: a fresh form shows the next number, 1 more than the
highest logged in this log for the same contest (the form's Contest).
Each log and contest has its own count, and it stays right after a
deleted contact or a correction. Type over it to change it. Logging
says the number ("Logged W 1 A W, number 12"; "Logged, 12" when
logging speech is brief). Put
**Serial received** on the form for theirs. CW messages can send the
number as {NR}; it's logged as Serial sent even if that field isn't on
the form. None of this needs the keyer.

## Logs

The File menu keeps everything about logs together at the top: **New
Log** (a submenu: New Log…, New Contest Log…, New Test Log…), **Open
Log** (a submenu of every log), **Delete This Log…** and **Show Log in
Finder**. Then Import…, Export… and Back Up Now; then **Contests** (a
submenu: Contest Score…, Show Contest Files, Save Profile as Contest…); then Save
Contact and Close Window.

Solid Copy starts with one log, the **main log**. You can make more:

- **File > New Log > New Log…** (Command-N): a log of its own, for a special event or a
  contest kept apart from everyday contacts. It uploads like the main
  log.
- **File > New Log > New Contest Log…**: a log for one contest (ARRL Field Day
  or one of SKCC's events, or one of your own files), with that contest's profile: its form and CW messages. If you
  have no profile for it yet, one is made from the contest's template.
  Opening the log always brings that profile back.
- **File > New Log > New Test Log…** (Shift-Command-N): for trying layouts, simulating a contest and
  so on. Nothing in a test log is ever uploaded, by hand or
  automatically, and its backups stay on this Mac.
- **File > Open Log**: every log, the open one ticked. Choosing one
  switches to it and says which log is open and how many contacts it
  has. The window title always names the open log ("Solid Copy, Main
  log, Home").
- **File > Delete This Log…** (any log but the main one): after asking,
  with how many contacts it has, moves the log, its backups and cards to
  the Trash and opens the main log. Anything already uploaded stays on
  LoTW and QRZ. The main log can't be deleted from the menu, on purpose:
  it's your real logbook. To empty it, select all in its log
  (Command-A) and press Delete (Command-Z undoes it). To remove it
  altogether, quit Solid Copy, use File > Show Log in Finder first to
  find its folder, and move Logbook.sqlite to the Trash (leave the Logs
  folder: it holds your other logs); the next launch starts an empty
  main log. Backups, beside the log and in your backup folder, are kept.

**Copying contacts between logs:** select contacts in the log (Shift-Up
and Shift-Down select several), press Command-C, open the other log,
move into its log and press Command-V. Every field comes across, Notes
too; contacts already in that log are skipped, and Command-Z takes the
paste back out. A scanned card stays with the log it was attached in.
The copy is ordinary ADIF text, so ADIF copied from elsewhere pastes too.
Command-V with contacts on the clipboard pastes them into the open log
from the form too (Callsign or any field), leaving the field as it was,
so there's no need to move into the log, even an empty one.

Each log remembers the profile last used with it, and opening the log
brings that profile back, with its form and CW messages: a "Field Day
2027" log comes back with your Field Day profile, and the main log with
Home. You hear the profile with the log's name.

Each log has its own contacts, backups and scanned cards. Profiles,
radios, lookups and your logins are shared by all of them. Switching
needs an empty form, so a contact you're typing is never lost: log it
or press Escape first. Solid Copy opens the log you had open when you
quit.

## Backups

Solid Copy backs up the log each time it opens, and before imports,
keeping the newest 20 beside the log (File > Show Log in Finder). Those
go if the Mac or its drive does, so choose a second folder in
**Settings > Backups** (the last section in the sidebar): **Choose Backup
Folder…** opens the usual Open dialog, where iCloud Drive is in the
sidebar and New Folder makes one.

A copy then goes there when Solid Copy opens; while it's open, on the
schedule in Settings > Backups (**Every 4 hours** to start, or every hour,
once a day, or never); when it quits; and with **File > Back Up Now**.
The schedule and quitting only back up if the log changed. They also
back up beside the log when no folder is chosen.
The newest 20 are kept there as "Solid Copy log 2026-11-16
143205Z.sqlite", with your scanned cards in a QSL Cards folder. You hear
nothing when it works; a problem is said with the warning sound (one at
quit is said the next time you open Solid Copy).

To restore: quit Solid Copy, then copy a backup over Logbook.sqlite in
the folder File > Show Log in Finder opens, renaming it Logbook.sqlite.

## Importing and exporting

**File > Import…** (Shift-Command-I) reads ADIF files (.adi, .adif), ADX files (.adx, ADIF
written as XML) and log files in the SQL format (.sql). It works out which
from the file itself. The file is only read, never changed. Solid Copy
backs up its own log first, skips contacts it already has, and Edit >
Undo takes the import back out.

**File > Export…** (Shift-Command-E) saves the whole log as ADIF, as ADX
or as a CSV spreadsheet. ADIF and ADX carry exactly the same fields; use
whichever the other program or service asks for. Notes are private, so they're left out unless you tick
Include QSO notes.

To check importing and exporting without changing your Solid Copy log,
run `tools/check-import-export.sh` (see Checks).

## Checks

For anyone changing the code. Each area has its own check; run the ones
for what you changed, from the folder you cloned Solid Copy into, such
as `bash tools/check-uploads.sh`. Every line should start with PASS. None
of them touch your Solid Copy log.

- `tools/check-log-database.sh`: the log file
- `tools/check-import-export.sh`: ADIF, ADX, CSV and SQL log file
  import and export, against a log file in the SQL format that you
  have (only read, never changed). Give its path.
- `tools/check-lookups.sh`: callsign lookups (add `--live` to also try
  callook.info)
- `tools/check-log-table.sh`: the log table
- `tools/check-profiles.sh`: operating profiles
- `tools/check-radio.sh`: the radio
- `tools/check-wsjtx.sh`: reading WSJT-X's decodes (no WSJT-X needed)
- `tools/check-rigctl.sh`: sharing the radio with other programs, with
  hamlib's rigctl as the other program (needs `brew install hamlib`)
- `tools/check-parks.sh`: parks
- `tools/check-awards.sh`: counting DXCC, WAS, WAZ and WPX
- `tools/check-rotor.sh`: rotor control, against a pretend rotctld (`--live` adds hamlib's dummy rotor)
- `tools/check-spots.sh`: spots
- `tools/check-bandplan.sh`: band plans, the US privileges and the out-of-band warning
- `tools/check-conditions.sh`: band conditions (add `--live` to read
  N0NBH's real figures once)
- `tools/check-cards.sh`: scanned and electronic QSL cards
- `tools/check-lotw.sh`: LoTW
- `tools/check-cw.sh`: CW messages and what goes to the WinKeyer (no
  keyer needed; nothing is sent)
- `tools/check-uploads.sh`: QRZ Logbook, Club Log, eQSL and automatic
  uploads
- `tools/check-clubs.sh`: club numbers
- `tools/check-backups.sh`: backups
- `tools/check-distance.sh`: distance and bearing
- `tools/check-logs.sh`: separate logs and test logs
- `tools/check-activity.sh`: the Window > Activity list
- `tools/scale-check.sh 100000`: speed with a 100,000-contact log
- `audit.sh`: Apple's accessibility audit. It takes over the screen for
  about 9 minutes, so start it when you can leave the Mac alone.

## Documents

- [docs/PLAN.md](docs/PLAN.md): goals, decisions and phases
- [docs/ACCESSIBILITY-CONTRACT.md](docs/ACCESSIBILITY-CONTRACT.md): the
  rules for focus and speech the app must keep
- [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md): a guide to the code for
  beginners

## Removing it

Solid Copy keeps its files in three places. To remove it completely:

1. **The app:** in Finder, drag Solid Copy from Applications to the Trash.
2. **Your log and settings:** in Finder, choose Go > Go to Folder (Shift-Command-G)
   and paste `~/Library/Containers/io.github.scott-h5.solidcopy`. Move that
   whole folder to the Trash. It holds your logs (Logbook.sqlite, and any
   other logs), backups, QSL cards, settings, the saved member and country
   lists, and the radio log if you recorded one. Export your logs first
   (File > Export…) if you want to keep the contacts, because emptying the
   Trash can't bring them back.
3. **Passwords:** open Keychain Access, search for "Solid Copy", and delete
   the entries named "Solid Copy: …" (QRZ.com, LoTW, QRZ Logbook, Club Log,
   eQSL). Those are the logins for the services you've set up.

Your backups aren't in that folder if you chose another one under Settings >
Backups, such as a folder in iCloud Drive. Solid Copy doesn't delete them,
so remove that folder yourself if you don't want the copies.

Nothing else is left behind: Solid Copy starts no helper programs, and it
lets go of the radio's port when it quits.

## Licence

Solid Copy is licensed under the GNU General Public License, version 3
(GPL-3.0). The full text is in the LICENSE file.

Solid Copy works with radios through Hamlib's rigctld, which you run
yourself for radios the built-in driver doesn't cover. Thank you to the
Hamlib project and its contributors:
https://hamlib.github.io/ (source code at
https://github.com/Hamlib/Hamlib). docs/CREDITS.md lists everything
Solid Copy includes and its licence.
