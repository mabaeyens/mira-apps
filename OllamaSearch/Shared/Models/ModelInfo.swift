import Foundation

struct ModelEntry: Decodable, Identifiable {
    var id: String { modelId }
    let modelId: String
    let displayName: String
    let sizeGb: Double
    let backend: String

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case displayName = "display_name"
        case sizeGb = "size_gb"
        case backend
    }
}

struct ActiveModel: Decodable {
    let backend: String
    let modelId: String

    enum CodingKeys: String, CodingKey {
        case backend
        case modelId = "model_id"
    }
}

struct ModelsResponse: Decodable {
    let mlxLm: [ModelEntry]
    let ollama: [ModelEntry]
    let active: ActiveModel

    enum CodingKeys: String, CodingKey {
        case mlxLm = "mlx_lm"
        case ollama
        case active
    }
}

struct PullProgress: Decodable {
    let type: String
    let percent: Int?
    let downloadedGb: Double?
    let totalGb: Double?
    let modelId: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case type
        case percent
        case downloadedGb = "downloaded_gb"
        case totalGb = "total_gb"
        case modelId = "model_id"
        case message
    }
}
