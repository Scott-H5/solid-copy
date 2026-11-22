# Solid Copy: Accessibility Contract

These are the promises Solid Copy makes to someone using VoiceOver and
the keyboard. Each one is written so it can be tested. When the app
changes, check it against this list. If a change breaks a rule, the
change isn't done yet.

Status: **Done** means it's in the app now. **Planned** gives the phase
it's scheduled for.

## Focus

1. **The app opens in the Callsign field.** No click, no Tab, no
   VoiceOver navigation needed. *Done.*
2. **Tab moves only through fields you normally change,** in a fixed,
   predictable order, and wraps from the last back to Callsign.
   Shift-Tab goes backwards. You choose the fields and which are Tab
   stops in Settings > Logging Form. *Done.*
3. **Tabbing into a field selects its contents,** so typing replaces the
   starting value (for example, 5 in Power on the Portable form). Signal
   reports start blank, and take only a plus or minus and up to 3
   digits; any other key beeps and says what's allowed, so a mistyped
   letter never reaches the log silently. *Done.*
4. **Return logs the contact from any field** in the entry form. Focus
   goes back to Callsign and the form resets to its defaults. *Done.*
5. **Escape clears the form** and returns to Callsign. *Done.* Command-Z
   brings the cleared form back, so a stray Escape loses nothing.
   Command-Z straight after logging takes the contact back out of the
   log and into the form, to fix and log again with Return; it says
   which call it took back. Nothing is logged except by Return (or
   Command-Return): never by leaving a field.
   Up Arrow in an empty Callsign brings the last contact back into the
   form to correct, and says which ("Correcting W 1 A W, 14:32 UTC, 20
   meters CW"); Up and Down step through older and newer ones; Return
   saves to that same contact ("Corrected"), Escape leaves it as it was,
   and Command-Z undoes a correction. *Done.*
6. **Command-L goes to Callsign** from anywhere in the window.
   **Command-I goes to the newest contact in the log,** so VoiceOver
   reads it and it's highlighted on screen; Escape in the log goes back
   to Callsign. The log isn't in the Tab loop, so it never slows down
   logging. *Done.*
7. **Auto-filled fields aren't tab stops.** Fields filled by a lookup or
   the radio stay on screen but don't slow down Tab. Name starts this
   way; you can make it a Tab stop again in Settings. *Done.*
8. **Nothing steals focus.** A lookup finishing, the radio changing
   frequency, or a spot arriving never moves focus. They speak instead.
   *Done for lookups, the radio and spots (a new list of spots keeps
   the spot you're on selected, and isn't spoken).*

## Speech

9. **Every action that has no visible movement is announced.** Logging
   says "Logged" with the call and the number of contacts. Clearing says
   "Cleared." Deleting says "Deleted" with the call. *Done.*
10. **Callsigns are spoken letter by letter** ("W 1 A W"), because
    VoiceOver otherwise tries to say them as words. *Done.* Phonetics
    ("Whiskey One Alfa Whiskey") as an option: *Planned, later.*
11. **A lookup produces one short line, most important first:** call,
    name, location, then worked-before or needed status. For example:
    "W 1 A W, Hiram, Newington Connecticut, worked 3 times before."
    States and provinces are said in full, not as two letters. The same
    line, with the full name and grid, is shown under the form. *Done.*
12. **Warnings are announced separately and first:** duplicate, invalid
    exchange, radio disconnected, no band. *Radio lost and back also
    have their own tones (Tone.swift), always played, so a dropped radio
    is heard even under other sounds; Settings > Speech > Radio lost or
    back adds the words or not. Logging with no band warns once, and
    Return again logs (16 November 2026).* *Dupe: done (in contests and park
    activations, said before the lookup, with a warning sound, whatever
    Settings > Speech says). Radio: done. Invalid exchange: planned.* The radio
    reconnects by itself, whatever order things are started in, and its
    state is spoken once when it changes ("Radio not answering",
    "Radio connected, 14.060 megahertz, CW"). It never needs a restart of
    Solid Copy or a dialog dismissed. *Done (RadioMonitor.swift), naming the
    radio: "Kenwood TS-590SG connected, 7.025 megahertz, CW", "… off or
    unplugged", "… not answering", "… connection not running". Trouble
    is said once, not again each time Solid Copy tries the radio, until
    it connects or its port goes.
    Switching radios (Control-Command-1, 2…, or the radio pop-up, whose
    label is the radio and its reading) says the new radio's name and
    leaves focus where it was. A change of frequency isn't spoken; it's
    on the radio pop-up under the clocks.*
13. **New announcements replace stale ones** instead of queuing behind
    them. *Done (announcements use high priority, which interrupts).*
14. **Status is available on request:** hotkeys speak frequency and
    mode, the contact count and, in contests, the rate. *Radio: done
    (Command-R says frequency, mode, filter, band and power, or what's
    wrong; Option-Command-R the keyer, RIT, AGC and the rest).
    The others planned, Phases 1 and 5.* (The last contact is shown, not spoken: see rule 6.)
    Whether each one is spoken or shown could become a setting.
15. **Announcements are short enough for a braille display,** with the
    key fact at the start. *Applies to every announcement.*

## Controls

16. **Standard controls only,** with clear names. Every field has a
    spoken name that matches its visible label. The visible label itself
    is hidden from VoiceOver, so moving with VO-arrows stops once per
    field instead of on the label and then the field. *Done.*
17. **Every command is in a menu** with its shortcut shown, so it can be
    found with VoiceOver's menu navigation and not just memorised.
    *Done.*
18. **Tables behave like Crystal Set's:** arrows move between rows,
    and actions are in VoiceOver's Actions rotor, in a shortcut menu,
    and in the menu bar. *Done for the log: Edit Contact and Delete
    Contact. Return, or "pressing" a row in VoiceOver, edits it.
    VO-Shift-M opens the shortcut menu for the contact under the
    VoiceOver cursor, and VO-arrows move through it as in Finder.*
    Every shortcut menu turns off the items macOS adds by itself, which
    include a hidden blank item that stops VO-Down.
19. **Deleting can be undone instead of asking "Are you sure?"**
    Delete removes the selected contacts at once (Shift-Up and Shift-Down
    select several) and says how many; Command-Z puts them all back and
    selects them. Undo is faster than a dialog and just as safe. While
    several are selected, the details panel says how many. *Done.*

20. **A contact is never lost silently.** If saving fails, the form
    keeps everything you typed, the Mac beeps, and VoiceOver says "Not
    saved" and why. *Done.*

21. **Editing a contact happens in a sheet, never in the logging form,**
    so there's no doubt which contact you're changing. The sheet opens
    in Callsign and has every field, Notes included. Tab moves through
    them in order (also out of Notes). Return saves, except in Notes,
    where it starts a new line; Command-Return and Command-S save from
    anywhere.
    Escape cancels and says "Nothing changed." Tab reaches Cancel and
    Save after Time when Keyboard navigation is on in System Settings.
    A wrong date or time
    beeps, says what's wrong and puts focus in that field. After saving,
    focus is back on the same contact in the log, and Command-Z undoes
    the edit. *Done.*

    QSL statuses and "via" are menus in words, never ADIF's letters, and
    QSL dates read and type as 2025-12-17. *Done (16 November 2026).*

22. **Every field of a contact can be reached without a wide table.**
    The log shows a few columns; the details panel under it lists every
    filled-in field of the selected contact, one line each ("Name: Hiram
    Percy"), so VoiceOver reads a field in one stop. Tab in the log (or
    Option-Command-I anywhere) goes to the details; Up and Down move
    through them; Command-C copies a value; Escape, Tab or Shift-Tab goes
    back to the log on the same contact, so Tab moves back and forth
    between the log and the details. Shift-Tab in the log steps back to
    Comment, the logging form's last field. So Shift-Tab backs out from
    details to log to form, while Tab in the form stays in the form. Edit Contact has every field, under
    group headings that VO-arrows can read and Tab skips, and scrolls to
    keep the focused field in view. In the log, Left and Right Arrow
    choose a column and say it with the contact's value; Option-Command-
    Left and Right move that column and say where it went (Call stays
    first). *Done.*

23. **Settings are one short window, in reading order.** Command-comma
    opens it in the QRZ username field; Escape or Command-W closes it.
    Save and Test says, and shows, whether the QRZ login worked and
    whether the account is free or subscribed. *Done.*

24. **Earlier contacts with a call are one key away.** The lookup line
    says how often and when you last worked the call, with band and
    mode ("Worked 3 times before, last on 30 October 2026 on 20 meters
    CW"). Option-Command-F narrows the log to that call and moves focus to the
    newest; the heading says so; Tab reads each one's details, notes
    included. Escape shows the whole log again and returns to Callsign,
    with the form as you left it. *Done.*

25. **Lists of choices work without a mouse.** In Settings > Logging Form
    and Log Columns, each row reads as one line ("Name: on the form, not a
    Tab stop"). Space shows or hides; Option-Command-Up and Down move;
    Show, Hide, Make Tab Stop and Move are also in the Actions rotor, the
    shortcut menu and buttons. Each change is spoken. *Done.*
    Settings is a list of sections ("Settings sections") beside the
    chosen section, as in System Settings, not tabs: Up and Down choose
    (it shows at once, focus stays in the list), Return or Right Arrow go
    in, Tab goes round the section and back to the list, Command-1 to 5
    go straight to a section's first control (Command-1 to 7). *Done.*
27. **The profile in use is always findable.** The window title is
    "Solid Copy, Portable" (VoiceOver reads it on arrival); the Profile
    menu ticks it; Option-Command-1 to 9 switch, and the new profile's
    name is spoken. Switching changes the form at once without moving
    focus or losing what's typed in fields both profiles share. *Done.*

26. **Searching the log keeps you informed without moving you.**
    Command-F goes to Search the log, just above the log (not a Tab stop
    in the form). The log narrows as you type; when you pause, VoiceOver
    says how many match, and the heading says so too. Return, Down Arrow
    or Tab goes to the first match; Escape, in the search or the log,
    clears it and returns to Callsign. *Done.*

28. **The radio can be driven without a mouse or a look at the radio.**
    Command-T goes to the tuning control, a slider to VoiceOver whose
    value is the frequency in kilohertz; arrows tune, each change is
    spoken (a quick press interrupting the last), and Escape returns to
    Callsign. Tab goes on to the Offset control (RIT or XIT), which works
    the same way; Delete clears it; then Power (watts), RF gain and
    Squelch (percent; shown only in FM), each one there only if the radio
    reports it, and from the last back to Callsign. Control-Command-Up
    and Down change band and say where the radio landed; Option-Command-S
    says the S-meter. A frequency or mode typed in Callsign
    tunes or changes mode on Return. Every other radio command is
    Control-Command and a letter (P preamp, A attenuator, G AGC, B noise
    blanker, N noise reduction, K peak filter, W dual watch, R RIT, X
    XIT, S split, V swap VFOs), is in the Radio menu, and says what the radio actually
    did ("Preamp 12 dB"), or that the radio can't. None of them moves
    focus. Nothing that transmits is on a key that can be pressed by
    accident; Power only changes when you're in its control and press an
    arrow. *Done (RadioSlider.swift, RadioControl.swift).*

29. **You choose how much is said, and nothing turned down is lost.**
    Lookups, logging and radio changes you make can each be said in
    full, briefly, or as a sound (lookups also not at all), in Settings
    > Speech; Quiet Mode (Option-Command-period) turns all three down to
    sounds for a while. Logging and radio keys always answer with at
    least a sound. Errors and warnings are always said in full. What was
    turned down is one key away: Option-Command-N (name and place),
    Option-Command-L (last contact), Command-R (the radio). *Done
    (Speaker.swift).*

30. **Closing a window by mistake loses nothing.** Closing the logging
    window hides it instead of quitting; Command-0 (Window > Logging
    Window), or clicking Solid Copy in the Dock, brings it back as it was,
    with focus in Callsign. Command-Q quits. Command-backtick and
    Shift-Command-backtick move between the logging window and Settings,
    and are in the Window menu. *Done (AppDelegate.swift).*

31. **A park is chosen by name without seeing a list.** In a park field
    (POTA park on the form, My POTA park in Profiles), typing searches POTA's park list; after a
    pause VoiceOver says how many match, or the park if one does. Down
    and Up go through the matches, each said in full with its place in
    the list ("US-1333, Big Pocono State Park, Pennsylvania. 1 of 3"), and
    put its reference in the field. Focus never moves. Return never logs
    a half-typed search: it beeps and says how many parks match. *Done
    (ParkSearch.swift).*

32. **Spots are read one line each, and used with one key.** The Spots
    window (Command-1) lists spots newest first, each one line, most
    important first ("W1AW, 14.062 CW, US-1333 Big Pocono State Park,
    Pennsylvania, 3 minutes ago, worked today"). Return on a spot tunes
    the radio and puts its call and park in the form, with focus in
    Callsign; Escape goes back to the logging window. Filters say what
    they leave when changed ("12 of 59 spots, CW"). DX cluster spots say
    their country and whether it's needed ("Falkland Islands, needed:
    new country"), and the list changes at most every 10 seconds, so it
    doesn't shift constantly under VoiceOver. SOTA spots say "summit"
    before the reference ("summit W4C/CM-001"), so it isn't heard as a
    park, and Return on one says "summit" too. *Done
    (SpotsWindowController.swift, DXCluster.swift).*
33. **A contact's QSLs are one line, in words.** The details panel says
    whether a contact is confirmed and how in one stop ("QSL: Confirmed:
    card 17 December 2025, LoTW 23 April 2022"), and shows every QSL
    field in words, never ADIF's letters ("Card received: Yes"). Marking
    cards (QSL menu, or the log's shortcut menu) works on the selection,
    says what it did ("Card sent for 3 contacts, dated today"), keeps
    the same contacts selected, and is undone with Command-Z or by the
    same command again. Attaching a folder of cards ends in a summary
    that lists every card it couldn't attach and why, so nothing is left
    out without your knowing; Open Card opens the scan in Preview, where
    VoiceOver reads its text. *Done (QSL.swift, LogTableViewController.swift,
    ContactDetailsViewController.swift). Edit Contact still shows the
    letters: see docs/PLAN.md.*

34. **Syncing with LoTW is one command, and it says how it went.** QSL >
    Sync with LoTW says each step as it starts ("Uploading 12 contacts
    with TQSL", "Getting confirmations from LoTW") and ends with a
    summary in a message VoiceOver reads, in words, never TQSL's codes:
    what was sent, what was confirmed, what matched nothing, and why
    anything didn't happen ("TQSL couldn't unlock your callsign
    certificate: its passphrase wasn't given"). TQSL itself runs without
    a window, because its own windows are hard to use with VoiceOver.
    *Done (LoTWSync.swift, LoTW.swift).*

35. **Uploads that run by themselves never interrupt logging.**
    Automatic uploads to LoTW, QRZ Logbook, Club Log or eQSL are silent
    when they work:
    no "uploaded" after every contact while you're working a pileup. A
    problem is said once, in words, with the warning sound ("Automatic
    upload. QRZ Logbook: nothing sent. Stopped. QRZ couldn't be
    reached."), and not again while it lasts. Nothing goes up by itself
    unless you chose that; By hand is the starting choice. Uploads by
    hand (the QSL menu, or the log's shortcut menu for just the contacts
    chosen) say how they went. *Done (AutoUploader.swift,
    OneByOneUpload.swift, UploadCommands.swift).*

36. **A copied number that doesn't fit the call is said at once.**
    An SKCC number that belongs to someone else, or to nobody, is a
    warning when you leave its field (or Callsign): the warning sound,
    then whose number it is, with calls spelled out ("SKCC 12345 is
    W 1 A B C. W 1 A B D isn't in SKCC's list."). It's on the lookup
    line too. Focus doesn't move, and the contact can still be logged.
    Club numbers filled in are said with the lookup, at the lookup's
    speech level, with SKCC's award letters in words ("SKCC 12345
    Tribune"). *Done (SKCCRoster.swift, ClubNumbers.swift,
    LogEntryViewController.swift).*

37. **You always know which log is open, and switching loses nothing.**
    The window title names the log ("Solid Copy, Contest practice (test
    log), Home"), and switching says it with its count ("Contest
    practice (test log) open, 12 contacts. Nothing in it is uploaded.").
    File > Open Log lists every log with the open one ticked. Switching
    is refused, and says why, while the form has a call or a sheet is
    open. Focus lands in Callsign of the log just opened. Command-C in
    the log copies contacts, and Command-V in the log or the form pastes
    them into the open log (focus doesn't move), each said with its
    count and the log's name ("Pasted 3 contacts into Practice (test
    log)."). Opening a log that brings back its profile says the profile
    too ("Field Day 2027 open, 0 contacts. Field Day profile."). *Done (Logs.swift, LogList.swift, LogTableViewController).*

38. **CW is sent and stopped without leaving the form.** F1 to F8 send
    messages from wherever focus is in the logging window; Escape stops
    sending (and only clears the form when nothing is sending). Sending
    is silent; a problem is said ("The WinKeyer isn't connected. CW
    menu, Connect WinKeyer."). Connecting, disconnecting and a lost
    WinKeyer are said. The CW menu lists what each key sends. *Done
    (CW.swift, WinKeyer.swift).*

39. **Your QSL card reads in full, in order.** The card is one column,
    so VoiceOver reads it top to bottom: your call, your lines, who it's
    to, the contact, the message, 73. Its PDF is tagged (headings,
    paragraphs, the picture as a figure with your description as its
    alternative text), and the description is also the card's last
    line. Nothing is cut off: too much text shrinks the type, then makes
    the card taller. Send QSL Card says what happened ("Card made, in a
    new message to ..."; without Mail, that the card is selected in
    Finder). *Built (ElectronicCard.swift, QSLCardSettingsViewController,
    LogTableViewController.sendCard); check-cards.sh reads the PDF's text
    back.*

40. **Instructions are text you can read again.** What a field needs
    (where to find a key, which nickname, a date's form) is in a note
    beside it, never only in the field's VoiceOver label or grey
    placeholder: those are spoken once, can't be read word by word and
    can't be copied (the author, 17 November 2026, eQSL QTH Nickname). A
    field's label is its name, short; a placeholder is at most an
    example ("2020-01-01"). Notes are selectable, so they can be copied,
    and a field is linked to its note (VO-Command-J). *Done for Settings
    > Uploads (UploadsSettingsViewController).*

41. **A message can be copied.** Every message sheet (showMessage) has
    Copy after OK, which puts the title and message on the clipboard,
    says "Copied." and closes: an alert's text is heard but can't be
    selected (the author, 17 November 2026, a Club Log refusal). A message
    that is only spoken (an automatic upload, the log's shortcut menu)
    can be shown again with QSL > Show Last Upload Message.

## Testing

Before each phase is finished:

- Go through the full logging loop with VoiceOver on, keyboard only.
- Check that each "Done" rule above still holds.
- Run Apple's accessibility audit on every screen: `bash audit.sh`. It
  takes about 15 minutes and prints one "AUDIT:" line per finding.
  Known false alarms, skipped by the test with the reasons written in
  it: contrast inside tables (measured 17 to 21 to 1), and a
  Parent/Child mismatch from the Caps Lock indicator macOS shows on a
  focused text field. A few "contrast nearly passed" findings on a window
  that's behind another (macOS dims those on purpose) are also expected;
  the same text passes when its window is in front. Last clean run:
  2026-11-14, every screen in front passed.
  Run of 2026-11-16 (30 minutes, VoiceOver on): 97 findings, mostly the
  same few repeated on every screen. Real: empty log cells had no
  description (now say "blank"). Expected: the main window's title
  and clocks behind Settings or a sheet. Probably the VoiceOver caption
  panel lying over text when the screen was sampled: "Log: 166
  contacts" and the Settings > Speech note, both plain black on white
  in the screenshots. Run with VoiceOver's caption panel off to check.
