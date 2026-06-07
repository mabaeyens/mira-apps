import Foundation

// ── Project ───────────────────────────────────────────────────────────────────

struct Project: Decodable, Identifiable {
    let id: String
    let name: String
    let localPath: String?
    let githubRepo: String?
    let createdAt: Int
    let lastUsed: Int
    let conversationCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case localPath         = "local_path"
        case githubRepo        = "github_repo"
        case createdAt         = "created_at"
        case lastUsed          = "last_used"
        case conversationCount = "conversation_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                = try  c.decode(String.self, forKey: .id)
        name              = try  c.decode(String.self, forKey: .name)
        localPath         = try? c.decode(String.self, forKey: .localPath)
        githubRepo        = try? c.decode(String.self, forKey: .githubRepo)
        createdAt         = try  c.decode(Int.self,    forKey: .createdAt)
        lastUsed          = try  c.decode(Int.self,    forKey: .lastUsed)
        conversationCount = (try? c.decode(Int.self,   forKey: .conversationCount)) ?? 0
    }

    var subtitle: String? {
        githubRepo ?? localPath.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    var icon: String { localPath != nil ? "folder" : "cloud" }
}

// ── Conversation ──────────────────────────────────────────────────────────────

// Pure data model — nonisolated so it can be used from the ConversationCache
// actor (the project defaults types to @MainActor isolation).
nonisolated struct Conversation: Decodable, Identifiable {
    let id: String
    let title: String
    let createdAt: Int
    let updatedAt: Int
    let modelName: String
    let messageCount: Int
    let projectId: String?

    enum CodingKeys: String, CodingKey {
        case id, title
        case createdAt    = "created_at"
        case updatedAt    = "updated_at"
        case modelName    = "model_name"
        case messageCount = "message_count"
        case projectId    = "project_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try  c.decode(String.self, forKey: .id)
        title        = try  c.decode(String.self, forKey: .title)
        createdAt    = try  c.decode(Int.self,    forKey: .createdAt)
        updatedAt    = try  c.decode(Int.self,    forKey: .updatedAt)
        modelName    = try  c.decode(String.self, forKey: .modelName)
        messageCount = (try? c.decode(Int.self,   forKey: .messageCount)) ?? 0
        projectId    = try? c.decode(String.self, forKey: .projectId)
    }

    init(id: String, title: String, createdAt: Int, updatedAt: Int,
         modelName: String, messageCount: Int, projectId: String? = nil) {
        self.id           = id
        self.title        = title
        self.createdAt    = createdAt
        self.updatedAt    = updatedAt
        self.modelName    = modelName
        self.messageCount = messageCount
        self.projectId    = projectId
    }
}

struct ConversationMessage: Decodable {
    let role: String
    let content: String
    let thinkingContent: String?
    enum CodingKeys: String, CodingKey {
        case role, content
        case thinkingContent = "thinking_content"
    }
}

// ── Memory ────────────────────────────────────────────────────────────────────

struct MemoryItem: Codable, Identifiable {
    let id: Int
    let text: String
    let createdAt: Double

    enum CodingKeys: String, CodingKey {
        case id, text
        case createdAt = "created_at"
    }
}
