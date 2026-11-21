import Foundation

/// A pairing link from the Mac: `mira://pair?u=<https url>&n=<label>#t=<base64url token>`.
///
/// Https only, by design: pairing is offered over Tailscale, never plain HTTP or LAN.
/// The token travels in the fragment so it never reaches a request line or a log.
struct PairingPayload: Equatable {
    let url: String
    let label: String?
    let token: String

    /// Fixed strings only. None may ever include the token or any part of the input.
    enum PairingError: Error, Equatable {
        case notPairingLink
        case notHTTPS
        case missingToken

        var message: String {
            switch self {
            case .notPairingLink: return "Not a Mira pairing code."
            case .notHTTPS:       return "Pairing links must use https."
            case .missingToken:   return "This pairing code has no token."
            }
        }
    }

    static func looksLikePairingLink(_ string: String) -> Bool {
        string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("mira:")
    }

    static func parse(_ string: String) -> Result<PairingPayload, PairingError> {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              comps.scheme?.lowercased() == "mira",
              comps.host?.lowercased() == "pair" else {
            return .failure(.notPairingLink)
        }

        let items = comps.queryItems ?? []
        guard let u = items.first(where: { $0.name == "u" })?.value,
              let target = URLComponents(string: u),
              let scheme = target.scheme?.lowercased() else {
            return .failure(.notPairingLink)
        }
        guard scheme == "https", let host = target.host, !host.isEmpty else {
            return .failure(.notHTTPS)
        }

        guard let token = token(fromFragment: comps.percentEncodedFragment) else {
            return .failure(.missingToken)
        }

        let label = items.first(where: { $0.name == "n" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .success(PairingPayload(
            url: u,
            label: (label?.isEmpty == false) ? label : nil,
            token: token))
    }

    private static func token(fromFragment fragment: String?) -> String? {
        guard let fragment else { return nil }
        for part in fragment.split(separator: "&") where part.hasPrefix("t=") {
            let raw = String(part.dropFirst(2))
            guard !raw.isEmpty,
                  raw.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "=") })
            else { return nil }
            // The token is itself the base64url text of random bytes (the same
            // string the server holds), not an encoding of a text token, so it
            // is passed through verbatim, without decoding, minus any padding.
            let text = raw.replacingOccurrences(of: "=", with: "")
            return text.isEmpty ? nil : text
        }
        return nil
    }
}
