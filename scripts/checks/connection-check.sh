#!/bin/bash
# Prove that a failed request still says what actually went wrong.
#
# Compiles ConnectionErrors.swift standalone and asserts the two mappings that
# section C of TEST_PLAN.md is about: HTTP status -> APIError, and probe outcome
# -> the sentence the user reads. Needs no server and no token; every input here
# is constructed.
#
# Why this exists. The regression it guards already shipped once: every call site
# threw the response away and decoded the body as the success type, so a 401
# arrived as "The data couldn't be read because it is missing" — data loss
# wording for an auth failure. A build cannot catch that coming back, because
# the wrong version compiles perfectly.
#
# It cannot check that every request routes through `send`. That is structural,
# so it is a grep at the end rather than an assertion in Swift.
#
# Usage: scripts/checks/connection-check.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$REPO/OllamaSearch"

D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

cat > "$D/main.swift" <<'SWIFT'
import Foundation

// Same rationale as decode-check.sh: compiled at -O, a failed `precondition`
// traps without printing its message, so a real failure arrives as
// "Trace/BPT trap: 5" with the reason gone. Failures accumulate and the exit
// code comes from the total.
var failures = 0
func check(_ ok: Bool, _ message: @autoclosure () -> String) {
    if !ok {
        print("FAIL: \(message())")
        failures += 1
    }
}

// ------------------------------------------------------------ status -> error

// 403 is deliberately in the same bucket as 401 here. At the `send` layer the
// app is already connected, so a 403 on a request is a token/permission
// problem; the Host-header reading of 403 only applies to a probe, which is
// the other half of this file.
let statusCases: [(Int, String)] = [
    (200, "nil"), (201, "nil"), (204, "nil"),
    (401, "unauthorized"), (403, "unauthorized"),
    (500, "serverError"), (503, "serverError"), (418, "serverError"),
]
print("status -> APIError")
for (status, expected) in statusCases {
    let actual: String
    switch APIError.from(status: status, body: Data()) {
    case nil:               actual = "nil"
    case .unauthorized:     actual = "unauthorized"
    case .serverError:      actual = "serverError"
    case .invalidURL:       actual = "invalidURL"
    }
    check(actual == expected, "HTTP \(status) mapped to \(actual), expected \(expected)")
    print("  \(status) -> \(actual)")
}

