import Foundation

struct ServerInfo: Codable {
    let model: String
    let backend: String
    let host: String
    let contextWindow: Int
    let hardware: String

    enum CodingKeys: String, CodingKey {
        case model, backend, host, hardware
        case contextWindow = "context_window"
    }

    var contextWindowFormatted: String {
        let k = contextWindow / 1000
        return "\(k)k tokens"
    }

    var backendDisplayName: String {
        backend == "omlx" ? "oMLX" : "Ollama"
    }
}
