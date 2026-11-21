# How Solid Copy Works

A guide to the code for someone new to programming. It explains what
each file does and why, and has recipes for common changes.

## The folders

- `Sources/App`: starting the app and building the menus.
  - `main.swift`: where the program begins.
  - `AppDelegate.swift`: opens the log in use and the window when the
    app launches; `install` puts a log in use (also when switching).
  - `Logs.swift`: File > New Log (New Log…, New Test Log…), Open Log, Delete This
    Log…, and switching logs safely.
  - `Backups.swift`: when backups are made and copied.
  - `MainMenu.swift`: the menu bar, written in code.
- `Sources/Activity`: the list of uploads and syncs in progress or done,
  and its window (Window > Activity). See "Window > Activity" below.
- `Sources/Keyer`: sending CW through a WinKeyer.
  - `WinKeyer.swift`: connects on request, sends text, stops, sets the
    speed; the comments list the WinKeyer commands used.
  - `SerialPort.swift`: opening a serial port and reading and writing it.
  - The CW menu is `Sources/App/CW.swift`; the messages and their
    fill-ins are `Sources/Model/CWMessages.swift`; Settings > CW is
    `Sources/Settings/CWSettingsViewController.swift`.
- `Sources/LogEntry`: the logging form.
  - `LogEntryViewController.swift`: the fields, Tab order, and what
    Return and Escape do.
  - `FormTextField.swift`: the form's fields, and the field editor that
    sends pasted contacts (ADIF) to the log instead of into a field.
  - `ClockBar.swift`: the UTC and local clocks at the top. Only UTC is
    saved in the log; ADIF times are always UTC.
- `Sources/LogTable`: the log under the form, and the details panel.
  - `ContactDetailsViewController.swift`: the details panel, one line
    per filled-in field of the selected contact.
  - `LogTableViewController.swift`: the table's columns, Delete and
    Undo, Escape, and the Delete Contact action for VoiceOver.
- `Sources/EditContact`: the Edit Contact sheet.
  - `EditContactViewController.swift`: every field of one contact,
    checking the date and time, and its keys (Return, Command-Return, Command-S,
    Escape, Tab out of Notes).
- `Sources/Import`: bringing in logs from other programs.
  - `LogImport.swift`: looks at a file to see what it is, and hands it to
    the right reader. Add new formats here.
  - `ADIFImport.swift`: reads ADIF. The comments explain the format.
  - `ADXImport.swift`: reads ADX (ADIF as XML) with Apple's XMLParser,
    then hands each record to `ADIFImport.contact`, so both formats
    follow the same rules. Refuses a DOCTYPE (how hostile XML hides
    entity bombs) and any file that isn't valid XML, rather than
    importing half of it.
  - `SQLLogImport.swift`: reads a log file in the SQL format
    (read-only) and turns each row into a contact. The comments at the
    top list how every column is mapped, and why.
- `Sources/Export`
  - `LogExport.swift`: writes ADIF, ADX and CSV. ADIF and ADX share
    one list of a contact's values (`values`), so they can't drift apart. Add new formats to
    `ExportFormat` and they appear in the Export dialog's Format menu.
- `Sources/App/ImportExport.swift`: the Import and Export dialogs and
  their summaries.
- `Sources/Radio`: the radio, through the built-in driver or a rigctld
  you run (Hamlib NET rigctl).
  - `RadioMonitor.swift`: keeps connected and never gives up; says what
    changed. The comments at the top explain each case.
  - `RadioLink.swift`: the interface both ways of reaching a radio
    share, and the failures they report (not answering, port gone,
    port in use, refused).
  - `RigctldClient.swift`: the conversation with a rigctld you run, with
    a time limit on every wait. The comments show what rigctld's replies
    look like.
  - `KenwoodClient.swift`: the built-in driver's serial conversation
    with a Kenwood or Elecraft radio's own USB port, with the same time
    limits. It asks a question, or sends changes followed by "ID;", and
    waits for the answer.
  - `KenwoodCAT.swift`: the words themselves, with no port in it: turns
    RadioControl's commands ("F 7025300", "M CW 500") into Kenwood's
    ("FA00007025300", "MD3", "FW0050"), and reads answers. Kept apart so
    `tools/radio-check` can test it with canned answers.
  - `RigctlServer.swift`: the other way round: Solid Copy answering
    rigctld's network commands at 127.0.0.1 port 4532, so iDigi or
    WSJT-X can use the radio through the built-in driver (Settings >
    Radio, "Share the radio with other programs"; "Let them transmit"
    adds PTT, with the safeguards listed in its comments). Questions are answered
    from the reading Solid Copy already has; changes go through
    RadioMonitor's queue. The comments show the protocol, recorded
    between hamlib's own rigctl and rigctld. It only knows the small
    RigctlRadio interface, so `tools/check-rigctl.sh` tests it with a
    pretend radio and hamlib's rigctl as the client.
  - `RigctlSharing.swift`: joins the server to RadioMonitor (the real
    RigctlRadio).
  - `RadioReading.swift`: frequency, band, mode and power in ADIF's
    terms, and in words.
  - `RadioSettings.swift`: one radio's settings, and the built-in
    driver's radios for the Settings menus. Settings.swift keeps your
    list and which is in use.
  - `RadioMenu.swift`: the menu items for choosing a radio, shared by
    the Radio menu and the radio pop-up.
  - `RadioControl.swift`: tuning, mode, filter, keyer, preamp,
    attenuator, AGC, noise blanker and reduction, peak filter, dual
    watch, RIT, XIT, offset, split, VFO and band commands, and what typed in Callsign counts as
    a frequency or mode.