// A success status must never produce an error, whatever the body holds. This
// is the actual shape of the old bug: a body that does not match the success
// type used to become a decode error rather than being passed through.
check(APIError.from(status: 200, body: Data(#"{"detail":"nonsense"}"#.utf8)) == nil,
      "a 2xx with an unexpected body must not become an error")

// mira-core sends {"detail": "..."} — that text is the whole point of showing a
// server error, so losing it would leave only "Server error 500".
let detailed = APIError.from(status: 500, body: Data(#"{"detail":"model failed to load"}"#.utf8))
check(detailed == .serverError("model failed to load"),
      "the server's own detail must survive: got \(String(describing: detailed))")
// ...and a body that is not that envelope must still name the status.
check(APIError.from(status: 500, body: Data("<html>502 Bad Gateway</html>".utf8))
        == .serverError("Server error 500"),
      "a non-JSON error body must fall back to the status, not to a decode error")
print("  500 with detail -> \(detailed?.errorDescription ?? "nil")")

// The wording that regressed. Whatever else changes, an auth failure must not
// read as data loss.
let authText = APIError.unauthorized.errorDescription ?? ""
check(authText.lowercased().contains("token") || authText.lowercased().contains("authoris"),
      "the 401 message no longer mentions the token: \(authText)")
for e in [APIError.invalidURL, .unauthorized, .serverError("x")] {
    let text = (e.errorDescription ?? "").lowercased()
    check(!text.contains("couldn't be read") && !text.contains("data couldn"),
          "\(e) reads as a decode failure: \(text)")
    check(!(e.errorDescription ?? "").isEmpty, "\(e) has no message at all")
}

// ------------------------------------------------------- probe -> explanation

print("\nProbeResult -> message")
let probes: [(String, ProbeResult)] = [
    ("ok",           .ok),
    ("401",          .refused(status: 401)),
    ("403",          .refused(status: 403)),
    ("503",          .refused(status: 503)),
    ("500",          .refused(status: 500)),
    ("unreachable",  .unreachable(reason: nil)),
    ("unreachable+", .unreachable(reason: "The request timed out.")),
]
for (label, probe) in probes {
    let msg = probe.failureMessage(target: "mira.example.ts.net")
    print("  \(label) -> \(msg ?? "nil (no error)")")
    if case .ok = probe {
        check(msg == nil, "a successful probe must produce no error message")
        continue
    }
    guard let msg else {
        check(false, "\(label) produced no message — a failure with nothing to show "
                   + "is how a connection silently does nothing")
        continue
    }
    check(msg.contains("mira.example.ts.net"),
          "\(label) does not name the address the user typed: \(msg)")
    check(!msg.lowercased().contains("couldn't be read"),
          "\(label) reads as a decode failure: \(msg)")
}

// The three that must stay distinguishable. Each sends the user somewhere
// different, and collapsing any two of them is the failure this whole type
// exists to prevent.
let m401 = ProbeResult.refused(status: 401).failureMessage() ?? ""
let m403 = ProbeResult.refused(status: 403).failureMessage() ?? ""
let m503 = ProbeResult.refused(status: 503).failureMessage() ?? ""
let mDown = ProbeResult.unreachable(reason: nil).failureMessage() ?? ""
check(m401.lowercased().contains("token"), "401 must point at the token: \(m401)")
check(m403.lowercased().contains("allowed_hosts"),
      "403 must point at allowed_hosts, not at the token or the network: \(m403)")
check(m503.lowercased().contains("starting"), "503 must say the server is starting: \(m503)")
check(mDown.lowercased().contains("could not reach"),
      "an unreachable server must name the connection: \(mDown)")
check(Set([m401, m403, m503, mDown]).count == 4,
      "two of the four connection failures now read the same")

// Without a target, the copy still has to be a sentence about something.
check(!(ProbeResult.refused(status: 401).failureMessage() ?? "").hasPrefix(" "),
      "the no-target message starts with a gap where the subject should be")
check((ProbeResult.unreachable(reason: "boom").failureMessage() ?? "").contains("boom"),
      "the underlying URLError reason is dropped")

// ---------------------------------------------------------- probe -> banner
//
// The banner is the other channel: a strip across the top of a conversation
// while the app is reconnecting, not the settings sheet. Two rules make it
// different from failureMessage, and both are load-bearing.
//
// First, it is short. The sheet's 403 copy is two sentences and names a file, a
// setting and a restart; that is right for someone already in the settings and
// wrong for a caption-sized strip, which truncates. Second, it returns nil for
// the states the reconnect loop's own progress copy already covers, so the
// caller can fall back rather than print a second phrasing of "starting up".

print("\nProbeResult -> bannerMessage")
let banners: [(String, ProbeResult, Bool)] = [
    ("ok",           .ok,                          false),
    ("401",          .refused(status: 401),        true),
    ("403",          .refused(status: 403),        true),
    ("503",          .refused(status: 503),        false),
    ("500",          .refused(status: 500),        true),
    ("unreachable",  .unreachable(reason: nil),    false),
]
for (label, probe, expectMessage) in banners {
    let msg = probe.bannerMessage
    print("  \(label) -> \(msg ?? "nil (caller falls back)")")
    check((msg != nil) == expectMessage,
          "\(label) bannerMessage was \(msg == nil ? "nil" : "set"), expected the opposite")
    guard let msg else { continue }
    // One line of .caption on the narrowest supported iPhone is roughly 60
    // characters; the banner allows two. Past this the sentence is being
    // written for a sheet, not for a strip, and the actionable half is what
    // gets cut.
    check(msg.count <= 70, "\(label) banner copy is \(msg.count) chars, too long to read: \(msg)")
}

// The one the whole reconnect change exists for: a 403 must send the user to
// mira.yaml on the first probe, not to their Wi-Fi.
let b403 = ProbeResult.refused(status: 403).bannerMessage ?? ""
check(b403.contains("allowed_hosts"), "the 403 banner must name allowed_hosts: \(b403)")
// Edge case (d) of the spec: a missing token and a refused host are different
// fixes and must not share copy in either channel.
check(ProbeResult.refused(status: 401).bannerMessage != ProbeResult.refused(status: 403).bannerMessage,
      "401 and 403 now read the same in the banner")
// 503 falling back is what keeps "still starting up" saying it once.
check(ProbeResult.refused(status: 503).bannerMessage == nil,
      "503 must fall back to the reconnect loop's own copy, not add a second phrasing")

if failures > 0 {
    print("\nFAILED — \(failures) assertion(s) above")
    exit(1)
}
print("\nOK")
SWIFT

swiftc -O -o "$D/connectioncheck" \
  "$APP/Shared/Networking/ConnectionErrors.swift" \
  "$D/main.swift" 2>&1 | grep -v "^$" || true

"$D/connectioncheck"

# ---------------------------------------------------------------- structural

# `send` inspects the status before anything is decoded. A call site that goes
# straight to the session bypasses it and brings the original bug back one
# endpoint at a time. Five are expected and deliberate:
#   send()              — the one that maps status to APIError
#   health()            — wants the raw 200/503 rather than an error
#   isHealthy(at:)      — same, for an arbitrary URL
#   probeDetailed()     — reports the status as ProbeResult
#   probeToken()        — same, against a guarded route
# A sixth is not automatically wrong, but it needs a reason. Update the count
# here when you add one, and say why in the commit.
DIRECT=$(grep -c "session\.data(for:\|URLSession\.shared\.data(for:\|session\.bytes(for:" \
  "$APP/Shared/Networking/APIClient.swift")
echo
echo "direct session calls in APIClient.swift: $DIRECT (expected 6)"
if [ "$DIRECT" -ne 6 ]; then
  echo "FAIL: a request may now bypass send(), which is what let a 401 decode as data loss"
  exit 1
fi
echo "OK"
