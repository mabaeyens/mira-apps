#if os(iOS)
import Foundation
import SwiftUI

/// What goes into iCloud's key-value store. `token` is decoded so a legacy entry
/// can be migrated, and is written only when the Keychain refused the token.
private struct StoredConnection: Codable {
    var id: UUID
    var label: String
    var urlString: String
    var token: String?
}

/// A saved server. `token` lives in memory only: it is read from and written to
/// the Keychain (see ConnectionTokenKeychain), never encoded with the rest.
struct SavedConnection: Identifiable, Hashable {
    var id: UUID
    var label: String
    var urlString: String
    var token: String?

    init(id: UUID = UUID(), label: String, urlString: String, token: String? = nil) {
        self.id = id
        self.label = label
        self.urlString = urlString
        self.token = token
    }

    var url: URL? { URL(string: urlString) }

    static func autoLabel(for urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else { return "Server" }
        if host.hasPrefix("100.") || host.hasSuffix(".ts.net") { return "Tailscale" }
        return "Local"
    }
}

@Observable
final class SavedConnectionsStore {
    private static let connectionsKey = "savedConnections_v2"
    private static let activeKey     = "activeConnectionURL"
    private let kv = NSUbiquitousKeyValueStore.default

    // ── Known connections ──────────────────────────────────────────────────────
    // Add your own connections via the UI. The seeds array ships empty so no
    // real IPs are committed to the repository.
    static let seeds: [(label: String, url: String)] = [
        // ("Home WiFi",  "http://192.168.x.x:8000"),
        // ("Tailscale",  "https://your-mac.ts.net:8443"),
    ]

    var connections: [SavedConnection] = []
    var activeURLString: String? = nil

