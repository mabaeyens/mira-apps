import Foundation

/// The one place that turns a backend id from mira-core into something to show
/// a user.
///
/// There used to be three: `ChatViewModel.backendLabel`, a computed property on
/// `ServerInfo`, and an inline ternary chain in `InputBar`. Each knew a
/// different subset of ids and **all three ended `: "Ollama"`**, so any backend
/// they had not been taught about was reported as Ollama. That stopped being
/// theoretical when the default became `mira-mlx` in July 2026: the About panel,
/// the only place on macOS to see what is running, said Ollama while mira-mlx
/// served every token.
///
/// The rule that replaces the fallback: an id we do not recognise renders as
/// itself. A wrong-but-plausible name is worse than an unfamiliar one, because
/// a user can act on it.
enum Backend {

    /// Ids mira-core uses, mapped to the spelling each project prefers.
    /// Anything absent here is not an error, it just renders as its own id.
    private static let known: [String: String] = [
        "omlx":     "oMLX",
        "dflash":   "dFlash",
        "mlx-lm":   "mlx-lm",
        "ollama":   "Ollama",
        "mira-mlx": "mira-mlx",
        "vllm-mlx": "vllm-mlx",
    ]

    /// Display label for a backend id. Empty in, empty out — callers decide what
    /// to show before `/backend` has answered, since "" is not a backend.
    static func label(for id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        // Match loosely so a separator or capitalisation difference on the
        // server side is a cosmetic mismatch, not a silent fallback.
        let key = trimmed.lowercased().replacingOccurrences(of: "_", with: "-")
        return known[key] ?? trimmed
    }
}
