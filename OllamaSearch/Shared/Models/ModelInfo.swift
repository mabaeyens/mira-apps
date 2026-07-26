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

/// One backend's slice of the local library, as `GET /models` reports it.
///
/// `available` is "could this backend be started at all", which is a different
/// question from whether it has models: Ollama installed with its daemon down
/// is available, has no models, and carries a `detail` saying to start it.
struct BackendLibrary: Decodable, Identifiable {
    var id: String { backend }
    let backend: String
    let available: Bool
    let detail: String
    let models: [ModelEntry]
}

struct ModelsResponse: Decodable {
    /// Every backend the server knows how to start. The flat `mlxLm` and
    /// `ollama` below are the older shape of the same data, minus four backends.
    let backends: [BackendLibrary]
    let mlxLm: [ModelEntry]
    let ollama: [ModelEntry]
    let active: ActiveModel

    enum CodingKeys: String, CodingKey {
        case backends
        case mlxLm = "mlx_lm"
        case ollama
        case active
    }

    /// Size on disk for a model under a given backend, or nil if unknown.
    func sizeGb(backend: String, model: String) -> Double? {
        backends.first { $0.backend == backend }?
            .models.first { $0.modelId == model }?
            .sizeGb
    }
}

struct BackendPreset: Decodable, Identifiable {
    let id: String
    let label: String
    let backend: String
    let model: String
    let contextWindow: Int
    let active: Bool
    /// False when the backend is not installed or the model is not on disk, so
    /// switching to it would fail. Servers older than 2026-07-26 do not send
    /// this; they offered everything unconditionally, so absent means true.
    let available: Bool
    /// Why `available` is false. Empty otherwise.
    let detail: String

    enum CodingKeys: String, CodingKey {
        case id, label, backend, model, active, available, detail
        case contextWindow = "context_window"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        backend = try c.decode(String.self, forKey: .backend)
        model = try c.decode(String.self, forKey: .model)
        contextWindow = try c.decode(Int.self, forKey: .contextWindow)
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? false
        available = try c.decodeIfPresent(Bool.self, forKey: .available) ?? true
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
    }

    init(id: String, label: String, backend: String, model: String,
         contextWindow: Int, active: Bool, available: Bool = true, detail: String = "") {
        self.id = id
        self.label = label
        self.backend = backend
        self.model = model
        self.contextWindow = contextWindow
        self.active = active
        self.available = available
        self.detail = detail
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
