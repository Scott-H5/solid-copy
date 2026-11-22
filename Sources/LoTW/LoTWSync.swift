// LoTWSync.swift
//
// QSL > Sync with LoTW (Shift-Command-L): uploads the contacts LoTW
// doesn't have yet, through TQSL, then downloads new confirmations, and
// says what happened. The rules are in LoTW.swift.
//
// How TQSL is run: Solid Copy is in the App Sandbox, and anything it runs
// directly is sandboxed too, so TQSL couldn't reach your certificate in
// ~/.tqsl. Opening TQSL as its own app doesn't work either: macOS drops
// the command line when a sandboxed app opens another (found 16 November
// 2026: TQSL just showed its main window). Apple's way is a script *you*
// put in Library/Application Scripts/<Solid Copy's ID>/: a sandboxed app
// may run those (NSUserUnixTask), outside the sandbox, but can't put one
// there itself. Settings > Uploads > Install TQSL Script… does it with a Save
// dialog you confirm. The script (scriptText) only starts TQSL with what
// Solid Copy passes it. TQSL and Solid Copy swap files (the contacts, and
// TQSL's log and output) in a folder you choose in Settings > Uploads.
//
// Nothing is sent anywhere but LoTW, and only your LoTW login and your
// contacts.

import AppKit

@MainActor
enum LoTWSync {
    static let tqslApp = URL(fileURLWithPath: "/Applications/TrustedQSL/tqsl.app")
    static var tqslInstalled: Bool { FileManager.default.fileExists(atPath: tqslApp.path) }
    private(set) static var running = false

    // MARK: - The TQSL script

    static let scriptName = "tqsl.sh"
    static let scriptText = """
        #!/bin/sh
        # Installed by Solid Copy (Settings > Uploads). Solid Copy is sandboxed,
        # so it runs TQSL through this script, which macOS lets it run
        # outside the sandbox. It only starts TQSL with what Solid Copy
        # passes it (sign and upload a file of contacts). Delete it to stop.
        exec /Applications/TrustedQSL/tqsl.app/Contents/MacOS/tqsl "$@"

        """

    // Library/Application Scripts/<Solid Copy's ID>, which macOS makes.
    static var scriptsFolder: URL? {
        try? FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
    }
    static var scriptURL: URL? { scriptsFolder?.appendingPathComponent(scriptName) }
    static var scriptInstalled: Bool {
        guard let url = scriptURL else { return false }
        return FileManager.default.isExecutableFile(atPath: url.path)
    }

