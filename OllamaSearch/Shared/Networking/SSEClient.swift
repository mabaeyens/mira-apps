import Foundation

/// Streams SSE events from the FastAPI server using URLSession async bytes.
///
/// Memory safety:
/// - Uses `AsyncThrowingStream` with `onTermination` to guarantee the inner
///   `Task` is cancelled when the consumer stops iterating (e.g. view dismissed).
/// - The caller must store the consuming `Task` and cancel it in `deinit`.
struct SSEClient {

    static let shared = SSEClient()
    private init() {}

    // Dedicated session for SSE: 300 s per-packet timeout (heartbeats arrive every 5 s,
    // so 60 s default would only drop on genuine connection loss — but 300 s makes the
    // intent explicit). 1-hour resource ceiling for the full stream.
    private static let sseSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 3600
        return URLSession(configuration: config)
    }()

    /// Opens an SSE stream for a POST /chat request.
    /// Yields typed `ServerEvent` values as they arrive.
    func stream(request: URLRequest) -> AsyncThrowingStream<ServerEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await SSEClient.sseSession.bytes(for: request)

                    // Surface non-200 as an error immediately
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        continuation.finish(throwing: SSEError.httpError(http.statusCode))
                        return
                    }

                    for try await line in bytes.lines {
                        // SSE format: "data: <json>"
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if let event = ServerEvent.parse(payload) {
                            continuation.yield(event)
                            // Do NOT break after `done` — the server emits `title`
                            // and `compress` events after `done` in the same stream.
                            // The server closes the connection naturally when finished.
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // When the consumer's `for await` loop exits (cancel or break),
            // cancel the inner task so we don't leak the URLSession data task.
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

enum SSEError: LocalizedError {
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "Server returned HTTP \(code)"
        }
    }
}
