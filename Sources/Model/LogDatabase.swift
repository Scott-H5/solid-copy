// LogDatabase.swift
//
// Stores contacts in the log file, using Database.swift.
//
// Where the log lives: Solid Copy is sandboxed, so its files are in its
// own container folder:
//   ~/Library/Containers/io.github.scott-h5.solidcopy/Data/
//       Library/Application Support/Solid Copy/
// That folder holds Logbook.sqlite (the log) and a Backups folder.
// File > Show Log in Finder opens it.
//
// The table's columns are named after ADIF fields, in lower case
// (call, qso_date, time_on, ...), so ADIF export and import are close to
// a straight copy. Dates and times are stored exactly as ADIF writes
// them, in UTC: qso_date as YYYYMMDD and time_on as HHMMSS.
//
// Everything is kept here, including Notes. Exports can leave Notes out;
// backups never do, because they're copies of this whole file.

import Foundation

final class LogDatabase {
    let fileURL: URL
    private let database: Database

    // How many automatic backups to keep. Older ones are deleted.
    static let backupsToKeep = 20

    // Changes to the table layout, oldest first. Each one runs once per log
    // file, in order, and the file remembers how many have run (its
    // "user version"). To add a field later, add it to LogField.swift and
    // add a new entry at the end of this list, for example:
    //   addColumns(["my_new_field"])
    // Never change an entry that has already been used: existing log files
    // have already run it.
    private static let migrations: [String] = [
        // 1: the first layout (2026-11-14).
        """
        CREATE TABLE qso (
            id TEXT PRIMARY KEY,
            call TEXT NOT NULL,
            qso_date TEXT NOT NULL,
            time_on TEXT NOT NULL,
            rst_sent TEXT NOT NULL DEFAULT '',
            rst_rcvd TEXT NOT NULL DEFAULT '',
            comment TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE INDEX qso_by_call ON qso (call);
        CREATE INDEX qso_by_time ON qso (qso_date, time_on);
        """,
        // 2: name, location, radio, awards, QSL, contest and my-station
        // fields, matching what SQL log files hold (2026-11-14).
        addColumns([
            "name", "email", "web", "band", "mode", "submode",
            "freq", "band_rx", "freq_rx", "tx_pwr", "sat_name", "qth",
            "state", "cnty", "country", "dxcc", "gridsquare", "cqz",
            "ituz", "iota", "address", "lat", "lon", "distance",
            "ant_az", "ant_el", "pota_ref", "sota_ref", "wwff_ref", "skcc",
            "ten_ten", "sig", "sig_info", "qsl_sent", "qsl_rcvd", "qsl_via",
            "qslmsg", "contest_id", "stx", "srx", "stx_string", "srx_string",
            "station_callsign", "my_gridsquare", "my_rig", "my_pota_ref", "my_sota_ref", "my_wwff_ref",
            "my_sig", "my_sig_info",
        ]),
        // 3: end time, my state and county, LoTW and QRZ Logbook status,
        // and the SQL log format's own fields, for the SQL log import
        // (2026-11-14).
        addColumns([
            "qso_date_off", "time_off", "my_state", "my_cnty",
            "lotw_qsl_rcvd", "lotw_qslrdate", "qrzcom_qso_upload_status", "qrzcom_qso_upload_date",
            "app_macloggerdx_qsl_sent", "app_macloggerdx_qsl_rcvd",
            "app_macloggerdx_ext_val_3", "app_macloggerdx_ext_val_4",
        ]),
        // 4: FISTS (official ADIF fields), and LICW and CWops numbers
        // (Solid Copy's own fields, as ADIF has none) (2026-11-14).
        addColumns(["fists", "fists_cc", "app_solidcopy_licw", "app_solidcopy_cwops"]),
        // 5: The SQL log format's own fields taken out again (2026-11-15). Checked
        // against the author's log: its QSL text was a bulk mark ("CardC" with
        // one date on every contact) plus what's already in the LoTW and
        // QRZ Logbook fields; extra value 3 only repeated the state, and 4
        // was empty. Nothing in them is lost.
        """
        ALTER TABLE qso DROP COLUMN app_macloggerdx_qsl_sent;
        ALTER TABLE qso DROP COLUMN app_macloggerdx_qsl_rcvd;
        ALTER TABLE qso DROP COLUMN app_macloggerdx_ext_val_3;
        ALTER TABLE qso DROP COLUMN app_macloggerdx_ext_val_4;
        """,
        // 6: QSL tracking: card dates and how they went, their card's
        // message, LoTW and eQSL sent and received, and QRZ Logbook
        // confirmations (ADIF 3.1.6 names) (2026-11-16). Step 5 was wrong
        // about "CardC": those are real paper cards (the author, 16 November),
        // now imported as cards received (SQLLogImport.swift). Its
        // dropped column was never needed: the import reads the original.
        addColumns([
            "qslsdate", "qsl_sent_via", "qslrdate", "qsl_rcvd_via", "qslmsg_rcvd",
            "lotw_qsl_sent", "lotw_qslsdate", "eqsl_qsl_sent", "eqsl_qslsdate", "eqsl_qsl_rcvd", "eqsl_qslrdate",
            "qrzcom_qso_download_status", "qrzcom_qso_download_date",
        ]),
        // 7: scanned QSL cards: the card's file and its text (2026-11-16).
        addColumns(["app_solidcopy_qsl_card", "app_solidcopy_card_text"]),
        // 8: your own club fields, named in Settings > Clubs (2026-11-16).
        addColumns((1...LogField.clubSlots).map { "app_solidcopy_club\($0)" }),
        // 9: Club Log uploads (ADIF's names) (2026-11-17).
        addColumns(["clublog_qso_upload_status", "clublog_qso_upload_date"]),
    ]

