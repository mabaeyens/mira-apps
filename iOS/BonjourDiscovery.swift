import Foundation
import Network

/// Discovers the OllamaSearch server on the local network via Bonjour (mDNS).
///
/// Memory safety:
/// - `browser` is cancelled in `deinit` — NWBrowser retains its update
///   handler closure strongly, so explicit cancellation is required.
@MainActor
@Observable
final class BonjourDiscovery {

    var discoveredURL: URL?
    var isSearching = false

    private var browser: NWBrowser?

    deinit {
        browser?.cancel()
    }

    func start() {
        guard browser == nil else { return }
        isSearching = true

        let params = NWParameters()
        params.includePeerToPeer = true

        let b = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_ollamasearch._tcp", domain: "local."),
            using: params
        )

        b.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                if case .failed = state { self?.isSearching = false }
            }
        }

        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Take the first result — for personal use there's only one server
                if let result = results.first,
                   case .service(let name, _, _, _) = result.endpoint {
                    // Resolve host + port
                    self.resolveEndpoint(result.endpoint)
                }
            }
        }

        b.start(queue: .main)
        browser = b
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }

    private func resolveEndpoint(_ endpoint: NWEndpoint) {
        // Use NWConnection to resolve the endpoint to a host:port string
        let conn = NWConnection(to: endpoint, using: .tcp)
        conn.stateUpdateHandler = { [weak self] state in
            if case .ready = state,
               case .hostPort(let host, let port) = conn.currentPath?.remoteEndpoint {
                let ipString = "\(host)"
                    .replacingOccurrences(of: "%", with: "")   // strip IPv6 scope
                Task { @MainActor [weak self] in
                    self?.discoveredURL = URL(string: "http://\(ipString):\(port)")
                    self?.isSearching = false
                }
                conn.cancel()
            }
            if case .failed = state { conn.cancel() }
        }
        conn.start(queue: .main)
    }
}
