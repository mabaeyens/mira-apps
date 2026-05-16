import Foundation

struct BackendInfo: Codable {
    let backend: String
    let model: String
    let host: String
    let contextWindow: Int

    enum CodingKeys: String, CodingKey {
        case backend, model, host
        case contextWindow = "context_window"
    }
}
