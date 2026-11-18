// CallsignLookup.swift
//
// Looks up a callsign using the services you've set up, in order:
//   1. the local cache (anything looked up in the last 30 days),
//   2. QRZ.com, if your QRZ login is in Settings,
//   3. callook.info (US calls only), if it's turned on in Settings.
// The first one that knows the call wins.
//
// Calls with a "/" (W1AW/P, VE3/W1AW) are looked up by their main part,
// since that's how the services file them.
//
// The cache is a small file next to the log (LookupCache.json), so repeat
// lookups are instant and work without the internet.

import Foundation

@MainActor
final class CallsignLookup {
    static let shared = CallsignLookup()

    enum Outcome {
        case found(LookupResult)
        case notFound
        // Something went wrong (no internet, wrong password, ...), and
        // nothing else found the call either.
        case failed(String)
    }

    let qrz = QRZClient()
    private var cache: [String: LookupResult]?
    private static let maximumAge: TimeInterval = 30 * 24 * 60 * 60

    func lookUp(_ call: String) async -> Outcome {
        let key = Self.lookupCall(for: call)
        if let cached = loadCache()[key], Date().timeIntervalSince(cached.fetched) < Self.maximumAge {
            return .found(cached)
        }

        var problem: String?
        let username = Settings.qrzUsername
        if !username.isEmpty {
            do {
                if let fields = try await qrz.lookup(key, username: username, password: Settings.qrzPassword) {
                    return remember(QRZClient.result(from: fields, call: key))
                }
            } catch {
                problem = error.localizedDescription
            }
        }
        if Settings.useCallook {
            do {
                if let result = try await CallookClient.lookup(key) {
                    return remember(result)
                }
            } catch {
                problem = problem ?? error.localizedDescription
            }
        }
        if username.isEmpty && !Settings.useCallook {
            return .failed("No lookup services are turned on. Choose them in Settings.")
        }
        return problem.map { .failed($0) } ?? .notFound
    }

    // The part of a call to look up: "W1AW/P" -> "W1AW", "VE3/W1AW" -> "W1AW".
    nonisolated static func lookupCall(for call: String) -> String {
        let parts = call.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return call }
        return parts.filter(Callsign.looksValid).max { $0.count < $1.count } ?? call
    }

    // Forgets every cached lookup (used after changing the QRZ login, so
    // free-account results can be replaced by fuller ones).
    func clearCache() {
        cache = [:]
        saveCache()
    }

    // MARK: - Cache

    // The most lookups kept. Past this, the oldest are dropped.
    private static let maximumCached = 5_000

    private func remember(_ result: LookupResult) -> Outcome {
        var all = loadCache()
        all[result.call] = result
        if all.count > Self.maximumCached {
            let oldest = all.values.sorted { $0.fetched < $1.fetched }.prefix(all.count - Self.maximumCached)
            for old in oldest { all.removeValue(forKey: old.call) }
        }
        cache = all
        saveCache()
        return .found(result)
    }

    private var cacheURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Solid Copy", isDirectory: true)
            .appendingPathComponent("LookupCache.json")
    }

    private func loadCache() -> [String: LookupResult] {
        if let cache { return cache }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded = cacheURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? decoder.decode([String: LookupResult].self, from: $0) } ?? [:]
        // Old results are no use: drop them when the cache is read.
        loaded = loaded.filter { Date().timeIntervalSince($0.value.fetched) < Self.maximumAge }
        cache = loaded
        return loaded
    }

    private func saveCache() {
        guard let cacheURL, let cache else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(cache).write(to: cacheURL, options: .atomic)
    }
}