    // SQL that adds text columns, each starting empty.
    private static func addColumns(_ names: [String]) -> String {
        names.map { "ALTER TABLE qso ADD COLUMN \($0) TEXT NOT NULL DEFAULT '';" }.joined(separator: "\n")
    }

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        database = try Database(url: fileURL)
        try migrate()
    }


    // MARK: - Contacts

    // Every contact, oldest first.
    //
    // Read one row at a time, straight into contacts, so a big log loads
    // quickly and without a second copy in memory. (Measured with
    // tools/scale-check.sh.)
    func loadAll() throws -> [QSO] {
        var contacts: [QSO] = []
        contacts.reserveCapacity(try count())
        // Where each column is, worked out from the first row.
        var positions: (id: Int32, call: Int32, date: Int32, time: Int32, fields: [(Int32, String)])?
        try database.forEachRow("SELECT * FROM qso ORDER BY qso_date, time_on, rowid") { columns, text in
            if positions == nil {
                func position(_ name: String) -> Int32 { Int32(columns.firstIndex(of: name) ?? -1) }
                let fields = LogField.all.compactMap { field in
                    columns.firstIndex(of: field.adif).map { (Int32($0), field.adif) }
                }
                positions = (position("id"), position("call"), position("qso_date"), position("time_on"), fields)
            }
            guard let at = positions,
                  let id = UUID(uuidString: text(at.id) ?? ""),
                  let timeOn = QSO.date(adifDate: text(at.date) ?? "", adifTime: text(at.time) ?? "")
            else { return }
            var fields: [String: String] = [:]
            for (column, name) in at.fields {
                if let value = text(column) { fields[name] = value }
            }
            contacts.append(QSO(id: id, call: text(at.call) ?? "", timeOn: timeOn, storedFields: fields))
        }
        return contacts
    }

    // created_at and updated_at times. Made once: formatters are slow to
    // create, and an import saves every contact.
    private static let timestamp = ISO8601DateFormatter()

    // Backup names: "Logbook 2026-11-14 143205Z.sqlite".
    private static let backupName: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HHmmss'Z'"
        return formatter
    }()

    // The columns written for every contact: the special ones, then one
    // for each field in LogField.swift.
    private static let fieldColumns = LogField.all.map(\.adif)

    func insert(_ qso: QSO) throws {
        let now = Self.timestamp.string(from: Date())
        let columns = ["id", "call", "qso_date", "time_on"] + Self.fieldColumns + ["created_at", "updated_at"]
        let values = [qso.id.uuidString, qso.call, qso.adifDate, qso.adifTime]
            + Self.fieldColumns.map { qso[$0] } + [now, now]
        let places = Array(repeating: "?", count: columns.count).joined(separator: ", ")
        try database.run("INSERT INTO qso (\(columns.joined(separator: ", "))) VALUES (\(places))", values)
    }

    // Saves changes to a contact that's already in the log.
    func update(_ qso: QSO) throws {
        let now = Self.timestamp.string(from: Date())
        let columns = ["call", "qso_date", "time_on"] + Self.fieldColumns + ["updated_at"]
        let values = [qso.call, qso.adifDate, qso.adifTime] + Self.fieldColumns.map { qso[$0] } + [now]
        let assignments = columns.map { "\($0) = ?" }.joined(separator: ", ")
        try database.run("UPDATE qso SET \(assignments) WHERE id = ?", values + [qso.id.uuidString])
    }

    // The log file's column names (used by the tests, to check that every
    // field in LogField.swift has a column).
    func columnNames() throws -> [String] {
        try database.query("PRAGMA table_info(qso)").compactMap { $0["name"] }
    }

    // Adds many contacts at once, as one transaction: either all are
    // saved, or (if anything fails) none are. Used by imports.
    func insertAll(_ contacts: [QSO]) throws {
        try database.transaction {
            for qso in contacts { try insert(qso) }
        }
    }

    // Saves changes to many contacts at once, as one transaction (marking
    // QSL cards on a selection).
    func updateAll(_ contacts: [QSO]) throws {
        try database.transaction {
            for qso in contacts { try update(qso) }
        }
    }

    // Deletes many contacts at once, as one transaction (undoing an import).
    func deleteAll(ids: [UUID]) throws {
        try database.transaction {
            for id in ids { try delete(id: id) }
        }
    }

    func delete(id: UUID) throws {
        try database.run("DELETE FROM qso WHERE id = ?", [id.uuidString])
    }

    func count() throws -> Int {
        Int(try database.query("SELECT count(*) AS n FROM qso").first?["n"] ?? "0") ?? 0
    }

    // MARK: - Backups

    // The Backups folder, next to the log file.
    var backupsFolder: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
    }

    // Writes a complete copy of the log into the Backups folder, named
    // with the UTC date and time ("Logbook 2026-11-14 143205Z.sqlite"),
    // then deletes all but the newest backups. Returns the new file.
    //
    // "VACUUM INTO" is SQLite's own way to make a clean, consistent copy
    // of a database while it's open; copying the file directly could
    // catch it halfway through a write.
    @discardableResult
    func backUp() throws -> URL {
        try FileManager.default.createDirectory(at: backupsFolder, withIntermediateDirectories: true)
        let backup = backupsFolder.appendingPathComponent("Logbook \(Self.backupName.string(from: Date())).sqlite")
        try database.run("VACUUM INTO ?", [backup.path])
        // Checked before anything is pruned: a damaged copy must never
        // push a good backup out of the folder.
        guard Self.isIntact(backup) else {
            try? FileManager.default.removeItem(at: backup)
            throw DatabaseError(message: "The backup didn't pass SQLite's integrity check, so it wasn't kept. "
                                + "The older backups are untouched.")
        }
        try pruneBackups()
        return backup
    }

    // SQLite's own check of a whole file: "PRAGMA integrity_check" answers
    // with one row, "ok", when every page and index reads back sound. It
    // opens the file read-only, so the file isn't changed.
    static func isIntact(_ file: URL) -> Bool {
        guard let copy = try? Database(readOnlyURL: file),
              let rows = try? copy.query("PRAGMA integrity_check") else { return false }
        return rows.count == 1 && rows[0].values.contains("ok")
    }

    // The newest backup, or nil if there are none.
    var newestBackup: URL? {
        (try? FileManager.default.contentsOfDirectory(at: backupsFolder, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("Logbook ") && $0.pathExtension == "sqlite" }
            .max { $0.lastPathComponent < $1.lastPathComponent }
    }

    // The names start with the date, so sorting by name sorts by age.
    private func pruneBackups() throws {
        let backups = try FileManager.default
            .contentsOfDirectory(at: backupsFolder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("Logbook ") && $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in backups.dropFirst(Self.backupsToKeep) {
            try FileManager.default.removeItem(at: old)
        }
    }

    // MARK: - Table layout

    private func migrate() throws {
        let current = try database.userVersion
        for (index, sql) in Self.migrations.enumerated() where index >= current {
            try database.transaction {
                try database.execute(sql)
                try database.execute("PRAGMA user_version = \(index + 1)")
            }
        }
    }
}
