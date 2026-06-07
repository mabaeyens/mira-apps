import Foundation

// Writes conversations to the iCloud Drive container (falls back to local
// Documents) so the list is readable when the backend is unreachable.
actor ConversationCache {
    static let shared = ConversationCache()
    private let containerID = "iCloud.com.mab.OllamaSearch"
    private var resolvedURL: URL?

    private func cacheURL() -> URL {
        if let url = resolvedURL { return url }
        let url: URL
        if let ubiquity = FileManager.default.url(forUbiquityContainerIdentifier: containerID) {
            let docs = ubiquity.appendingPathComponent("Documents")
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            url = docs.appendingPathComponent("conversations.json")
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            url = docs.appendingPathComponent("mira_conversations.json")
        }
        resolvedURL = url
        return url
    }

    func save(_ conversations: [Conversation]) {
        let file = CachedFile(
            savedAt: Date().timeIntervalSince1970,
            conversations: conversations.map { CachedConv($0) }
        )
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: cacheURL())
    }

    func load() -> (conversations: [Conversation], savedAt: Date)? {
        guard let data = try? Data(contentsOf: cacheURL()),
              let file = try? JSONDecoder().decode(CachedFile.self, from: data) else { return nil }
        let convs = file.conversations.map(\.asConversation)
        return (convs, Date(timeIntervalSince1970: file.savedAt))
    }
}

// ── Private wire types ────────────────────────────────────────────────────────

private nonisolated struct CachedFile: Codable {
    let savedAt: Double
    let conversations: [CachedConv]
}

private nonisolated struct CachedConv: Codable {
    let id: String
    let title: String
    let createdAt: Int
    let updatedAt: Int
    let modelName: String
    let messageCount: Int
    let projectId: String?

    init(_ c: Conversation) {
        id = c.id; title = c.title; createdAt = c.createdAt; updatedAt = c.updatedAt
        modelName = c.modelName; messageCount = c.messageCount; projectId = c.projectId
    }

    var asConversation: Conversation {
        Conversation(id: id, title: title, createdAt: createdAt, updatedAt: updatedAt,
                     modelName: modelName, messageCount: messageCount, projectId: projectId)
    }
}
