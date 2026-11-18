// UploadCommands.swift
//
// The upload commands, by hand:
//   QSL > Sync with LoTW (Shift-Command-L): every contact LoTW doesn't
//     have yet, then its confirmations (LoTWSync.swift).
//   QSL > Sync with QRZ Logbook (Shift-Command-U): every contact QRZ
//     Logbook doesn't have yet, then its confirmations
//     (QRZLogbookSync.swift).
//   QSL > Upload to Club Log, Upload to eQSL: every contact that service
//     doesn't have yet
//     (OneByOneUpload.swift and each service's file in Sources/Uploads).
//   The log's shortcut menu, Upload to LoTW / QRZ Logbook / Club Log /
//     eQSL: just the contacts chosen, even ones already sent.
// Each step is said as it starts ("Uploading 12 contacts with TQSL."). The
// QSL menu's summary is shown in a message VoiceOver reads, as imports
// are; the shortcut menu's (usually a contact or two) is just said.
// (Automatic uploads are in AutoUploader.swift.)
//
// With no login saved yet, an upload goes to that service's login field
// in Settings > Uploads instead of a message saying where to go.
//
// More of the AppDelegate class, like ImportExport.swift.

import AppKit

extension AppDelegate {

    @objc func syncWithLoTW(_ sender: Any?) {
        guard let logbook, window?.attachedSheet == nil else { return }
        guard !LoTWSync.running else { return Speaker.announce("A LoTW sync is already running.") }
        Task { [weak self] in
            let summary = await Activity.shared.track("LoTW", "Sync: uploads and confirmations", { progress in
                await LoTWSync.sync(logbook) { Speaker.announce($0); progress($0) }
            }, finish: { (true, $0) })
            UploadReport.last = summary
            self?.showMessage("LoTW sync finished.", details: summary)
        }
    }

    @objc func syncWithQRZLogbook(_ sender: Any?) {
        guard let logbook, window?.attachedSheet == nil else { return }
        guard !OneByOneUpload.running.contains(.qrzLogbook), !QRZLogbookSync.running else {
            return Speaker.announce("A QRZ Logbook sync is already running.")
        }
        guard hasLogin(.qrzLogbook) else { return askForLogin(.qrzLogbook) }
        Task { [weak self] in
            let summary = await Activity.shared.track("QRZ Logbook", "Sync: uploads and downloads", { progress in
                await QRZLogbookSync.sync(logbook) { Speaker.announce($0); progress($0) }
            }, finish: { (true, $0) })
            UploadReport.last = summary
            self?.showMessage("QRZ Logbook sync finished.", details: summary)
        }
    }
    @objc func uploadAllToClubLog(_ sender: Any?) { uploadAll(to: .clubLog) }
    @objc func uploadAllToEQSL(_ sender: Any?) { uploadAll(to: .eqsl) }

    private func uploadAll(to service: UploadService) {
        guard let logbook, window?.attachedSheet == nil else { return }
        guard !OneByOneUpload.running.contains(service) else {
            return Speaker.announce("A \(service.name) upload is already running.")
        }
        guard hasLogin(service) else { return askForLogin(service) }
        let contacts = service.toUpload(logbook.contacts, from: Settings.uploadFrom(service))
        Task { [weak self] in
            let report = await Self.send(contacts, to: service, logbook: logbook)
            UploadReport.last = report.text
            self?.showMessage("\(service.name) upload finished.", details: report.text)
        }
    }

    // A login (key, token, or username and password) is saved.
    private func hasLogin(_ service: UploadService) -> Bool {
        switch service {
        case .lotw: true  // LoTWSync says what's missing itself.
        case .qrzLogbook: !Settings.qrzLogbookKey.isEmpty
        case .clubLog: !Settings.clubLogToken.isEmpty
        case .eqsl: !Settings.eqslUsername.isEmpty && !Settings.eqslPassword.isEmpty
        }
    }

    // Settings > Uploads, in the service's login field, said so focus
    // landing there isn't a surprise. (Automatic uploads don't come here:
    // they never open windows; see contract rule 35.)
    private func askForLogin(_ service: UploadService) {
        editLogin(for: service)
        switch service {
        case .qrzLogbook:
            Speaker.announce("QRZ Logbook needs your logbook's API key. Paste it here, then press Return to save it.")
        case .clubLog:
            Speaker.announce("Club Log needs a token. On clublog.org, open Settings, then API, and create one. "
                             + "Paste it here, then press Return to save it.")
        case .eqsl:
            Speaker.announce("eQSL needs your eQSL username and password. Type them here; each is saved as you leave it.")
        case .lotw: break
        }
    }

    // QSL > QRZ Logbook API Key…, Club Log Token…, eQSL Login…: Settings
    // > Uploads, focus in that field, ready to paste.
    @objc func editQRZLogbookKey(_ sender: Any?) { editLogin(for: .qrzLogbook) }
    @objc func editClubLogToken(_ sender: Any?) { editLogin(for: .clubLog) }
    @objc func editEQSLLogin(_ sender: Any?) { editLogin(for: .eqsl) }

    // QSL > QSL Card Settings…: Settings > QSL Card (ElectronicCard.swift).
    @objc func editCardSettings(_ sender: Any?) {
        showSettings(nil)
        settingsWindow?.showSection(named: "QSL Card")
    }

    private func editLogin(for service: UploadService) {
        showSettings(nil)
        settingsWindow?.showLogin(for: service)
    }

    // Every by-hand upload is listed in Window > Activity as it runs.
    private static func send(_ contacts: [QSO], to service: UploadService, logbook: Logbook) async -> UploadReport {
        let what = "Upload \(contacts.count == 1 ? "1 contact" : "\(contacts.count) contacts")"
        return await Activity.shared.track(service.name, what, { progress in
            let say: (String) -> Void = { Speaker.announce($0); progress($0) }
            switch service {
            case .lotw: return await LoTWSync.upload(contacts, to: logbook, progress: say)
            case .qrzLogbook: return await QRZLogbookUpload.upload(contacts, logbook: logbook, progress: say)
            case .clubLog: return await ClubLogUpload.upload(contacts, logbook: logbook, progress: say)
            case .eqsl: return await EQSLUpload.upload(contacts, logbook: logbook, progress: say)
            }
        }, finish: { ($0.ok, $0.text) })
    }

    // From the log's shortcut menu.
    func upload(_ contacts: [QSO], to service: UploadService) {
        guard let logbook else { return }
        guard hasLogin(service) else { return askForLogin(service) }
        Task {
            let report = await Self.send(contacts, to: service, logbook: logbook)
            let text = (service == .lotw ? "LoTW. " : "") + report.text
            UploadReport.last = text
            if !report.ok { Speaker.Cue.warning.play() }
            Speaker.announce(text)
        }
    }

    // QSL > Show Last Upload Message: the last upload or sync message
    // again, in a sheet you can read word by word, with Copy.
    @objc func showLastUploadMessage(_ sender: Any?) {
        guard window?.attachedSheet == nil else { return }
        if UploadReport.last.isEmpty {
            return Speaker.announce("No upload message yet since Solid Copy opened.")
        }
        showMessage("Last upload message", details: UploadReport.last)
    }
}
