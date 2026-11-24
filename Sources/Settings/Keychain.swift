// Keychain.swift
//
// Keeps passwords in the Mac's Keychain, the encrypted store macOS uses
// for passwords: the QRZ.com password ("Solid Copy: QRZ.com"), the LoTW
// website password ("Solid Copy: LoTW"), the QRZ Logbook API key
// ("Solid Copy: QRZ Logbook"), the Club Log token ("Solid Copy: Club
// Log") and the eQSL password ("Solid Copy: eQSL"). They're never written to a
// settings file or log. You can see or delete them in the Keychain Access
// app, by those names.

import Foundation
import Security

enum Keychain {
    // The names passwords are filed under in the Keychain.
    static let service = "Solid Copy: QRZ.com"
    static let lotwService = "Solid Copy: LoTW"
    // The QRZ Logbook key has no username, so it's filed under this one.
    static let qrzLogbookService = "Solid Copy: QRZ Logbook"
    static let qrzLogbookAccount = "API key"
    // Club Log's token has no username either.
    static let clubLogService = "Solid Copy: Club Log"
    static let tokenAccount = "token"
    static let eqslService = "Solid Copy: eQSL"

    // The password saved for this username, or nil if there isn't one.
    // Off only in checks that build Settings (tools/screen-size-check):
    // they mustn't read the author's real logins, and macOS would stop
    // them to ask permission. Nothing outside this process can change it.
    static var readsAllowed = true

    static func password(for account: String, service: String = service) -> String? {
        guard readsAllowed, !account.isEmpty else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // Saves (or replaces) the password for this username. An empty password
    // removes it.
    static func setPassword(_ password: String, for account: String, service: String = service) throws {
        guard !account.isEmpty else { return }
        deletePassword(for: account, service: service)
        guard !password.isEmpty else { return }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: service,
            kSecValueData as String: Data(password.utf8),
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
            throw LookupError(message: "Couldn't save the password in the Keychain: \(reason)")
        }
    }

    static func deletePassword(for account: String, service: String = service) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