    init() {
        load()
        migrateToKVStoreIfNeeded()
        migrateIfNeeded()
        seedKnownConnections()
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kv,
            queue: .main
        ) { [weak self] _ in self?.load() }
        kv.synchronize()
    }

    private func seedKnownConnections() {
        var changed = false
        for (label, urlString) in Self.seeds {
            guard !connections.contains(where: { $0.urlString == urlString }) else { continue }
            connections.append(SavedConnection(label: label, urlString: urlString))
            changed = true
        }
        if changed { persist() }
    }

    func add(_ connection: SavedConnection) {
        // Same URL again (re-pairing, a rotated token): update the saved entry.
        // Keeping the old one dropped the new token, so the next launch
        // reconnected with the stale one and every request came back 401.
        if let i = connections.firstIndex(where: { $0.urlString == connection.urlString }) {
            connections[i].token = connection.token
            if (connection.token ?? "").isEmpty { ConnectionTokenKeychain.delete(connection.urlString) }
            if !connection.label.isEmpty { connections[i].label = connection.label }
        } else {
            connections.insert(connection, at: 0)
        }
        persist()
    }

    func delete(at offsets: IndexSet) {
        guard !DemoMode.isActive else { return }
        let removed = offsets.map { connections[$0].urlString }
        connections.remove(atOffsets: offsets)
        // The token goes with the connection, unless another entry still uses the URL.
        for url in removed where !connections.contains(where: { $0.urlString == url }) {
            ConnectionTokenKeychain.delete(url)
        }
        if let active = activeURLString, removed.contains(active) {
            activeURLString = connections.first?.urlString
            if let v = activeURLString { kv.set(v, forKey: Self.activeKey) } else { kv.removeObject(forKey: Self.activeKey) }
        }
        persist()
    }

    func setActive(_ urlString: String) {
        guard !DemoMode.isActive else { return }
        activeURLString = urlString
        kv.set(urlString, forKey: Self.activeKey)
        kv.synchronize()
    }

    func update(_ connection: SavedConnection) {
        guard let idx = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        let old = connections[idx].urlString
        connections[idx] = connection
        // An explicit edit may clear the token or move it to another URL.
        if (connection.token ?? "").isEmpty { ConnectionTokenKeychain.delete(connection.urlString) }
        if old != connection.urlString, !connections.contains(where: { $0.urlString == old }) {
            ConnectionTokenKeychain.delete(old)
        }
        persist()
    }

    func token(for urlString: String) -> String? {
        connections.first { $0.urlString == urlString }?.token
    }

    /// Tokens go to the Keychain; the key-value JSON carries none. If the Keychain
    /// refuses a token it stays in the JSON for now rather than being lost.
    private func persist() {
        // Nothing is saved from the demo: no connection, no token, no key-value write.
        guard !DemoMode.isActive else { return }
        var stored: [StoredConnection] = []
        for c in connections {
            var keep: String? = nil
            if let t = c.token, !t.isEmpty {
                let current = ConnectionTokenKeychain.read(c.urlString)
                if current != t.trimmingCharacters(in: .whitespacesAndNewlines),
                   !ConnectionTokenKeychain.write(t, for: c.urlString) {
                    keep = t
                }
            }
            stored.append(StoredConnection(id: c.id, label: c.label, urlString: c.urlString, token: keep))
        }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        kv.set(data, forKey: Self.connectionsKey)
        kv.synchronize()
    }

    private func load() {
        activeURLString = kv.string(forKey: Self.activeKey)
        guard let data = kv.data(forKey: Self.connectionsKey),
              let decoded = try? JSONDecoder().decode([StoredConnection].self, from: data) else { return }
        var needsScrub = false
        connections = decoded.map { d in
            var c = SavedConnection(id: d.id, label: d.label, urlString: d.urlString)
            let inKeychain = ConnectionTokenKeychain.read(d.urlString)
            if let legacy = d.token, !legacy.isEmpty {
                // A token still sitting in the key-value store: an entry from before
                // this build, or one an older build on another device wrote back.
                // A token already in the Keychain wins; otherwise move this one.
                if let current = inKeychain {
                    c.token = current
                    needsScrub = true
                } else if ConnectionTokenKeychain.write(legacy, for: d.urlString),
                          ConnectionTokenKeychain.read(d.urlString) != nil {
                    c.token = ConnectionTokenKeychain.read(d.urlString)
                    needsScrub = true
                } else {
                    c.token = legacy   // Keychain refused it: keep it rather than lose it.
                }
            } else {
                c.token = inKeychain
            }
            return c
        }
        if needsScrub { persist() }
    }

    // One-time migration from UserDefaults to NSUbiquitousKeyValueStore.
    private func migrateToKVStoreIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "savedConnections_kv_migrated") else { return }
        defer { UserDefaults.standard.set(true, forKey: "savedConnections_kv_migrated") }
        guard kv.data(forKey: Self.connectionsKey) == nil else { return }
        if let data = UserDefaults.standard.data(forKey: Self.connectionsKey) {
            kv.set(data, forKey: Self.connectionsKey)
        }
        if let active = UserDefaults.standard.string(forKey: Self.activeKey) {
            kv.set(active, forKey: Self.activeKey)
        }
        kv.synchronize()
    }

    // One-time migration from the old localURL / remoteURL keys
    private func migrateIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "savedConnections_migrated") else { return }
        defer { UserDefaults.standard.set(true, forKey: "savedConnections_migrated") }

        var toAdd: [SavedConnection] = []
        if let remote = UserDefaults.standard.string(forKey: "remoteURL"), !remote.isEmpty {
            toAdd.append(SavedConnection(label: SavedConnection.autoLabel(for: remote), urlString: remote))
        }
        if let local = UserDefaults.standard.string(forKey: "localURL"), !local.isEmpty,
           !toAdd.contains(where: { $0.urlString == local }) {
            toAdd.append(SavedConnection(label: "Local", urlString: local))
        }
        let fresh = toAdd.filter { c in !connections.contains(where: { $0.urlString == c.urlString }) }
        connections.append(contentsOf: fresh)
        if !fresh.isEmpty { persist() }

        if activeURLString == nil {
            activeURLString = UserDefaults.standard.string(forKey: "localURL")
                ?? UserDefaults.standard.string(forKey: "remoteURL")
        }
    }
}
#endif
