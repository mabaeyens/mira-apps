import Foundation

/// The server's verdict on its own machine's memory, relayed by `GET /hardware`.
///
/// This is the only field that should drive UI. The numbers alongside it in
/// `SystemMemory` are for a diagnostics view — re-reading them here to invent a
/// different verdict would put the threshold logic in two places, and the server
/// is the half that actually measured it.
enum MemoryAdvisory: String, Decodable {
    /// Nothing to say. Show nothing.
    case ok
    /// The machine is under memory pressure but the model is still resident.
    /// At most a quiet indicator — never interrupt anything for this.
    case busy
    /// The model has been compressed out of RAM. Measured 2026-08-08 on an
    /// M5/32GB: a reply in that state cost 15.37s against a warm 0.47s.
    /// This is the one worth telling someone about.
    ///
    /// Who pays that cost is no longer fixed. Since mira-core `13ba3db` the
    /// server can reclaim the model on its own idle branch, so the next reply
    /// may well be fast. But it skips that work under critical pressure, on
    /// battery, without enough headroom, or when `proactive_decompress` is off
    /// — and it is off by default. Nothing in `system_memory` says which case
    /// this is, so the copy must not predict one.
    case evicted
    /// macOS reports critical memory pressure.
    case critical
    /// The probe failed, the backend is still starting, or it is not mira-mlx.
    /// Absence is not health, but it is not a problem to report to a user either
    /// — so this shows nothing.
    case unknown

    /// Decode an unrecognised string as `.unknown` instead of throwing. A newer
    /// server adding a fifth level must not take the whole `/hardware` decode
    /// down with it.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MemoryAdvisory(rawValue: raw) ?? .unknown
    }
}

extension MemoryAdvisory {
    /// What to tell the user, or nil for the states that must stay silent.
    ///
    /// Says what it means for them rather than what the number is: "compressor
    /// occupancy 17.03GB" is true and useless. It also names *the Mac running
    /// Mira* on purpose — an iPhone connecting to a remote Mac gets this same
    /// field, and it must never read as if the phone were short of memory.
    var advisoryText: String? {
        switch self {
        case .evicted:
            // Deliberately does NOT promise a slow reply. The server may reclaim
            // the model on idle before the user types anything, in which case a
            // warning that "the next reply will be slow" is simply false — and a
            // banner that cries wolf is worse than no banner. "may be slow until
            // it loads back in" is true whether or not that reclaim happens.
            return "Something else on the Mac running Mira pushed its model out of memory. "
                 + "Replies may be slow until it loads back in."
        case .critical:
            return "The Mac running Mira is very low on memory. "
                 + "Replies may be slow until something else frees some up."
        case .ok, .busy, .unknown:
            return nil
        }
    }
}

/// Live memory state of the machine running the inference backend.
///
/// Every field is optional and the whole object is absent on an older server, a
/// non-mira-mlx backend, or a backend that is still starting. Decoding must
/// survive all three — that is the actual regression risk in reading this
/// endpoint, so there is no forced unwrap anywhere in here.
struct SystemMemory: Decodable {
    let advisory: MemoryAdvisory

    // Diagnostics only. Nothing below this line should drive UI. In particular
    // `pressureLevel` is deliberately not used for display: measured 2026-08-08,
    // 8.64GB had already been taken while macOS still reported level 1, so the
    // derived `advisory` had flipped before the OS admitted anything was wrong.
    let ceilingBytes: Int?
    let staticCeilingBytes: Int?
    let availableBytes: Int?
    let compressorBytes: Int?
    let otherProcessesBytes: Int?
    let pressureLevel: Int?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case advisory
        case ceilingBytes = "ceiling_bytes"
        case staticCeilingBytes = "static_ceiling_bytes"
        case availableBytes = "available_bytes"
        case compressorBytes = "compressor_bytes"
        case otherProcessesBytes = "other_processes_bytes"
        case pressureLevel = "pressure_level"
        case source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A missing or null `advisory` is "no information", same as an
        // unrecognised one. It is never read as health.
        advisory = try c.decodeIfPresent(MemoryAdvisory.self, forKey: .advisory) ?? .unknown
        ceilingBytes = try c.decodeIfPresent(Int.self, forKey: .ceilingBytes)
        staticCeilingBytes = try c.decodeIfPresent(Int.self, forKey: .staticCeilingBytes)
        availableBytes = try c.decodeIfPresent(Int.self, forKey: .availableBytes)
        compressorBytes = try c.decodeIfPresent(Int.self, forKey: .compressorBytes)
        otherProcessesBytes = try c.decodeIfPresent(Int.self, forKey: .otherProcessesBytes)
        pressureLevel = try c.decodeIfPresent(Int.self, forKey: .pressureLevel)
        source = try c.decodeIfPresent(String.self, forKey: .source)
    }
}

/// `GET /hardware` — why this machine got the context window and cache budget it
/// did, plus `systemMemory`, the live half describing what it can do right now
/// given whatever else is running.
///
/// Every field is optional so that an older server, or one that grows new keys,
/// still decodes.
struct HardwareInfo: Decodable {
    let systemMemory: SystemMemory?

    let totalRamGb: Double?
    let model: String?
    let modelWeightGb: Double?
    let derivedContextWindow: Int?
    let activeContextWindow: Int?

    enum CodingKeys: String, CodingKey {
        case systemMemory = "system_memory"
        case totalRamGb = "total_ram_gb"
        case model
        case modelWeightGb = "model_weight_gb"
        case derivedContextWindow = "derived_context_window"
        case activeContextWindow = "active_context_window"
    }
}