- `Sources/LogEntry/RadioSlider.swift`: the Tuning, Offset, Power, RF gain and Squelch controls at
  the bottom of the window (Command-T, then Tab), sliders to VoiceOver.
- `Sources/Settings/RadioViewController.swift`: Settings > Radio.
- `Sources/Lookup`: callsign lookups.
  - `CallsignLookup.swift`: tries the cache, then QRZ, then
    callook.info. The cache is `LookupCache.json` next to the log.
  - `QRZClient.swift`: QRZ's XML service (log in, look up, log in again
    when the session expires) and how QRZ's fields become ADIF fields.
  - `CallookClient.swift`: callook.info, for US calls.
  - `LookupResult.swift`: what a lookup found, and the summary line.
- `Sources/Settings`: the Settings window, your saved settings, and the
  Keychain (where the QRZ password lives).
  - `SettingsWindowController.swift`: the window, a sidebar list of
    sections and a scroll area showing the chosen one. Each section's
    controls Tab round in their own loop; `spliceSidebar` puts the
    sidebar into the shown section's loop (just before its first
    control) and takes it out again when another section is shown, so
    Tab and Shift-Tab reach the list from any section.
  - `ProfilesViewController.swift`: the Profiles section. A profile (in
    `Settings.swift`) is a form plus station details; the profile in use
    supplies the form and is added to each logged contact. New Profile
    copies the one in use or starts from one of `Settings.templates`.
  - `ChoiceListViewController.swift`: the list used for Logging Form and
    Log Columns (Space, Option-Command-arrows, the Actions rotor).
  - When a form or column setting changes, `Settings` sends a
    `didChange` notice, and the form and log rebuild themselves.
- `Sources/Model`: the data, separate from the window, so an iPhone
  version could reuse it.
  - `LogField.swift`: the list of every field (ADIF name, label, group).
    The log file, details panel, Edit Contact and log columns all read it.
  - `ADIFLocation.swift`: converts latitude and longitude between
    decimal degrees and ADIF's "N043 36.250" form.
  - `QSO.swift`: one contact: the callsign and time, plus every other
    field by its ADIF name (`qso["gridsquare"]`).
  - `Database.swift`: a small, general wrapper around SQLite, the
    database built into macOS.
  - `LogDatabase.swift`: the log file's table (columns named after ADIF
    fields), saving, loading, deleting, and backups.
  - `Logbook.swift`: the list of contacts. It saves each change to the
    log file first, and only then changes the screen. The form and the table both
    "observe" it, so they update whenever it changes.
  - `Callsign.swift`: tidying, checking and speaking callsigns.
- `Sources/Accessibility`
  - `Speaker.swift`: makes VoiceOver say something. `announce` always
    speaks; `say(kind, full:, brief:, cue:)` speaks a lookup, logging or
    radio-change message at the level chosen in Settings > Speech (or
    plays its sound, in Quiet Mode or if you chose sound only).
  - `FieldLabel.swift`: a field's visible label, hidden from VoiceOver
    because the field speaks its own name. It draws its text itself,
    because an ordinary text label stays visible to VoiceOver.
- `macOS`: the app's settings for macOS (`Info.plist`) and its
  permissions (`SolidCopy.entitlements`).
- `project.yml`: describes the app for XcodeGen, which creates the Xcode
  project. Edit this, not the Xcode project.
- `build.sh`: builds and installs the app.
- `tools/check-log-database.sh`: tests the log file code on its own.
- `tools/check-profiles.sh`: old settings becoming Home, switching to
  Portable, starting values and station details on logged contacts.
- `tools/check-log-table.sh`: checks the log table on its own: contacts
  show when it opens, and narrowing to one call.
- `audit.sh` (in the main folder): Apple's accessibility audit of every
  screen, driven by `UITests/AccessibilityAuditTests.swift`. It needs
  Accessibility permission for the test runner the first time.
- `tools/scale-check.sh 100000`: fills a throwaway log with that many
  made-up contacts and times opening, searching, logging and backing up,
  with memory use. Run it after any change to how the log is read,
  searched or shown.
- `tools/check-lookups.sh`: checks the lookup code with sample QRZ and
  callook.info replies (add `--live` to ask callook.info about W1AW).
- `tools/check-import-export.sh`: imports your SQL log file into a
  throwaway log, exports it as ADIF and as ADX, imports each again, and
  checks every field of every contact comes back the same. It also feeds
  both readers damaged and hostile files.

## Where the log is kept

Solid Copy is sandboxed, so its files are in its own container folder:
`~/Library/Containers/io.github.scott-h5.solidcopy/Data/Library/Application Support/Solid Copy/`.
It holds `Logbook.sqlite` (the main log) and its `Backups` and `QSL
Cards` folders. File > Show Log in Finder opens the folder of the log in
use. Terminal usually can't read inside containers (macOS protects app
data), but Finder can.

Other logs (File > New Log…, New Test Log…) live in `Logs/<id>/`, each
with its own `Logbook.sqlite`, `Backups` and `QSL Cards`. The folder is
named by the log's ID, so its name can be anything and renaming would
move nothing. The list of logs and the one in use are in user defaults
(`Sources/Model/LogList.swift`). The main log was never moved, so
nothing changed for it when there became more than one.

