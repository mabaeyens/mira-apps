import Foundation

/// Demo mode: the chat UI with a few bundled sample conversations and no server.
///
/// `APIClient.baseURL` is pointed at `DemoMode.baseURL`, a host under the
/// reserved `.invalid` top-level domain, and `DemoURLProtocol` answers every
/// request for it from memory. Nothing else in the app knows it is a demo
/// except the writers, which refuse to persist anything while it is on.
///
/// Rules, all enforced here or in `DemoURLProtocol`:
/// - no request leaves the device: while demo is on, a request to any other
///   host from `URLSession.shared` or the SSE session fails locally;
/// - nothing outlives the process: no Keychain item, no iCloud key-value or
///   iCloud Drive write, no transcript cache, no saved connection, so the next
///   launch is the first-run screen again;
/// - every demo conversation id starts with `idPrefix`, so a cache write that
///   was scheduled in demo and runs after it ended is still refused.
nonisolated enum DemoMode {

    static let host = "mira-demo.invalid"
    /// https only so the URL passes App Transport Security checks on its way to
    /// the protocol handler. No connection is ever opened for it.
    static let baseURL = URL(string: "https://mira-demo.invalid")!
    static let idPrefix = "demo-"

    private static let state = DemoState()

    static var isActive: Bool { state.read { $0.active } }

    static func isDemoID(_ id: String) -> Bool { id.hasPrefix(idPrefix) }

    /// Call once at launch. Covers `URLSession.shared`; a session with its own
    /// configuration lists `DemoURLProtocol` in `protocolClasses` itself.
    static func register() {
        URLProtocol.registerClass(DemoURLProtocol.self)
    }

    static func enter() {
        DemoStore.shared.reset()
        state.write { $0.active = true; $0.served = 0; $0.blocked = 0 }
    }

    static func exit() {
        state.write { $0.active = false }
        DemoStore.shared.reset()
    }

    // ── Counters, for the UI test ─────────────────────────────────────────────

    static func noteServed() { state.write { $0.served += 1 } }
    static func noteBlocked() { state.write { $0.blocked += 1 } }
    /// Requests answered from memory, and requests to any other host refused,
    /// since demo was entered.
    static var counters: (served: Int, blocked: Int) { state.read { ($0.served, $0.blocked) } }
}

private nonisolated final class DemoState: @unchecked Sendable {
    struct Values { var active = false; var served = 0; var blocked = 0 }
    private let lock = NSLock()
    private var values = Values()

    func read<T>(_ body: (Values) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(values)
    }

    func write(_ body: (inout Values) -> Void) {
        lock.lock(); defer { lock.unlock() }
        body(&values)
    }
}

// ── In-memory store ───────────────────────────────────────────────────────────

/// What the demo "server" holds. Seeded from `DemoContent`, changed only in
/// memory, emptied again on enter and on exit.
nonisolated final class DemoStore: @unchecked Sendable {
    static let shared = DemoStore()

    struct Entry {
        let role: String
        let content: String
        var thinking: String? = nil
    }

    struct Conversation {
        let id: String
        var title: String
        let createdAt: Int
        var updatedAt: Int
        var messages: [Entry]
    }

    private let lock = NSLock()
    private var conversations: [Conversation] = []
    private var memories: [[String: Any]] = []
    private var nextMemoryID = 1

    func reset() {
        lock.lock(); defer { lock.unlock() }
        conversations = DemoContent.conversations(now: Date())
        memories = []
        nextMemoryID = 1
    }

    func conversationList() -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return conversations.sorted { $0.updatedAt > $1.updatedAt }.map {
            ["id": $0.id, "title": $0.title, "created_at": $0.createdAt, "updated_at": $0.updatedAt,
             "model_name": DemoContent.modelName, "message_count": $0.messages.count]
        }
    }

    func messages(for id: String) -> [[String: Any]]? {
        lock.lock(); defer { lock.unlock() }
        guard let conv = conversations.first(where: { $0.id == id }) else { return nil }
        return conv.messages.map { m in
            var row: [String: Any] = ["role": m.role, "content": m.content]
            if let thinking = m.thinking { row["thinking_content"] = thinking }
            return row
        }
    }

    func exists(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return conversations.contains { $0.id == id }
    }

    func create(title: String = "New conversation") -> String {
        lock.lock(); defer { lock.unlock() }
        let id = DemoMode.idPrefix + UUID().uuidString.lowercased()
        let now = Int(Date().timeIntervalSince1970)
        conversations.append(Conversation(id: id, title: title, createdAt: now, updatedAt: now, messages: []))
        return id
    }

    func rename(_ id: String, title: String) {
        lock.lock(); defer { lock.unlock() }
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].title = title
    }

    func delete(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        conversations.removeAll { $0.id == id }
    }

    func append(_ entries: [Entry], to id: String) {
        lock.lock(); defer { lock.unlock() }
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].messages.append(contentsOf: entries)
        conversations[i].updatedAt = Int(Date().timeIntervalSince1970)
    }

    func memoryList() -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return memories
    }

    func addMemory(_ text: String) -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        let item: [String: Any] = ["id": nextMemoryID, "text": text, "created_at": Date().timeIntervalSince1970]
        nextMemoryID += 1
        memories.insert(item, at: 0)
        return item
    }

    func deleteMemory(_ id: Int) {
        lock.lock(); defer { lock.unlock() }
        memories.removeAll { ($0["id"] as? Int) == id }
    }
}

