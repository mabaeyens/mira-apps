import Foundation

struct Conversation: Decodable, Identifiable {
    let id: String
    let title: String
    let createdAt: Int      // Unix timestamp (SQLite stores INTEGER)
    let updatedAt: Int
    let modelName: String

    enum CodingKeys: String, CodingKey {
        case id, title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case modelName = "model_name"
    }
}

struct ConversationMessage: Decodable {
    let role: String          // "user" | "assistant"
    let content: String
    // Server only returns {role, content} — no id/timestamps
}
