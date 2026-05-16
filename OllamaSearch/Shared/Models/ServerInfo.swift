import Foundation

struct ServerInfo: Codable {
    let model: String
    let backend: String
    let host: String
    let contextWindow: Int
    let hardware: String
    let ssdCacheDir: String?
    let ssdCacheMaxSize: String?
    let hotCacheSize: String?

    enum CodingKeys: String, CodingKey {
        case model, backend, host, hardware
        case contextWindow = "context_window"
        case ssdCacheDir = "ssd_cache_dir"
        case ssdCacheMaxSize = "ssd_cache_max_size"
        case hotCacheSize = "hot_cache_size"
    }

    var contextWindowFormatted: String {
        let k = contextWindow / 1000
        return "\(k)k tokens"
    }

    var backendDisplayName: String {
        backend == "omlx" ? "oMLX" : "Ollama"
    }

    var ssdCacheDirShortened: String {
        guard let dir = ssdCacheDir else { return "—" }
        return dir.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var ssdCacheMaxSizeFormatted: String {
        guard let size = ssdCacheMaxSize else { return "—" }
        return size == "auto" ? "auto" : size
    }

    var hotCacheSizeFormatted: String {
        guard let size = hotCacheSize, size != "0" else { return "disabled" }
        return size
    }
}
