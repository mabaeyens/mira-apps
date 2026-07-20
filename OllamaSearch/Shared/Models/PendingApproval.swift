import Foundation

/// A destructive action the server refused, awaiting explicit user approval.
///
/// The server derives `token` from the exact action text and only executes when
/// that same token comes back on a later `/chat` request. The model cannot mint
/// one, so approval can only originate from a user tap — never from model output
/// or from any text the model has read. See `mira-core/core/approvals.py`.
struct PendingApproval: Identifiable, Equatable {
    let id = UUID()
    /// Tool that was refused, e.g. `run_shell`, `delete_file`, `github_merge_pr`.
    let tool: String
    /// Action the token is bound to (usually the same as `tool`).
    let action: String
    /// The token to echo back on approval.
    let token: String
    /// The command or path the action would touch — what the user is judging.
    let target: String
    /// The guard pattern that matched, e.g. `rm -rf`.
    let matched: String
    /// Server-supplied explanation.
    let message: String

    /// Title for the confirmation prompt.
    var title: String {
        switch action {
        case "delete_file":          return "Delete file?"
        case "github_merge_pr":      return "Merge pull request?"
        case "github_delete_file":   return "Delete file on GitHub?"
        case "github_delete_branch": return "Delete branch?"
        default:                     return "Run destructive command?"
        }
    }

    /// Body text: the exact target, plus why it was flagged.
    var detail: String {
        var lines = [target]
        if !matched.isEmpty { lines.append("Matched: \(matched)") }
        if !message.isEmpty { lines.append(message) }
        return lines.joined(separator: "\n\n")
    }
}
