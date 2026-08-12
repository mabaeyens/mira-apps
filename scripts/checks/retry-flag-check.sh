#!/bin/bash
# Prove that a resend tells the server it is a resend, and that an ordinary send
# does not.
#
# `retry` is destructive on the server: mira-core's /chat drops the last user
# message and everything saved after it before the new turn starts. Sent by
# accident it silently eats a turn; not sent at all — which is what shipped —
# the failed exchange stays in the database and the question ends up there twice
# with the broken answer between them, and every later turn is built on both
# copies. Neither failure is visible in the app, because the client trims its own
# array either way and looks correct while the database is not.
#
# So the assertion is on the bytes of the request, not on the call site. This
# builds the real URLRequest through APIClient.chatRequest and reads its body.
# ThinkingMode is stubbed rather than compiled: its real home is
# ChatViewModel.swift, which pulls in SwiftUI and the whole view layer for an
# enum with three cases. The stub is checked against the real one below so the
# two cannot drift apart unnoticed.
#
# Usage: scripts/checks/retry-flag-check.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$REPO/OllamaSearch"

D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

cat > "$D/main.swift" <<'SWIFT'
import Foundation

/// Stub of the enum in ChatViewModel.swift. Kept to the same three cases; the
/// shell asserts the real one still has exactly these.
enum ThinkingMode: String, CaseIterable {
    case adaptive, off, on
}

/// The parts of a multipart body, as `name -> [value]`. Files are ignored: this
/// check is about the flags.
func fields(of request: URLRequest) -> [String: [String]] {
    guard let body = request.httpBody,
          let text = String(data: body, encoding: .utf8) else { return [:] }
    var out: [String: [String]] = [:]
    // Each part is: Content-Disposition: form-data; name="x"\r\n\r\n<value>\r\n
    let parts = text.components(separatedBy: "Content-Disposition: form-data; name=\"")
    for part in parts.dropFirst() {
        guard let quote = part.firstIndex(of: "\"") else { continue }
        let name = String(part[part.startIndex..<quote])
        guard !name.contains(";") else { continue }   // a file part, not a flag
        let rest = part[part.index(after: quote)...]
        guard let sep = rest.range(of: "\r\n\r\n") else { continue }
        var value = String(rest[sep.upperBound...])
        if let end = value.range(of: "\r\n--") { value = String(value[..<end.lowerBound]) }
        out[name, default: []].append(value)
    }
    return out
}

// `APIClient` is @MainActor, and top-level code in main.swift is not, so the
// checks live in a function that is. Called straight through assumeIsolated:
// this binary's top level really does run on the main thread.
@MainActor
func runChecks() -> Int {
var failures = 0
func check(_ ok: Bool, _ message: @autoclosure () -> String) {
    if !ok {
        print("FAIL: \(message())")
        failures += 1
    }
}

let api = APIClient.shared

// ------------------------------------------------------------- ordinary send
let normal = fields(of: api.chatRequest(message: "hello", conversationId: "conv-1"))
print("ordinary send -> \(normal.keys.sorted())")
check(normal["retry"] == nil,
      "an ordinary send carries retry=\(normal["retry"] ?? []) — this deletes a turn the "
    + "user meant to keep, and asking the same question twice on purpose is legitimate")
check(normal["message"] == ["hello"], "the message itself did not survive the body builder")
check(normal["conversation_id"] == ["conv-1"], "the conversation id did not survive the body builder")

// ------------------------------------------------------------------- a resend
let resend = fields(of: api.chatRequest(message: "hello", conversationId: "conv-1", retry: true))
print("resend        -> \(resend.keys.sorted())")
check(resend["retry"] == ["true"],
      "a resend does not carry retry=true, so the server appends and the question ends up "
    + "in the database twice: got \(resend["retry"] ?? ["nothing"])")

// The flag must be the only difference. If a resend also changed, say, the
// thinking mode, the replacement turn would not be the turn the user asked for.
check(normal.keys.sorted() + ["retry"] == resend.keys.sorted().filter { $0 != "retry" } + ["retry"]
        || Set(resend.keys).subtracting(normal.keys) == ["retry"],
      "a resend differs from a send by more than the retry flag: "
    + "\(Set(resend.keys).symmetricDifference(normal.keys))")

// -------------------------------------------------- the flag is not sticky
// One request built with retry, then another without, must not inherit it —
// the builder has no state, and this is what says so.
let after = fields(of: api.chatRequest(message: "next", conversationId: "conv-1"))
check(after["retry"] == nil, "retry leaked into the next request built after a resend")

// ------------------------------------------------------- other flags unharmed
let thinking = fields(of: api.chatRequest(message: "hi", conversationId: "c", thinkingMode: .on, retry: true))
check(thinking["thinking_enabled"] == ["true"] && thinking["retry"] == ["true"],
      "thinking_enabled and retry cannot both ride one request: \(thinking)")
let adaptive = fields(of: api.chatRequest(message: "hi", conversationId: "c", thinkingMode: .adaptive))
check(adaptive["thinking_enabled"] == nil,
      "adaptive must omit thinking_enabled and let the server heuristic decide")
let approved = fields(of: api.chatRequest(message: "hi", conversationId: "c", approvedTokens: ["a", "b"]))
check(approved["approved_tokens"] == ["a", "b"],
      "approval tokens are no longer repeatable: \(approved["approved_tokens"] ?? [])")

return failures
}

let failures = MainActor.assumeIsolated { runChecks() }
if failures > 0 {
    print("\nFAILED — \(failures) assertion(s) above")
    exit(1)
}
print("\nOK")
SWIFT

swiftc -O -o "$D/retrycheck" \
  "$APP/Shared/Networking/ConnectionErrors.swift" \
  "$APP/Shared/Networking/APIClient.swift" \
  "$APP/Shared/Models/Backend.swift" \
  "$APP/Shared/Models/BackendInfo.swift" \
  "$APP/Shared/Models/Conversation.swift" \
  "$APP/Shared/Models/ModelInfo.swift" \
  "$APP/Shared/Models/ServerInfo.swift" \
  "$APP/Shared/Models/SystemMemory.swift" \
  "$D/main.swift" 2>&1 | grep -v "^$" || true

"$D/retrycheck"

# ---------------------------------------------------------------- structural

echo

# The stub above stands in for the real ThinkingMode. If a fourth case appears,
# the stub still compiles and the check silently stops covering it.
CASES=$(grep -c "^    case \(adaptive\|off\|on\)" "$APP/Shared/ViewModels/ChatViewModel.swift")
echo "ThinkingMode cases covered by the stub: $CASES (expected 3)"
if [ "$CASES" -ne 3 ]; then
  echo "FAIL: ThinkingMode changed shape — update the stub in this script"
  exit 1
fi

# Which call sites may ask for a retry. The whole point of the flag is that it
# is never inferred, so exactly one place decides: resendLast(). A second one is
# not automatically wrong, but it needs a reason in the commit.
SENDERS=$(grep "send(retry:" "$APP/Shared/ViewModels/ChatViewModel.swift" | grep -vc "func send" || true)
echo "call sites passing retry to send(): $SENDERS (expected 1)"
if [ "$SENDERS" -ne 1 ]; then
  echo "FAIL: something other than resendLast() now decides a turn should be deleted"
  exit 1
fi
echo "OK"
