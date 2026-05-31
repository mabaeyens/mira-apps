import Foundation

/// A single chat bubble displayed in the UI.
struct Message: Identifiable {
    enum Role { case user, assistant, info }

    let id = UUID()
    let role: Role
    var content: String              // grows as tokens stream in
    var thinkingContent: String?     // persisted thinking block, if any
    var fetchContext: [FetchInfo]    // web pages read this turn
    var ragContext: [RAGChunk]       // document chunks used this turn
    var isStreaming: Bool             // true while tokens are still arriving
    var imageAttachments: [Data]     // raw image bytes attached to user messages

    init(role: Role, content: String = "", thinkingContent: String? = nil, imageAttachments: [Data] = []) {
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.fetchContext = []
        self.ragContext = []
        self.isStreaming = role == .assistant && content.isEmpty
        self.imageAttachments = imageAttachments
    }

    static func info(_ text: String) -> Message {
        Message(role: .info, content: text)
    }
}
