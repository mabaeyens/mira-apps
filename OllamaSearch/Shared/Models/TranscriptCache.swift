import Foundation

/// The last transcript the server returned for each conversation, so opening a
/// conversation can paint at once and refresh behind what is already on screen.
///
/// Local to this device on purpose: the Caches directory is neither backed up
/// nor synced, and the system may empty it, which costs one spinner. It is not
/// the iCloud container `ConversationCache` uses for the conversation list:
/// full transcripts are larger and more private than titles.
///
/// Only server-confirmed content is written here. A turn that is still running
/// or awaited is never cached, so a stale copy can lack the newest turn but
/// cannot contain one the server does not have.
actor TranscriptCache {
    static let shared = TranscriptCache()

    nonisolated struct Entry: Codable, Sendable {
        let role: String
        let content: String
        let thinkingContent: String?
    }

    /// Most recently written transcripts kept on disk.
    private let maxFiles = 80
    private var resolvedDirectory: URL?

    private func directory() -> URL {
        if let url = resolvedDirectory { return url }
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("transcripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        resolvedDirectory = url
        return url
    }

    /// Conversation ids are server-generated; anything that is not a plain
    /// token is refused rather than turned into a path.
    private func fileURL(for id: String) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !id.isEmpty, id.count <= 128,
              id.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return directory().appendingPathComponent("\(id).json")
    }

    func save(_ entries: [Entry], for id: String) {
        guard let url = fileURL(for: id), !entries.isEmpty,
              let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
        prune()
    }

    func load(_ id: String) -> [Entry]? {
        guard let url = fileURL(for: id),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Entry].self, from: data)
    }

    func remove(_ id: String) {
        guard let url = fileURL(for: id) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func prune() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory(), includingPropertiesForKeys: keys
        ), files.count > maxFiles else { return }
        let dated = files.map { url -> (URL, Date) in
            let date = (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
            return (url, date)
        }
        for (url, _) in dated.sorted(by: { $0.1 > $1.1 }).dropFirst(maxFiles) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