## Contests and serial numbers

`Sources/Model/Contest.swift` reads contest files (`Contest.parse`: one
"key: value" per line; problems come back in words with the line) from
the Contests folder (`ContestList.load`, which writes Field Day's file
and a README into a new folder). A contest has its exchange fields, serial
yes or no, a dupe rule (`dupe(of:band:mode:in:)`, modes grouped by
`modeGroup` as CW, Phone, Digital), CW messages and what to submit
(`dupeSheet`). `fileText` writes one back out (Save Profile as Contest…).
`Settings.profile(for:)` builds a contest's profile from it. `dupeText`
in the form uses the open log's contest (`LogInfo.contest`) when it has
one. Files are read fresh each time, so edits work at once. And
`nextSerial`, used by the form: Serial sent (STX)
shows 1 more than the highest logged in this log for the form's Contest,
filled whenever the form resets (`fillSerial`). A CW message with {NR}
records the number it sent (`serialWasSent`), so it's logged even when
Serial sent isn't on the form. File > New Contest Log… (Logs.swift) adds
a log with `LogInfo.contest` set and links it to `Settings.profile(for:)`,
which finds a profile whose Contest field starts as the contest's ID or
makes one from its template.

## Separate logs and test logs

`LogInfo` (LogList.swift) is one log: an ID, a name, and whether it's a
test log, fixed when it's made. `Logbook.open(info)` opens or makes its
file, backs it up, and remembers the info, so `logbook.isTest` is always
at hand. Every upload path checks it before doing anything:
`OneByOneUpload.upload` (QRZ Logbook, Club Log and eQSL), LoTW's private `upload` (which Sync, the
shortcut menu and automatic uploads all pass through) and `LoTWSync.sync`
(so no confirmations land in a test log either), `AutoUploader.logged`
and `run`. `Backups.copy` leaves test logs' backups on this Mac.
`tools/check-logs.sh` checks all of that with a pretend QRZ.

Switching (`switchTo` in Logs.swift) refuses while the form has a call
or a sheet is open, sends anything waiting for an automatic upload, backs
up the log being left if it changed, opens the new one, and calls
`AppDelegate.install`. At launch that builds the form, table and window;
when switching it hands the new log to the same form and table
(`LogEntryViewController.use`, `LogTableViewController.use`), which clear
everything tied to the old log (undo history, waiting lookups, the
search) and refresh, and it closes the Spots window (its "needed" counts
belong to a log). The views are never rebuilt: the first version did, and
with VoiceOver on it crashed inside macOS's text-input indicator, which
was still attached to the old Callsign field (17 November 2026). Opening at
launch falls back to the main log if the chosen one won't open. Deleting
a log (never the main one) moves its folder to the Trash only after the switch to the
main log has worked, and only a folder under `Logs`.

Each time the app opens, it writes a full copy of the log into
`Backups`, named with the UTC date and time, and deletes all but the
newest 20.

A second copy can go to a folder you chose (Settings > Backups;
`Sources/Settings/BackupFolder.swift` keeps it as a security-scoped
bookmark). `Sources/App/Backups.swift` decides when: at launch it copies
the backup just made; every ten minutes `backUpIfDue` checks the schedule
(`Settings.backupEveryHours`, 4 to start) and backs up if that long has
passed and the log changed (`logChangedSinceBackup`, set by a Logbook
observer, cleared by each backup); at quit, if the log changed, it makes a fresh
backup and copies it straight through (the app is ending, so no
background task); File > Back Up Now does both and says how it went.
`BackupCopy.swift` does the file work: the log goes in as
"Solid Copy log <date>.sqlite" by way of a ".partial" file moved into
place, so a cut-short copy never looks complete; all but the newest 20
logs are removed (never other files); cards are copied when new or a
different size, and never deleted. A problem at quit is kept in
`Settings.backupProblem` and said at the next launch.

## Adding a field to the log file

The table's layout is a list of changes in `LogDatabase.swift`
(`migrations`). Each log file remembers how many it has run. To add a
field, add a new entry at the end of the list, such as
`ALTER TABLE qso ADD COLUMN freq TEXT NOT NULL DEFAULT ''`. Never edit
an entry that's already in use: existing log files have run it already.

## What happens when you press Return

1. You're typing in a field. macOS sends the field a command called
   `insertNewline`.
2. The field passes the command to its delegate, the
   `LogEntryViewController`, through `control(_:textView:doCommandBy:)`.
3. That function sees `insertNewline` and calls `logContact`.
4. `logContact` checks the callsign, creates a `QSO`, and adds it to
   the `Logbook`, which saves it to the log file first. If saving
   fails, the form keeps what you typed and VoiceOver says why.
5. The logbook tells its observers. The table redraws and the "Log:"
   heading updates its count.
6. `logContact` resets the form, moves focus to Callsign, and calls
   `Speaker.announce` to say "Logged".
7. Before resetting, it kept a copy of the form (`FormState`) and
   registers an "undo" with it. Command-Z runs `unlog`: the contact comes
   out of the log, the copy goes back in the form, and a "redo" is
   registered (`relog`) that puts the same contact back, time and all.
   Clear Form keeps a copy the same way (`unclear`). These undos share
   the window's undo list with typing, edits and deletes, so Command-Z
   always takes back the latest thing, and the Edit menu says what
   ("Undo Log Contact").

