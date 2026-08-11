import Foundation

/// How a failed request explains itself to the user.
///
/// Split out of `APIClient.swift` on 2026-08-11 so that it can be compiled on
/// its own by `scripts/checks/connection-check.sh`. `APIClient` drags in
/// `ThinkingMode`, which lives in `ChatViewModel.swift`, which pulls in SwiftUI
/// — so nothing in that file could be checked without building the whole app.
/// These two types are pure functions of a status code and carry all the copy
/// that section C of TEST_PLAN.md is about, so they are the half worth isolating.
///
/// `ProbeResult` was nested inside `APIClient` and is now top level. No call site
/// changed: all four spelled it through type inference, never as
/// `APIClient.ProbeResult`.

/// Outcome of a connection probe, keeping "the server answered and refused us"
/// distinct from "we never got there".
///
/// Collapsing the two into a single `false` is actively misleading: a server
/// that rejects the request by `Host` header (Gate 0, see mira-core
/// `docs/remote-access.md`) answers `403` on a perfectly good connection, and
/// reporting that as "check your connection" sends the user hunting through
/// Tailscale and Wi-Fi for a problem that is one line of `mira.yaml`.
enum ProbeResult: Equatable {
    /// The probe returned 200 — the server is up and willing to talk to us.
    case ok
    /// We reached the server and it answered with a non-200 status.
    case refused(status: Int)
    /// The request never produced a response (DNS, TLS, routing, timeout).
    case unreachable(reason: String?)
}

extension ProbeResult {
    /// User-facing explanation, or `nil` when the probe succeeded.
    ///
    /// `target` is shown to the user, so pass the address they typed rather than
    /// the derived URL that was actually requested.
    func failureMessage(target: String? = nil) -> String? {
        let subject = target.map { "\($0)" } ?? "the server"
        switch self {
        case .ok:
            return nil
        case .refused(let status) where status == 403:
            // Gate 0 in mira-core rejects any Host header it doesn't recognise,
            // and a Tailscale MagicDNS name isn't recognised by default.
            return """
            \(subject) answered but refused this address. If you're connecting over \
            Tailscale, add the hostname to allowed_hosts in mira.yaml on your Mac and \
            restart Mira.
            """
        case .refused(let status) where status == 401:
            return "\(subject) needs a token. Check the Server Token field."
        case .refused(let status) where status == 503:
            return "\(subject) is still starting up. Try again in a moment."
        case .refused(let status):
            return "\(subject) answered with HTTP \(status)."
        case .unreachable(let reason):
            let base = "Could not reach \(subject). Check the URL, and that Tailscale is on."
            guard let reason, !reason.isEmpty else { return base }
            return "\(base) (\(reason))"
        }
    }
}

enum APIError: LocalizedError, Equatable {
    case invalidURL
    case unauthorized
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:        return "Invalid server URL"
        case .unauthorized:
            // Distinct from serverError so callers can offer to fix the token
            // instead of telling the user to check their connection.
            return "Not authorised — the server rejected this app's access token."
        case .serverError(let m): return m
        }
    }
}

extension APIError {
    /// The error a response status should surface as, or `nil` on success.
    ///
    /// Extracted from `APIClient.send` so the mapping can be checked without a
    /// server. The bug this guards is not hypothetical: every call site used to
    /// throw the response away and hand an error body straight to
    /// `JSONDecoder().decode(SuccessType.self)`, so a 401 surfaced as "The data
    /// couldn't be read because it is missing" — a decode error three layers from
    /// the actual cause, reading like data loss rather than an auth failure.
    static func from(status: Int, body: Data) -> APIError? {
        switch status {
        case 200..<300:
            return nil
        case 401, 403:
            return .unauthorized
        default:
            let detail = (try? JSONDecoder().decode(APIErrorResponse.self, from: body))?.detail
            return .serverError(detail ?? "Server error \(status)")
        }
    }
}

/// mira-core's error envelope: `{"detail": "..."}`.
struct APIErrorResponse: Decodable {
    let detail: String
}
