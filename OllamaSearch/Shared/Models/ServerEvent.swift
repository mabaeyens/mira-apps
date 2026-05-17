import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mab.mira", category: "ServerEvent")

// ── Data types carried by events ──────────────────────────────────────────────

struct FetchInfo: Decodable, Identifiable {
    var id: String { url }
    let url: String
    let chars: Int
    let preview: String
}

struct RAGChunk: Decodable, Identifiable {
    var id: String { source + preview }
    let source: String
    let score: Double
    let preview: String
}

struct SearchResult: Decodable, Identifiable {
    var id: String { url }
    let title: String
    let url: String
}

// ── Typed SSE event ───────────────────────────────────────────────────────────

enum ServerEvent {
    case thinking(String)
    case token(String)
    case searchStart(String)
    case searchDone(query: String, count: Int, results: [SearchResult])
    case fetchStart(String)
    case fetchDone(url: String, chars: Int)
    case fetchContext([FetchInfo])
    case ragIndexing(String)
    case ragDone(name: String, chunks: Int)
    case ragContext([RAGChunk])
    case stats(inputTokens: Int, outputTokens: Int, contextPct: Double)
    case done(String)
    case title(convId: String, title: String)
    case toolStart(name: String, label: String)
    case toolDone(name: String, label: String)
    case compress(String)
    case warning(String)
    case error(String)
    case heartbeat
}

// ── JSON parsing ──────────────────────────────────────────────────────────────

extension ServerEvent {
    /// Parse a single SSE `data:` payload into a typed event.
    /// Returns nil for unknown or malformed events (treated as no-ops).
    static func parse(_ jsonString: String) -> ServerEvent? {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type_ = obj["type"] as? String
        else { return nil }

        switch type_ {
        case "thinking":
            return .thinking(obj["content"] as? String ?? "")

        case "token":
            return .token(obj["content"] as? String ?? "")

        case "search_start":
            return .searchStart(obj["query"] as? String ?? "")

        case "search_done":
            let query   = obj["query"] as? String ?? ""
            let count   = obj["count"] as? Int ?? 0
            let rawList = obj["results"] as? [[String: Any]] ?? []
            let results = rawList.compactMap { r -> SearchResult? in
                guard let title = r["title"] as? String,
                      let url = r["url"] as? String else { return nil }
                return SearchResult(title: title, url: url)
            }
            return .searchDone(query: query, count: count, results: results)

        case "fetch_start":
            return .fetchStart(obj["url"] as? String ?? "")

        case "fetch_done":
            return .fetchDone(
                url: obj["url"] as? String ?? "",
                chars: obj["chars"] as? Int ?? 0
            )

        case "fetch_context":
            let raw = obj["fetches"] as? [[String: Any]] ?? []
            let fetches = raw.compactMap { r -> FetchInfo? in
                guard let url = r["url"] as? String,
                      let chars = r["chars"] as? Int,
                      let preview = r["preview"] as? String else { return nil }
                return FetchInfo(url: url, chars: chars, preview: preview)
            }
            return .fetchContext(fetches)

        case "rag_indexing":
            return .ragIndexing(obj["name"] as? String ?? "")

        case "rag_done":
            return .ragDone(
                name: obj["name"] as? String ?? "",
                chunks: obj["chunks"] as? Int ?? 0
            )

        case "rag_context":
            let raw = obj["chunks"] as? [[String: Any]] ?? []
            let chunks = raw.compactMap { r -> RAGChunk? in
                guard let source = r["source"] as? String,
                      let score = r["score"] as? Double,
                      let preview = r["preview"] as? String else { return nil }
                return RAGChunk(source: source, score: score, preview: preview)
            }
            return .ragContext(chunks)

        case "stats":
            return .stats(
                inputTokens: obj["input_tokens"] as? Int ?? 0,
                outputTokens: obj["output_tokens"] as? Int ?? 0,
                contextPct: obj["context_pct"] as? Double ?? 0
            )

        case "done":
            return .done(obj["content"] as? String ?? "")

        case "title":
            return .title(
                convId: obj["conv_id"] as? String ?? "",
                title: obj["title"] as? String ?? ""
            )

        case "tool_start":
            let name = obj["tool"] as? String ?? ""
            let label = obj["label"] as? String ?? name
            return .toolStart(name: name, label: label)

        case "tool_done":
            let name = obj["tool"] as? String ?? ""
            let label = obj["label"] as? String ?? name
            return .toolDone(name: name, label: label)

        case "compress":
            return .compress(obj["message"] as? String ?? "")

        case "warning":
            return .warning(obj["message"] as? String ?? "")

        case "error":
            return .error(obj["message"] as? String ?? "")

        case "heartbeat":
            return .heartbeat

        default:
            logger.debug("Unknown SSE event type: \(type_)")
            return nil
        }
    }
}