## Correcting a contact from the form

Up Arrow in an empty Callsign (`stepThroughLog` in
LogEntryViewController.swift) loads the newest contact into the form
(`startCorrecting`) and remembers its id in `correctingID`. While that's
set, Return calls `saveCorrection` instead of logging a new contact: it
takes the log's current copy, puts the form's fields in it, and saves it
with `replaceContact`, which registers an undo that saves the old copy
back. If the call changed, the old call's lookup details
(`LookupResult.filledFields`) are cleared and the new call is looked up.
The radio fields are marked as typed, so the radio doesn't overwrite
what was logged. `resetForm` clears `correctingID`, so Escape, logging or
Undo all end the correction.

## Distance and bearing

`GreatCircle.swift` (Model) turns a Maidenhead grid into the centre of
its square, and works out the great-circle distance (haversine) and the
initial bearing on a sphere of radius 6,371 km. `lookupFinished` adds it
to the lookup line ("282 miles, 53 degrees north-east") and speech
("282 miles north-east"), from the profile's MY_GRIDSQUARE to the
lookup's LAT/LON (QRZ's, closer than a grid) or GRIDSQUARE.
`addDistance` puts DISTANCE (whole km, ADIF's unit) on each contact at
logging, when a late lookup arrives, and when a corrected call is looked
up again (DISTANCE is in `LookupResult.filledFields`, so a changed call
clears it). Miles follow `Locale.measurementSystem`.

## Club numbers

Leaving Callsign also calls `fillClubNumbers`
(LogEntryViewController.swift), which asks `ClubNumbers.numbers` for the
call's SKCC, FISTS, LICW, CWops and your-own-club numbers
(`LogField.clubNumberFields`). It walks the log newest first, taking each
field's first non-empty value for the same main call (W1AW/P is W1AW),
then lets SKCC's list (`SKCCRoster`) replace SKCC. Values go into empty
form fields at once; ones typed are left alone and not announced. The
rest are kept in `clubNumbers` and added to the contact at logging, for
fields not on the form. The lookup line and speech include them
(`clubsShown`, `clubsSpoken`); with lookups off they're said on their
own.

`SKCCRoster` keeps SKCC's pipe-separated member file as "SKCC
members.txt" beside the log, reads it into two dictionaries (call to
number, number to call), and fetches it again when it's a week old
(checked at launch and on each call; a failed fetch waits an hour). A
fetch that isn't SKCC's file (wrong header, fewer than 1,000 members,
over 20 MB) is refused and the old copy kept. `checkSKCC` runs on
leaving SKCC number, and on leaving Callsign when a number was typed
first: `SKCCRoster.problem` gives the words for the screen, and again
with calls spelled out for speech.

Your own club fields are five fixed columns, `app_solidcopy_club1` to
`club5` (migration 8). Their names live in user defaults
(`ClubNames`, in LogField.swift, since the check tools build the field
list without Settings). `LogField.label` reads the name each time, so a
rename shows everywhere the list is next built: Settings posts
`Settings.didChange`, the form rebuilds when a label changed, and the
log's headings are retitled. Unnamed slots are kept off the form, the
column choices and Edit Contact (unless a contact has a value in one).
Exports write them as APP_SOLIDCOPY_CLUB1 and so on; another program
won't know your name for it. (ADIF's USERDEF fields could carry the
name: maybe later.)

## Dupes
Outside a contest or park, `everydayDupe` warns of the same call, band
and mode group (Spot.group: CW, Phone, Data) on the same UTC day.

## Country and needed

`entityText` asks `Countries` (cty.dat) for the call's country and
`WorkedCountries.needed(country:band:modeGroup:log:)` (the Spots window's
tracker, which counts the log as it grows) whether it's a new country,
band or mode. `entityWords` adds it to the lookup line and speech; a
needed one is said even at the brief level. Logging fills Country from
cty.dat when the lookup didn't. cty.dat is fetched at launch if missing
or a month old.

Leaving Callsign calls `dupeText`, which checks the log for the same call
on the same band and mode, but only in a contest (Contest on the form,
same contest, last 4 days) or on a park activation (same park and UTC
day). If the lookup is about to speak, the dupe goes first in its line and
speech (`sayLookup`); if not, it's said on its own. Either way the
warning sound plays, whatever Settings > Speech says, because it's a
warning (contract rule 12).

## Parks

