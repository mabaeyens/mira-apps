#if os(iOS)
import Foundation
import SwiftUI

struct SavedConnection: Codable, Identifiable, Hashable {
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
        migrateIfNeeded()
        seedKnownConnections()
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
        guard !connections.contains(where: { $0.urlString == connection.urlString }) else { return }
        connections.insert(connection, at: 0)
        persist()
    }

    func delete(at offsets: IndexSet) {
        let removed = offsets.map { connections[$0].urlString }
        connections.remove(atOffsets: offsets)
        if let active = activeURLString, removed.contains(active) {
            activeURLString = connections.first?.urlString
            UserDefaults.standard.set(activeURLString, forKey: Self.activeKey)
        }
        persist()
    }

    func setActive(_ urlString: String) {
        activeURLString = urlString
        UserDefaults.standard.set(urlString, forKey: Self.activeKey)
    }

    func update(_ connection: SavedConnection) {
        guard let idx = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        connections[idx] = connection
        persist()
    }

    func token(for urlString: String) -> String? {
        connections.first { $0.urlString == urlString }?.token
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        UserDefaults.standard.set(data, forKey: Self.connectionsKey)
    }

    private func load() {
        activeURLString = UserDefaults.standard.string(forKey: Self.activeKey)
        guard let data = UserDefaults.standard.data(forKey: Self.connectionsKey),
              let decoded = try? JSONDecoder().decode([SavedConnection].self, from: data) else { return }
        connections = decoded
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
