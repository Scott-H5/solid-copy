// Every window and sheet fits a small, zoomed screen.
//
// Apple's accessibility audit doesn't test this: it looks at each window
// at the size it opens on the test Mac, never on a smaller or zoomed
// screen. So a window that couldn't shrink below 780 points of height,
// with its bottom off a small laptop's screen, passed every audit (found
// 24 November 2026). This check is what catches that now.
//
// The screen to fit: 1024 by 640 points, a 13-inch laptop with Displays
// set to Larger Text, which people with low vision often use. Less the
// menu bar and the Dock, about 570 points of height are left for a
// window, title bar and all. Each window is asked to shrink to almost
// nothing; Auto Layout stops it at the smallest its contents allow, and
// that has to fit. (A window whose contents scroll can shrink further.)
// A sheet hangs below its window's title bar, so it has 28 points less.
//
// Run it with:  bash tools/check-screen-size.sh

import AppKit
func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }

let screenWidth: CGFloat = 1024, screenHeight: CGFloat = 570, titleBar: CGFloat = 28

setvbuf(stdout, nil, _IOLBF, 0)
MainActor.assumeIsolated {
  _ = NSApplication.shared
  let book = try! Logbook(database: LogDatabase(fileURL: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("L.sqlite")))

  // The smallest a window's frame (title bar included) can be.
  func smallest(_ window: NSWindow) -> NSSize {
    window.setContentSize(NSSize(width: 100, height: 100)); window.layoutIfNeeded()
    let content = window.contentView!.frame.size
    let least = NSSize(width: max(content.width, window.contentMinSize.width),
                       height: max(content.height, window.contentMinSize.height))
    return window.frameRect(forContentRect: NSRect(origin: .zero, size: least)).size
  }
  func fits(_ name: String, _ window: NSWindow?, sheet: Bool = false) {
    guard let window else { return check(false, "\(name): no window") }
    let size = smallest(window)
    let room = screenHeight - (sheet ? titleBar : 0)
    check(size.width <= screenWidth && size.height <= room,
          "\(name) fits a 1024 by 640 screen (smallest \(Int(size.width)) by \(Int(size.height)), room \(Int(screenWidth)) by \(Int(room)))")
  }

  // The logging window, as AppDelegate makes it.
  let form = LogEntryViewController(logbook: book)
  let main = NSWindow(contentViewController: form)
  main.styleMask = [.titled, .closable, .miniaturizable, .resizable]
  main.contentMinSize = NSSize(width: 600, height: 360)
  fits("The logging window", main)

  // Edit Contact, sized for the small screen as it would be there.
  let editor = EditContactViewController(qso: QSO(call: "N0CALL", timeOn: Date()))
  editor.fit(toScreenHeight: screenHeight)
  let sheet = NSWindow(contentViewController: editor)
  sheet.styleMask = [.titled]
  sheet.layoutIfNeeded()
  let sheetSize = sheet.contentView!.fittingSize
  check(sheetSize.height <= screenHeight - titleBar && sheetSize.width <= screenWidth,
        "Edit Contact fits below the logging window's title (\(Int(sheetSize.width)) by \(Int(sheetSize.height)))")

  // Set Up Station, the first-run window.
  let firstRun = FirstRunSheet.contentsForChecks().fittingSize
  check(firstRun.height + titleBar <= screenHeight && firstRun.width <= screenWidth,
        "Set Up Station fits (\(Int(firstRun.width)) by \(Int(firstRun.height)))")

  fits("Spots", SpotsWindowController(logbook: book).window)
  fits("Activity", ActivityWindowController().window)
  fits("Log", LogBrowserWindowController(logbook: book).window)
  fits("WSJT-X Decodes", DecodesWindowController(logbook: book).window)
  fits("Awards", AwardsWindowController(logbook: book).window)
  // With a club chosen, Between dates: its dates and goal show, and fit.
  ClubNames.setName("NAQCC number", for: 1)
  UserDefaults.standard.set("club:app_solidcopy_club1", forKey: "awards.award")
  UserDefaults.standard.set("between", forKey: "awards.clubPeriod")
  let clubAwards = AwardsWindowController(logbook: book)
  clubAwards.reload()
  func goalShown(_ view: NSView) -> Bool {
    if let field = view as? NSTextField, field.accessibilityLabel() == "Goal, members" {
      return !field.isHiddenOrHasHiddenAncestor
    }
    return view.subviews.contains(where: goalShown)
  }
  check(goalShown(clubAwards.window!.contentView!), "Awards: a club's dates and goal show when a club is chosen")
  fits("Awards, a club chosen", clubAwards.window)
  // Nothing in the dates row is squeezed below its own size at the least width.
  func find(_ view: NSView, _ label: String) -> NSView? {
    if view.accessibilityLabel() == label { return view }
    for sub in view.subviews { if let found = find(sub, label) { return found } }
    return nil
  }
  if let row = find(clubAwards.window!.contentView!, "Dates")?.superview {
    let squeezed = row.subviews.filter { $0.frame.width + 0.5 < $0.fittingSize.width }
    check(squeezed.isEmpty && row.frame.maxX <= clubAwards.window!.contentView!.frame.width,
          "Awards: the dates row isn't squeezed (\(Int(row.fittingSize.width)) wide)")
  }
  UserDefaults.standard.set("dxcc", forKey: "awards.award")
  let dxccAwards = AwardsWindowController(logbook: book)
  dxccAwards.reload()
  check(!goalShown(dxccAwards.window!.contentView!), "Awards: no club choices for DXCC")
  ClubNames.setName("", for: 1)
  fits("Band Plan", BandPlanWindowController().window)

  // Settings, on every section (its sections scroll, but the sidebar and
  // the window's least size still have to fit).
  Keychain.readsAllowed = false  // never the real logins
  let settings = SettingsWindowController()
  _ = settings.window
  check(settings.sectionTitles.count >= 14, "Settings has its sections (\(settings.sectionTitles.count))")
  for title in settings.sectionTitles {
    settings.showSection(named: title)
    fits("Settings > \(title)", settings.window)
    // And no section much wider than the others (one long unwrapped line
    // once made Settings need nearly the whole screen's width).
    check(smallest(settings.window!).width <= 760, "Settings > \(title) isn't made wide by one long line")
  }

  // Settings > Radio, New Radio: focus goes to the Manufacturer menu, and
  // that menu is shown. (A new radio made for Hamlib NET rigctl hid it with
  // focus in it, so VoiceOver lost its place; 26 November 2026.)
  ["radios", "currentRadio"].forEach(UserDefaults.standard.removeObject(forKey:))
  settings.showSection(named: "Radio")
  func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
  let radioViews = views(settings.window!.contentView!)
  let newRadio = radioViews.compactMap { $0 as? NSButton }.first { $0.title == "New Radio" }
  let maker = radioViews.compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "Manufacturer" }
  newRadio?.performClick(nil)
  check(maker != nil && settings.window!.firstResponder === maker && maker?.isHiddenOrHasHiddenAncestor == false
        && Settings.currentRadio?.builtIn == true,
        "Settings > Radio: New Radio puts focus on the Manufacturer menu, which is shown")
  maker?.selectItem(withTitle: "Kenwood")
  if let maker { _ = maker.sendAction(maker.action, to: maker.target) }
  check(Settings.currentRadio?.name == "Kenwood" && settings.window!.firstResponder === maker
        && maker?.isHiddenOrHasHiddenAncestor == false,
        "and choosing Kenwood keeps focus there, naming the radio Kenwood")

  // Move Up and Move Down set the order, which is Control-Command-1, 2, ...
  // in the Radio menu.
  ["radios", "currentRadio"].forEach(UserDefaults.standard.removeObject(forKey:))
  let ts590 = RadioSettings(model: 2037, modelName: "Kenwood TS-590SG", port: "/dev/cu.a", builtIn: true)
  let kx3 = RadioSettings(model: 2045, modelName: "Elecraft KX3", port: "/dev/cu.b", builtIn: true)
  Settings.radios = [kx3, ts590]
  Settings.useRadio(ts590.id)
  settings.showSection(named: "Radio")
  // Settings > Radio shows a change a moment later (it waits for menus).
  RunLoop.main.run(until: Date().addingTimeInterval(0.3))
  let moveUp = radioViews.compactMap { $0 as? NSButton }.first { $0.title == "Move Up" }
  let moveDown = radioViews.compactMap { $0 as? NSButton }.first { $0.title == "Move Down" }
  check(moveUp?.isEnabled == true && moveDown?.isEnabled == false, "Settings > Radio: the last radio can move up, not down")
  moveUp?.performClick(nil)
  check(Settings.radios.map(\.id) == [ts590.id, kx3.id] && Settings.currentRadio?.id == ts590.id
        && RadioMenu.choices(withShortcuts: true).first?.keyEquivalent == "1"
        && RadioMenu.choices(withShortcuts: true).first?.title == "Kenwood TS-590SG",
        "Move Up makes the TS-590SG first, Control-Command-1")
  check(moveUp?.isEnabled == false && settings.window!.firstResponder === moveDown,
        "and focus goes to Move Down, as Move Up can't be pressed again")

  // New Radio, then Escape before it's set up: it's cancelled, Settings
  // stays open on Radio, and the radio in use before it is used again.
  settings.show()
  settings.showSection(named: "Radio")
  let inUseMenu = radioViews.compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "Radio in use" }
  newRadio?.performClick(nil)
  settings.window!.cancelOperation(nil)
  check(settings.window!.isVisible && Settings.radios.map(\.id) == [ts590.id, kx3.id]
        && Settings.currentRadio?.id == ts590.id && settings.window!.firstResponder === inUseMenu,
        "Escape cancels a new radio and stays in Settings > Radio, on Radio in use, with the TS-590SG back")
  settings.window!.cancelOperation(nil)
  check(!settings.window!.isVisible, "and Escape again, with nothing to cancel, closes Settings")
  settings.show()
  settings.showSection(named: "Radio")

  // New Radio, then Settings closed before it's set up: it's taken off,
  // and the radio in use before it is used again.
  newRadio?.performClick(nil)
  check(Settings.radios.count == 3, "New Radio adds a radio")
  settings.window!.close()
  check(Settings.radios.map(\.id) == [ts590.id, kx3.id] && Settings.currentRadio?.id == ts590.id,
        "closing Settings before the new radio is set up takes it off, and the TS-590SG is in use again")
  ["radios", "currentRadio"].forEach(UserDefaults.standard.removeObject(forKey:))

  // A message (AppDelegate.showMessage) with a long report, as an import
  // or upload with many problems gives: its OK and Copy buttons must
  // stay on the screen.
  let alert = MessageAlert.make(title: "Import finished.",
                                details: (1...60).map { "Line \($0): N0CALL on 20 meters, 14.074 FT8, not added: already in the log." }.joined(separator: "\n"))
  alert.layout()
  let alertHeight = alert.window.frame.height
  check(alertHeight <= screenHeight - titleBar, "a long message fits, buttons and all (\(Int(alertHeight)) points)")
  check(alert.accessoryView != nil && alert.informativeText.contains("box below"),
        "the long message is in a scrolling box, and the alert says so")
  let short = MessageAlert.make(title: "Export finished.", details: "12 saved as Contest.adi.")
  check(short.accessoryView == nil && short.informativeText == "12 saved as Contest.adi.", "a short message is the alert's own text, as before")
}