`ParkList.swift` keeps POTA's park list in its own SQLite file,
Parks.sqlite. `build` reads POTA's CSV (with a small CSV reader that
handles quotes), writes a new file with a `park` table and an FTS5
`park_search` index, and only then swaps it in, so a failed download
leaves the old list alone. `search` turns what's typed into an FTS5
query, each word quoted (so nothing typed is taken as FTS5's syntax)
and as a prefix ("POCONO"*), except two-letter state codes.

`ParkSearch.swift` makes a text field a park search. The controller that
owns the field passes on its typing (`textChanged`), Down and Up (`key`),
leaving (`left`) and, before logging, `resolve`, which turns a single
match into its reference or refuses with a reason.

## WSJT-X decodes

`Sources/WSJTX` reads what WSJT-X sends over UDP to 127.0.0.1 port 2237.
`WSJTXMessage.swift` reads its messages (the format is in its comments,
from WSJT-X's NetworkMessage.hpp) and refuses anything broken, and
`FT8Text` turns a message's words into who's calling whom.
`WSJTXListener.swift` listens while the decodes window is open and keeps
the last 15 minutes. It also answers back the way WSJT-X's messages
came: Reply (call a station, then watch WSJT-X's Status to see whether
it took it) and Halt Tx. `DecodesWindowController.swift` is Window > WSJT-X
Decodes; `DecodeLine.swift` has its words, apart from the window, so
`tools/check-wsjtx.sh` can test them. "Needed" is the Spots window's
WorkedCountries, with the band from WSJT-X's dial frequency.

## Spots

`Spots.swift` has `Spot` (one spot, its spoken line, its radio mode, and
whether a logged contact counts as it worked), `POTASpots` (reading
POTA's JSON) and `SpotList`, which fetches once a minute while the Spots
window is open and posts `SpotList.didChange`. A source is just a way to
get `[Spot]`, so DX cluster and SOTA spots join the same list.
SOTA spots are cluster spots whose comment names a summit
(`DXCluster.summit(in:)`); they have source "SOTA" and the summit as
their reference, which `Spot.referenceField` says goes in SOTA_REF
rather than POTA_REF.

`DXCluster.swift` connects to a cluster node with Apple's Network
framework (`NWConnection`, plain TCP), sends the callsign when the node
asks for it, and reads each "DX de" line into a `Spot`, working out its
mode. `SpotList` keeps its spots (one per call and band, 30 minutes) and
tells the window at most every 10 seconds. `Countries.swift` reads
cty.dat into a `CountryTable` (prefixes and exact calls) and finds a
call's country by its longest prefix; `WorkedCountries` keeps which
countries, bands and modes the log has, for "needed".

`SpotsWindowController.swift` filters and shows them, keeping the
selected spot (by `Spot.key`) when the list changes. Return calls
`onUse`, which AppDelegate points at `LogEntryViewController.useSpot`:
that tunes the radio, fills Callsign and their park or summit, keeps the spot's
other fields in `spotFields` for logging, and then looks up the call as
if it had been typed (`callsignDone`).

## QSLs

`Sources/Model/QSL.swift` is QSL tracking without any windows:
`summary` (the one line for the details panel), `display` (a QSL
field's value in words), `Filter` (confirmed, not confirmed, asking for a
card) and `CardMark` with `apply`, which marks contacts, or takes the
mark off if they all have it. The QSL menu (MainMenu.swift) and the log's
shortcut menu call `LogTableViewController`'s `markCard…` and `show…`
commands. Marking saves every contact in one step with
`Logbook.updateAll` (one transaction, one pass over the log), and Undo
puts the old versions back the same way.

`Sources/Model/QSLCards.swift` keeps scanned cards in a QSL Cards folder
beside the log file, one per contact, named by the contact's ID; the log
holds the file's name (`app_solidcopy_qsl_card`) and the scan's text
(`app_solidcopy_card_text`, which search reads like any field). Neither
field is in Edit Contact (`LogField.editable`). `match` pairs a folder's
files with contacts by the call in each file name, never guessing between
several contacts; `attach` copies a card in (via a temporary name, so a
failed copy leaves nothing half done). `Sources/App/QSLCardFolder.swift`
is the folder command: the copying runs away from the main thread, then
the log is changed in one `updateAll`, with Undo.

`Sources/Model/ElectronicCard.swift` makes your electronic QSL card in
two steps: `lines` decides what the card says (your call and lines, your
`my_` fields, "To" with their name, the contact's chosen fields as one
paragraph, the message, 73, what the picture shows), and `pdf` draws
those lines on a card-sized page with Core Graphics. The PDF is tagged
(`CGPDFContextBeginTag`: headings, paragraphs, and the picture as a
figure whose alternative text is your description), so it's an
accessible PDF and not just text on a page. One column on purpose:
VoiceOver reads a PDF across the page, so two columns would interleave.
Each block is measured with `NSLayoutManager`, the same layout that
draws it, then shrunk or the page made taller so nothing is cut off.
The picture is made ready once, when chosen (`preparedPicture`: at most
1600 pixels, JPEG, kept as Application Support/Solid Copy/Card
Picture.jpg). `ElectronicCard.builtInPicture` is the public-domain J-38
photo bundled from `macOS/J38Key.jpg` (where it's from:
`docs/CREDITS.md`; any file in `macOS/` but the plist and entitlements
is copied into the app). `LogTableViewController.sendCard` saves the card in Sent
Cards beside the log and hands it to Mail with `NSSharingService`; the
`CardMail` delegate marks the contact sent only once Mail has taken it.
Its settings are `Settings.card…` and
`Sources/Settings/QSLCardSettingsViewController.swift`, which reuses
`ChoiceListViewController` for the field list.

## Solid Copy's own sounds

`Sources/Accessibility/Tone.swift` makes short sounds as it runs: a WAV
file built in memory and played with `NSSound`, so there are no sound
files to ship. Each `Tone` is a recipe: a voice (sine, a buzz of odd
harmonics, a bell's partials, a knock, a marimba, a glide), its notes and
a level. `RadioMonitor.set` plays `.radioLost` or `.radioBack` when the
connection goes or returns (`RadioMonitor.tone`, which the radio check
replaces to listen). `Alert` is the dupe and needed sounds, as chosen in
Settings > Speech (`Settings.alertSound`): the logging form plays
`Alert.dupe` with a dupe warning and `Alert.needed` for a needed call,
and `SpotList` plays the needed one for a needed DX spot as it arrives
(`chimeIfNeeded`, once per call and band, every 30 seconds at most).

## LoTW

`Sources/LoTW/LoTW.swift` has the rules, with no windows or network:
which contacts to upload, TQSL's command line, reading TQSL's
"Final Status" from its log, the report address, reading LoTW's report
(or its error page), and matching confirmations to contacts.
`LoTWSync.swift` does the work: it writes the contacts to the folder from
Settings > Uploads (a security-scoped bookmark, as the App Sandbox needs),
runs TQSL through a script in Library/Application Scripts with
`NSUserUnixTask` (the one way a sandboxed app may run something outside
the sandbox, with its command line intact; opening TQSL with
`NSWorkspace` lost the command line), waits for it to quit, reads its
log and output, marks what was sent (with `Logbook.change`, on the latest
copies, so an edit made while TQSL ran isn't undone), then fetches
confirmations with `URLSession` and saves them with `Logbook.updateAll`.
LoTW's `APP_LoTW_LASTQSL` is kept (Settings.lotwLastQSL) and sent back
next time, so only newer confirmations come.

## QRZ Logbook, Club Log, eQSL, and automatic uploads

`Sources/Uploads/QRZLogbook.swift` has QRZ Logbook's rules, with no
network: which contacts to send, the form posted for one contact
(`KEY`, `ACTION=INSERT`, `ADIF`, every character but letters, digits and
`-._~` percent-encoded), the ADIF record (`LogExport.adifRecord`: no
header, no Notes, none of Solid Copy's `app_` fields), and reading QRZ's
answer (`RESULT=OK`, `FAIL` with a `REASON`, a duplicate, `AUTH`).
`OneByOneUpload.swift` is the loop QRZ Logbook, Club Log and eQSL share:
it posts one contact at a time with `URLSession`, named in the
User-Agent ("SolidCopy/<version>"), waits between contacts if the
service asks (Club Log: 60 a minute), stops on the first sign the rest
would fail (no internet, an error page, a login problem), and marks what
the service has with `Logbook.change` and `UploadService.mark`. Each
service gives it two small pieces: how to make the request for one
contact, and what an answer means (a `ContactAnswer`: added, already
there, refused and why, or stop). `QRZLogbookUpload.swift`,
`ClubLogUpload.swift` (Club Log's REST API: a Bearer token, JSON with one
ADIF record, the answer read from the HTTP status) and `EQSLUpload.swift`
(a file upload with the login, the answer read from eQSL's lines of
text) are those pieces. One at a time, so each answer belongs to one
contact and nothing is marked wrongly. Every upload returns an
`UploadReport` (Model/Upload.swift): words, whether it all went, and
whether it's worth trying again. `UploadService` (also Model/Upload.swift)
knows each service's name and the ADIF fields that say a contact is
uploaded there.

`QRZLogbookSync.swift` gets QRZ Logbook's confirmations: `ACTION=FETCH`
with `STATUS:CONFIRMED,MAX:250,AFTERLOGID:n`, page after page, the ADIF
taken whole from `ADIF=` to its last `<eor>` (it can hold `&`), then
matched to contacts by `LoTW.apply` with QRZ's fields (`LoTW.Marks`). All
confirmations are fetched each time, since a new one can be for an old
contact.

`AutoUploader.swift` keeps, for each service set to upload by itself, the
contacts logged on the form since Solid Copy opened (the form tells it,
through `LogEntryViewController.onLogged`), and a timer: each new contact
restarts it (30 seconds, or 5 minutes). When it fires it takes the
latest copies of those contacts, leaves out any uploaded or deleted
meanwhile, and uploads them. Only trouble is said, once; an upload that
couldn't reach the service keeps its contacts and tries again in ten
minutes or with the next contact. The waiting list is saved as it
changes, so contacts waiting at quitting go half a minute after the next
launch.

The log's shortcut menu hands the chosen contacts to
`AppDelegate.upload(_:to:)` (UploadCommands.swift) through
`LogTableViewController.onUpload`, so the log table needn't know how
uploads work.

## Window > Activity (uploads and syncs)

`Sources/Activity/Activity.swift` keeps a list of each LoTW, QRZ Logbook,
Club Log and eQSL sync or upload, by hand or automatic: what it was for,
its latest step, and whether it ended Done or Problem. It is held only
while Solid Copy is open (not saved), newest first, capped at 200.
`Activity.track(service, what, work, finish:)` wraps a run: the upload
and sync paths in UploadCommands.swift and AutoUploader.swift call it,
so new services only need wrapping, not new bookkeeping.

`ActivityWindowController.swift` shows the list (Window > Activity,
Command-2). Each row is one sentence for VoiceOver, as Spots does.

Quitting while anything is Running asks first (`applicationShouldTerminate`
in AppDelegate.swift), with Keep Running as the default. Waiting automatic
uploads are saved already, so they need no warning.

Downloads are listed too: the POTA spots (once when they first arrive,
then only when they stop or start working, not every minute), the POTA
park list, SKCC's roster and cty.dat. The DX cluster lists its first
connection, each reconnection and each new trouble (not each 30-second
retry). The radio lists each change between connected and trouble (from
`RadioMonitor.set(_:)`), not each reading. Checks: `tools/check-activity.sh`.

## Window > Log (browsing)

`Sources/LogTable/LogBrowserWindowController.swift` is the open log in its
own window (Window > Log, Command-3), for looking a contact up without
touching the logging window. It uses a second `LogTableViewController`
with `browseOnly` set, which turns off editing, deleting, card marks,
uploads and pasting in that table. While the Log window is in front, the
logging window's log menu items (Edit, Delete, QSL) are disabled, because
they're wired to the logging window's table (`validateMenuItem`). Searching
and the count are the Log window's own.

## What happens when you delete a contact

1. In the log, Delete goes to `LogTableView.keyDown`, which calls
   `deleteContact`.
2. The contact is removed from the logbook, and an "undo" is registered:
   a note saying how to put it back. Command-Z runs that note.
3. The next contact is selected, and VoiceOver says "Deleted".

## What happens when you edit a contact

1. In the log, Return goes to `LogTableView.keyDown`, which calls
   `editContact`. (Command-E, double-clicking, the shortcut menu and
   VoiceOver's actions all end up there too.)
2. `openEditor` creates an `EditContactViewController` with a copy of
   the contact and shows it as a sheet on the main window.
3. Save checks the fields and hands back a changed copy. Cancel hands
   back nothing.
4. `save` in the log table compares the copy with the original. If it
   changed, `Logbook.update` writes it to the log file, then the table
   redraws. An "undo" is registered that saves the old version back.
5. While the sheet is open, the main window's menu commands are turned
   off (`validateMenuItem`), so a shortcut typed in the sheet can't act
   on the log or form behind it.

## Where VoiceOver lands in the log

Each row of the log is made of cell views, each holding a text label.
VoiceOver doesn't see the cell views at all: it lands on each label's
inner "cell" object. So that object (`LogTextCell`, at the end of
`LogTableViewController.swift`) is what offers Edit Contact and Delete
Contact in the Actions rotor, and edits when "pressed".
It passes each of those on to the cell view, where they're defined.

VO-Shift-M works differently: VoiceOver simulates a right-click on the
row, and the table opens its shortcut menu for that row.

### The hidden menu item

macOS quietly adds an extra item to shortcut menus: a hidden, unnamed,
disabled placeholder for its own features (Writing Tools, Services).
Arrow keys skip it, but it made VO-Down stick on the first item. The log's
menu turns this off (`allowsContextMenuPlugIns` and
`automaticallyInsertsWritingToolsItems`). Do the same for every shortcut
menu in Solid Copy.

## Tools for checking accessibility

- `tools/inspect-accessibility.sh` prints what VoiceOver can see in the
  running app right now: windows, the focused element and what's around
  it, and any open shortcut menu with its items. Open the thing you want
  to check, then run it. It needs Accessibility permission for the app
  you run it from, and it only reads. This is how the hidden menu item
  was found.
- The system log: add messages with `Logger` (from `import os`), then
  read them with
  `/usr/bin/log show --last 10m --info --predicate 'subsystem == "io.github.scott-h5.solidcopy"'`.
  That showed the menu's highlight was moving correctly, which pointed
  at VoiceOver's own view of the menu.

## Recipes

### Add a new kind of field to the log

1. Add a line to `LogField.all` in `LogField.swift`, in the group and
   position where it should appear. It then shows in the details panel
   and Edit Contact.
2. Add its column to the log file: a new entry at the end of
   `migrations` in `LogDatabase.swift`, such as `addColumns(["my_field"])`.
3. Run `bash tools/check-log-database.sh`. It fails if a field has no
   column.

### Add a field to the logging form

In `LogEntryViewController.swift`:

1. Add a line like `private let nameField = NSTextField(string: "")`
   next to the other fields.
2. Add `("Name", nameField),` to `formRows`, where you want it in the
   Tab order. Its visible label is made for you, as a `FieldLabel`.
3. In `logContact`, copy it into the contact by its ADIF name, for
   example `qso["band"] = bandField.stringValue`.

### Add a column to the log

In `LogTableViewController.swift`, add a line to `columns`, for
example `Column(id: "gridsquare", title: "Grid", width: 70) { $0["gridsquare"] },`.
The order of the lines is the starting order of the columns. If
you've dragged columns into a new order, the table remembers yours
instead (it's saved under the name "LogColumns").

### Change what's spoken after logging

Find `Speaker.say(.logging, full: "Logged ...` in `logContact` and change
the text (`brief:` is what "Just Logged" says). To make another message
adjustable, change its `Speaker.announce` to `Speaker.say` with a kind;
to add a kind, add it to `Speaker.Kind` and it appears in Settings >
Speech by itself.

### Change a keyboard shortcut

In `MainMenu.swift`, change the `keyEquivalent` of the menu item. A
lower-case letter means Command plus that letter.

## How the radio is read

1. When Solid Copy opens, or you switch radios, `RadioMonitor` takes the
   radio in use (`Settings.currentRadio`).
2. With the built-in driver (the usual way for a Kenwood or Elecraft
   radio), it checks the radio's USB port is there. If not, the radio is
   "off or unplugged". If it is, `KenwoodClient` opens the port itself
   (see "With the built-in driver" below). Solid Copy starts no helper
   program.
3. Every second, on a background queue, the radio's client asks for
   frequency, mode and power: `FA;`, `MD;` and the power setting for a
   Kenwood or Elecraft radio. A rigctld you run (Hamlib NET rigctl) is
   asked the same things with `+f`, `+m` and `+l RFPOWER`.
4. A good reading goes to the form (`radioChanged` in
   LogEntryViewController.swift), which updates the radio pop-up's label
   and fills the radio fields you
   haven't typed in. Pressing Return logs the latest reading for every
   radio field you didn't type, on the form or not.
5. When something goes wrong, it tries again every 3 seconds: the port
   gone is "off or unplugged"; a rigctld that isn't running is "not
   running"; a radio that stays silent is "not answering". Each new kind
   of state is spoken once, and trouble only once until the radio
   connects or its port goes.
6. A radio that's off while its port stays is the costly case: the KX3,
   whose USB chip is in its cable. After a minute of silence, Solid Copy
   looks every 15 seconds instead of 3. Typing a callsign still looks at
   once. The built-in driver holds the serial port while it's connected,
   so another program (the Elecraft Utility, say) can't open it: choose
   No Radio first. `tools/check-radio.sh` checks this with a pretend
   serial port that never answers.

To try the Hamlib NET rigctl path without a radio, `tools/check-radio.sh`
runs hamlib's Dummy radio (model 1, in Homebrew's rigctld, a test tool
only) on port 4600, which pretends to be on 145 MHz FM.

### With the built-in driver

A radio set to "Built-in driver (Kenwood and Elecraft)" has no rigctld.
`KenwoodClient` opens the radio's USB port itself (8 data bits, no
parity, one stop bit, the speed in Settings), and asks in Kenwood's
text: "FA;" gets "FA00014060000;" back. The port's presence is checked
every second, as rigctld's is: if it's gone the radio is "off or
unplugged"; if another app holds it, "port in use". A silent radio is
"not answering", after a second per question. Changes are sent with
"ID;" after them: the radio answers "ID" once it has taken them, and a
"?" means it refused one, so the next choice is tried. Which commands
are radio-tested and which are not is listed in docs/PLAN.md, Phase 3.

## How tuning works

Each arrow key in the tuning control moves a *target* frequency
(`RadioMonitor.tune(toHertz:)`), which the screen and VoiceOver show at
once. The radio is sent the target ("F 14061490") on the background
queue; if more keys were pressed meanwhile, the newest target is sent
next, so ten quick presses don't queue ten commands on a slow serial
port. Once the radio confirms, the target is dropped and readings come
from the radio again.

The Offset control works the same way for the RIT or XIT offset
(`RadioMonitor.setOffset(toHertz:)`, "J 30").

Power, RF gain and Squelch do too, through one function for all three
(`RadioMonitor.changeLevel`, with `levelTargets`). Power is asked for in
watts ("POWER 7"), which `RigctldClient.set` turns into the fraction of
the radio's most power that hamlib's RFPOWER takes, using hamlib's own
`mW2power`. RF gain and squelch are fractions already ("L RF 0.85").
Squelch is only read in FM, so its control only shows there.

Band Up and Band Down (`changeBand` in RadioControl.swift) ask the radio
to change band itself first; a radio that can't is tuned by Solid
Copy: back to `lastOnBand` (where you last were on that band this
session), or else to a usual spot for the mode from `bandSteps`.

Every other change (mode, filter, keyer, preamp and the rest) goes
through `RadioMonitor.change`: send the command, read the radio back,
and say what it now reports, which may differ from what was asked (a
radio rounds a filter width to one it has). Anything but a frequency or
mode reads the status line's settings back too.

Radios differ in what they call the same thing: the TS-590SG's preamp
is 12 dB, an Icom's 10 or 20, and hamlib refuses a value the radio
hasn't got. So a change can be a list of commands to try in turn
(`RigctldClient.setFirst(of:)`): "L PREAMP 1", "L PREAMP 6", "L PREAMP
10", ... until one is taken. hamlib refuses on the spot, without asking
the radio, so this costs nothing. Swap VFOs is the same: swap ("G
XCHG"), or if the radio can't (the TS-590SG and KX3 can't, through
hamlib), use the other VFO ("V VFOB").

The TS-590S and TS-590SG get AGC through Kenwood's own GC command
(`RigctldClient.ts590Command`): hamlib's AGC command never reaches the
radio, and its AGC reading is only what it was last told to set, so
Solid Copy said "slow, medium, fast, super fast" while the radio stayed
on fast. These radios have slow, fast and off; from off, GC3 ("on
again") goes first, as the radio refuses to go straight to a speed.

Elecraft radios get a few settings through Elecraft's own commands,
which rigctld passes on with "W" (`RigctldClient.elecraftCommand`):
through hamlib the KX3 can't read or set its noise blanker or AGC,
and reports its noise reduction level instead of whether it's on. With
PA, NR, NB and GT the whole status read takes about 150 ms. A change has
to be followed by a question ("PA1;ID;"), or the KX3 ignores it; even
so it ignores NR1 (noise reduction on) from the cable, so Solid Copy
says "didn't change" whenever a setting reads back the same as before.

The audio peak filter is asked about only in CW: in other modes the KX3
doesn't answer, and hamlib retried for 6 seconds before giving up,
holding up every command behind it (the long waits after a mode change).

All of this was found with Radio > Record Radio Log, which had rigctld
write every command and every byte from the radio, with times. The menu
items went with the bundled rigctld in v1.3; `rigctl -vvvvv` (Homebrew's
hamlib) does the same job for a rigctld you run.
