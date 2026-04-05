import Foundation

struct Conversation: Decodable, Identifiable {
    let id: String
    let title: String
    let createdAt: Int      // Unix timestamp (SQLite stores INTEGER)
    let updatedAt: Int
    let modelName: String
    let messageCount: Int   // total messages stored (user + assistant)

    enum CodingKeys: String, CodingKey {
        case id, title
        case createdAt    = "created_at"
        case updatedAt    = "updated_at"
        case modelName    = "model_name"
        case messageCount = "message_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(String.self, forKey: .id)
        title        = try c.decode(String.self, forKey: .title)
        createdAt    = try c.decode(Int.self,    forKey: .createdAt)
        updatedAt    = try c.decode(Int.self,    forKey: .updatedAt)
        modelName    = try c.decode(String.self, forKey: .modelName)
        messageCount = (try? c.decode(Int.self,  forKey: .messageCount)) ?? 0
    }

    // Used by the title-event handler to update a title in-place
    init(id: String, title: String, createdAt: Int, updatedAt: Int,
         modelName: String, messageCount: Int) {
        self.id           = id
        self.title        = title
        self.createdAt    = createdAt
        self.updatedAt    = updatedAt
        self.modelName    = modelName
        self.messageCount = messageCount
    }
}

struct ConversationMessage: Decodable {
    let role: String          // "user" | "assistant"
    let content: String
    // Server only returns {role, content} — no id/timestamps
}