    // Writes the script where Save put it (the dialog makes that allowed),
    // and lets it run. Refuses anywhere but the scripts folder.
    static func installScript(at url: URL) throws {
        guard url.deletingLastPathComponent().standardizedFileURL == scriptsFolder?.standardizedFileURL,
              url.lastPathComponent == scriptName else {
            throw DatabaseError(message: "Save it as \(scriptName) in the folder the dialog opened in, unchanged.")
        }
        try Data(scriptText.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    // One-time repair (16 November 2026): the first sync read TQSL's "no
    // certificate, nothing signed" (code 8) as "all already on LoTW" and
    // marked every contact uploaded, dated that day. Those marks come off
    // again (confirmed contacts stay uploaded: LoTW has them). Runs once.
    static func repairFalseUploads(_ logbook: Logbook) {
        let key = "lotw.repairedFalseUploads"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let fixed = logbook.contacts.filter { $0["lotw_qslsdate"] == "20261116" }.map { qso -> QSO in
            var qso = qso
            qso["lotw_qslsdate"] = ""
            if qso["lotw_qsl_rcvd"].uppercased() != "Y" { qso["lotw_qsl_sent"] = "" }
            return qso
        }
        if !fixed.isEmpty, (try? logbook.updateAll(fixed)) == nil { return }
        UserDefaults.standard.set(true, forKey: key)
    }

    // MARK: - The shared folder

    // The folder chosen in Settings > Uploads, opened for use, or nil.
    static func folder() -> URL? {
        guard let bookmark = Settings.lotwFolderBookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope) { Settings.lotwFolderBookmark = fresh }
        return url
    }

    static func setFolder(_ url: URL) throws {
        Settings.lotwFolderBookmark = try url.bookmarkData(options: .withSecurityScope)
    }

    // MARK: - Sync

    // Uploads, then downloads. `progress` is told each step, to say. Returns
    // the summary, one sentence per line.
    static func sync(_ logbook: Logbook, progress: (String) -> Void) async -> String {
        // A test log isn't synced at all: no upload, and no confirmations
        // applied to contacts that aren't real.
        guard !logbook.isTest else { return UploadReport.testLogText }
        guard !running else { return "A sync is already running." }
        running = true
        defer { running = false }
        var lines: [String] = []
        lines.append(await upload(LoTW.toUpload(logbook.contacts, from: Settings.lotwUploadFrom),
                                  logbook, progress: progress).text)
        lines.append(await download(logbook, progress: progress))
        return lines.joined(separator: "\n\n")
    }

    // Uploads just these contacts, and gets no confirmations: the log's
    // shortcut menu and automatic uploads (AutoUploader.swift). Contacts
    // already uploaded are sent too if you chose them; TQSL tells LoTW's
    // repeats apart itself.
    static func upload(_ contacts: [QSO], to logbook: Logbook, progress: (String) -> Void = { _ in }) async -> UploadReport {
        guard !running else { return UploadReport(text: "A sync is already running.", ok: false) }
        running = true
        defer { running = false }
        return await upload(contacts, logbook, progress: progress)
    }

    private static func upload(_ contacts: [QSO], _ logbook: Logbook, progress: (String) -> Void) async -> UploadReport {
        // Checked here, where every LoTW upload passes, so no path misses it.
        guard !logbook.isTest else { return .testLog }
        func skip(_ why: String) -> UploadReport { UploadReport(text: "Upload skipped: " + why, ok: false) }
        guard tqslInstalled else { return skip("TQSL isn't in Applications (TrustedQSL folder).") }
        guard scriptInstalled else { return skip("install the TQSL script in Settings > Uploads.") }
        let location = Settings.tqslLocation
        guard !location.isEmpty else { return skip("add your TQSL station location in Settings > Uploads.") }
        guard let folder = folder() else { return skip("choose a folder for TQSL in Settings > Uploads.") }
        defer { folder.stopAccessingSecurityScopedResource() }

        guard !contacts.isEmpty else { return UploadReport(text: "Upload: nothing new to send.", ok: true) }
        let file = folder.appendingPathComponent("Solid Copy to LoTW.adi")
        let log = folder.appendingPathComponent("Solid Copy TQSL log.txt")
        do {
            try LogExport.adif(contacts, includeNotes: false).write(to: file, options: .atomic)
            try? FileManager.default.removeItem(at: log)
        } catch {
            return UploadReport(text: "Upload didn't start: couldn't write the contacts file. "
                                + error.localizedDescription, ok: false)
        }
        progress("Uploading \(count(contacts.count)) with TQSL.")
        // TQSL's own output goes to a file beside its log (a pipe could
        // fill up and stall it on a big upload).
        let output = folder.appendingPathComponent("Solid Copy TQSL output.txt")
        do {
            guard let scriptURL else { throw DatabaseError(message: "There's no scripts folder.") }
            let task = try NSUserUnixTask(url: scriptURL)
            FileManager.default.createFile(atPath: output.path, contents: nil)
            let handle = try FileHandle(forWritingTo: output)
            defer { try? handle.close() }
            task.standardOutput = handle
            task.standardError = handle
            // Waits until TQSL quits. An error here is TQSL's exit status,
            // not a failure to run: its log says what happened.
            try? await task.execute(withArguments: LoTW.tqslArguments(file: file, location: location, log: log))
        } catch {
            return UploadReport(text: "Upload didn't start: the TQSL script wouldn't run. "
                                + "\(error.localizedDescription) Install it again in Settings > Uploads.", ok: false)
        }
        func text(_ url: URL) -> String { String(decoding: (try? Data(contentsOf: url)) ?? Data(), as: UTF8.self) }
        let result = LoTW.uploadResult(fromLog: text(log) + "\n" + text(output))
        guard result.uploaded else {
            guard case .failed(let why) = result else { return UploadReport(text: "Upload failed.", ok: false) }
            // Not reaching LoTW is worth another try later.
            return UploadReport(text: "Upload: " + why, ok: false, tryAgain: why.contains("couldn't reach LoTW"))
        }
        // Every contact sent is marked; any TQSL skipped (its "compliant"
        // setting signs what it can) aren't, and the summary says why.
        // Marked on the latest copies, so an edit made meanwhile stays.
        let skipped = LoTW.skipped(in: text(output))
        let sent = contacts.filter { !skipped.keys.contains(LoTW.Skipped.key(for: $0)) }
        let today = QSL.today()
        do {
            try logbook.change(Set(sent.map(\.id))) { qso in
                qso["lotw_qsl_sent"] = "Y"
                if qso["lotw_qslsdate"].isEmpty { qso["lotw_qslsdate"] = today }
            }
        } catch {
            return UploadReport(text: "Uploaded, but the log couldn't be marked: \(error.localizedDescription)", ok: false)
        }
        let skippedText = skipped.keys.isEmpty ? ""
            : (contacts.count - sent.count == 1 ? " 1 contact wasn't signed, so isn't marked."
               : " \(contacts.count - sent.count) contacts weren't signed, so aren't marked.")
                + " Not signed: \(skipped.list). TQSL said: \(skipped.reason). Fix it in Edit Contact, then sync again."
        let words: String
        switch result {
        case .alreadySent: words = "Upload: LoTW already had all \(count(sent.count)); now marked uploaded."
        case .someAlreadySent: words = "Upload: sent \(count(sent.count)); LoTW already had some of them. Marked uploaded."
        default: words = "Upload: sent \(count(sent.count)) to LoTW."
        }
        return UploadReport(text: words + skippedText, ok: skipped.keys.isEmpty)
    }

    private static func download(_ logbook: Logbook, progress: (String) -> Void) async -> String {
        let username = Settings.lotwUsername
        let password = Settings.lotwPassword
        guard !username.isEmpty, !password.isEmpty else {
            return "Confirmations skipped: add your LoTW username and password in Settings > Uploads."
        }
        // Once, the first time with details: every confirmation again, so
        // older ones get where the other station was (Settings.lotwHasDetails).
        let everything = !Settings.lotwHasDetails
        let since = everything ? "" : Settings.lotwLastQSL
        guard let url = LoTW.reportRequest(username: username, password: password, since: since) else {
            return "Confirmations: couldn't make the request."
        }
        progress(everything ? "Getting all confirmations from LoTW once, with where each station was. "
                    + "This can take a minute." : "Getting confirmations from LoTW.")
        let report: LoTW.Report
        do {
            var request = URLRequest(url: url, timeoutInterval: 120)
            request.setValue("SolidCopy", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return "Confirmations: LoTW answered with an error. Try again later."
            }
            report = try LoTW.report(from: data)
        } catch {
            return "Confirmations: " + error.localizedDescription
        }
        let wasConfirmed = Set(logbook.contacts.filter { $0["lotw_qsl_rcvd"].uppercased() == "Y" }.map(\.id))
        let (changed, unmatched) = LoTW.apply(report.confirmations, to: logbook.contacts)
        do { try logbook.updateAll(changed) } catch {
            return "Confirmations came, but the log couldn't be changed: \(error.localizedDescription)"
        }
        // Only once they're saved, so a failure asks for them again.
        if !report.lastQSL.isEmpty { Settings.lotwLastQSL = report.lastQSL }
        Settings.lotwHasDetails = true
        let newly = changed.filter { !wasConfirmed.contains($0.id) }.count
        let detailed = changed.count - newly
        var text = newly == 0 ? "Confirmations: none new." : "Confirmations: \(count(newly)) newly confirmed by LoTW."
        if detailed > 0 {
            text += " \(count(detailed)) already confirmed got LoTW's state, zone or prefix."
        }
        if !unmatched.isEmpty {
            let some = unmatched.prefix(10).map { "\($0.call) \($0.band) \(QSO(call: $0.call, timeOn: $0.time).utcDateText)" }
            text += " \(unmatched.count) matched nothing in this log (logged elsewhere?): "
                + some.joined(separator: ", ") + (unmatched.count > 10 ? ", and more." : ".")
        }
        return text
    }

    private static func count(_ n: Int) -> String { n == 1 ? "1 contact" : "\(n) contacts" }
}
