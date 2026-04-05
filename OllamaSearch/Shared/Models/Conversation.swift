import Foundation

struct Conversation: Decodable, Identifiable {
    let id: String
    let title: String
    let createdAt: String
    let updatedAt: String
    let modelName: String

    enum CodingKeys: String, CodingKey {
        case id, title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case modelName = "model_name"
    }
}

struct ConversationMessage: Decodable, Identifiable {
    let id: String
    let conversationId: String
    let role: String          // "user" | "assistant"
    let content: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, role, content
        case conversationId = "conversation_id"
        case createdAt = "created_at"
    }
}