// ── Sample content ────────────────────────────────────────────────────────────

nonisolated enum DemoContent {

    static let modelName = "Sample model"
    static let backend = "demo"
    static let contextWindow = 32_000
    static let unavailable = "Not available in the demo. Connect your Mac to use this."

    /// The reply to anything sent in demo. Streamed a word at a time.
    static let replyThinking = """
    This is the demo, so there is no model behind this conversation. \
    The useful answer is to say so plainly and explain how to connect a real Mac.
    """

    static let reply = """
    This is a demo, so this reply is canned: no model ran, and nothing you typed left this device or was saved.

    Mira runs on your own Mac, and this app is how you talk to it. To connect yours:

    1. Install Mira on your Mac from askmira.es and open it.
    2. Click the Mira icon in the Mac's menu bar and choose **Pair iPhone…**
    3. Here, tap **Exit demo**, then **Add connection**, then **Scan QR from your Mac**.

    From then on your conversations live on your Mac, and replies come from the model running there.
    """

    static func conversations(now: Date) -> [DemoStore.Conversation] {
        let t = Int(now.timeIntervalSince1970)
        let hour = 3_600, day = 86_400
        return [
            DemoStore.Conversation(
                id: DemoMode.idPrefix + "lisbon", title: "A weekend in Lisbon",
                createdAt: t - 2 * hour, updatedAt: t - 2 * hour + 240,
                messages: [
                    .init(role: "user", content: "I have two days in Lisbon in March. What would you do?"),
                    .init(role: "assistant", content: """
                    Two days is enough for the old centre and one trip out. A plan that keeps the walking sensible:

                    **Day 1: Alfama and Baixa**

                    - Start at the Miradouro de Santa Luzia before the tour groups arrive, then walk down through Alfama rather than up it.
                    - Lunch near the Sé. Grilled fish is the safe order almost anywhere.
                    - Afternoon in Baixa and Chiado: Praça do Comércio, the Santa Justa lift (look at it, skip the queue), and a coffee at A Brasileira.
                    - Evening in Bairro Alto if you want it lively, or back in Alfama for fado.

                    **Day 2: Belém, then the river**

                    - Tram 15 or the train to Belém. Jerónimos Monastery first, it gets busy by eleven.
                    - Pastéis de Belém is worth the queue, which moves faster than it looks.
                    - Walk the riverfront to the Torre de Belém and the MAAT.
                    - Back in town, LX Factory for dinner.

                    March is mild but showery, so bring a light rain jacket, and shoes with grip: the pavements are polished stone and they are slippery when wet.
                    """),
                    .init(role: "user", content: "Is the Lisboa Card worth it for that?"),
                    .init(role: "assistant", content: """
                    For this plan, a 24-hour card on day 2 is the only one that pays for itself. Jerónimos and the Torre de Belém are both included, and so is the train out there.

                    Day 1 is nearly all walking and viewpoints, which cost nothing, so a card would sit unused. Pay per ride that day instead.
                    """),
                ]),
            DemoStore.Conversation(
                id: DemoMode.idPrefix + "sky", title: "Why is the sky blue?",
                createdAt: t - day - 3 * hour, updatedAt: t - day - 3 * hour + 60,
                messages: [
                    .init(role: "user", content: "Why is the sky blue? Short answer please."),
                    .init(role: "assistant", content: """
                    Sunlight is a mix of colours, and air molecules scatter the short blue wavelengths far more strongly than the long red ones. That scattered blue light reaches your eyes from every direction, so the whole sky looks blue.

                    At sunset the light crosses much more air, most of the blue is scattered away before it reaches you, and what is left is red and orange.
                    """, thinking: """
                    The user wants it short. The mechanism is Rayleigh scattering: scattering strength goes with the inverse fourth power of wavelength, so blue (about 450 nm) scatters several times more than red (about 700 nm). \
                    Violet scatters even more, but the sun emits less of it and eyes are less sensitive to it, so the sky reads as blue. I will leave violet out unless asked, and add one line on sunsets because it is the natural follow-up.
                    """),
                ]),
            DemoStore.Conversation(
                id: DemoMode.idPrefix + "debounce", title: "Debounce a search field in SwiftUI",
                createdAt: t - 3 * day, updatedAt: t - 3 * day + 120,
                messages: [
                    .init(role: "user", content: "How do I debounce a search field in SwiftUI without Combine?"),
                    .init(role: "assistant", content: """
                    Use `task(id:)`. It cancels the previous task whenever the id changes, so a short sleep at the top is a debounce:

                    ```swift
                    struct SearchView: View {
                        @State private var query = ""
                        @State private var results: [String] = []

                        var body: some View {
                            List(results, id: \\.self) { Text($0) }
                                .searchable(text: $query)
                                .task(id: query) {
                                    try? await Task.sleep(for: .milliseconds(300))
                                    guard !Task.isCancelled else { return }
                                    results = await search(query)
                                }
                        }
                    }
                    ```

                    Each keystroke changes `query`, which cancels the sleeping task and starts a new one. Only the task that survives 300 ms runs the search.
                    """),
                ]),
        ]
    }
}
