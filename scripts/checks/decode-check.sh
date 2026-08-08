#!/bin/bash
# Prove the app's model/backend/memory types still decode what the live server
# sends.
#
# Compiles ModelInfo.swift, Backend.swift and SystemMemory.swift standalone
# against real /models, /backends and /hardware payloads, so a server-side key
# rename fails here instead of silently emptying a picker at runtime. Also
# asserts the invariants that have broken before: exactly one row is active, a
# server too old to report `available` does not disable every row, every
# advisory the server can emit maps to a known case, and the states that must
# stay silent stay silent.
#
# SystemMemory is the one whose failure is silent. A renamed key in /models
# empties a picker and someone notices; a renamed key inside `system_memory`
# decodes to `.unknown`, which renders as nothing, which is indistinguishable
# from a healthy machine. The banner would simply never appear again and nothing
# would report it.
#
# Usage: scripts/checks/decode-check.sh [server-url]
#
# The token is read from the environment or from mira-core's mira.yaml and is
# never written into this file — an earlier version hardcoded it, which is a
# problem in a public repo. Nothing here echoes it.
set -euo pipefail

SERVER="${1:-http://localhost:8000}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$REPO/OllamaSearch"
MIRA_YAML="${MIRA_YAML:-$HOME/Projects/mira-core/mira.yaml}"

TOKEN="${MIRA_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -f "$MIRA_YAML" ]; then
  TOKEN=$(sed -n 's/^auth_token:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' "$MIRA_YAML" | head -1)
fi
if [ -z "$TOKEN" ]; then
  echo "No token. Set MIRA_TOKEN, or point MIRA_YAML at a mira.yaml that has auth_token." >&2
  exit 1
fi

D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

curl -sf -H "Authorization: Bearer $TOKEN" "$SERVER/models"   -o "$D/models.json"
curl -sf -H "Authorization: Bearer $TOKEN" "$SERVER/backends" -o "$D/backends.json"

# A server old enough to predate /hardware must not fail the whole check — the
# app treats a missing endpoint the same way it treats a missing field, and so
# does this. The literal shapes below carry the interesting cases anyway; the
# live fetch is here to catch a key rename, which only the real payload shows.
if ! curl -sf -H "Authorization: Bearer $TOKEN" "$SERVER/hardware" -o "$D/hardware.json"; then
  echo "note: $SERVER/hardware did not answer — checking the literal shapes only"
  echo '{}' > "$D/hardware.json"
fi

cat > "$D/main.swift" <<'SWIFT'
import Foundation

// Passed in rather than hardcoded so the script works from a temp dir.
let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// Not `precondition`: this is compiled at -O, where Swift traps on a failed
// precondition without printing the message. A real failure arrived as
// "Trace/BPT trap: 5" with the reason gone — confirmed by mutating
// SystemMemory.swift three ways and watching all three fail namelessly. A check
// that cannot say what broke costs more time than it saves.
//
// Failures accumulate rather than exiting at the first one, so a server-side
// rename that breaks four assertions is reported as four lines, not one at a
// time across four runs.
var failures = 0
func check(_ ok: Bool, _ message: @autoclosure () -> String) {
    if !ok {
        print("FAIL: \(message())")
        failures += 1
    }
}

let modelsData = try Data(contentsOf: URL(fileURLWithPath: "\(dir)/models.json"))
let library = try JSONDecoder().decode(ModelsResponse.self, from: modelsData)
print("ModelsResponse decoded")
print("  backends: \(library.backends.count)")
for b in library.backends {
    print("    \(b.backend) available=\(b.available) models=\(b.models.count) detail=\(b.detail)")
}
print("  active: \(library.active.backend) / \(library.active.modelId)")

let backendsData = try Data(contentsOf: URL(fileURLWithPath: "\(dir)/backends.json"))
let presets = try JSONDecoder().decode([BackendPreset].self, from: backendsData)
print("\n[BackendPreset] decoded: \(presets.count)")
for p in presets {
    let mark = p.active ? "*" : " "
    print("  \(mark) \(p.id) avail=\(p.available) backendLabel=\(Backend.label(for: p.backend)) \(p.detail)")
}
let active = presets.filter(\.active)
print("\nactive rows: \(active.count)  (must be exactly 1)")
check(active.count == 1, "the running model must appear exactly once")

// Old-server compatibility: no `available`/`detail` keys at all.
let legacy = #"[{"id":"a","label":"L","backend":"omlx","model":"m","context_window":1024,"active":false}]"#
let old = try JSONDecoder().decode([BackendPreset].self, from: Data(legacy.utf8))
print("legacy preset decodes, available defaults to \(old[0].available)")
check(old[0].available, "a server that does not report availability must not disable every row")

// ---------------------------------------------------------------- /hardware

let hardwareData = try Data(contentsOf: URL(fileURLWithPath: "\(dir)/hardware.json"))
let hardware = try JSONDecoder().decode(HardwareInfo.self, from: hardwareData)
print("\nHardwareInfo decoded")
if let sm = hardware.systemMemory {
    let banner = sm.advisory.advisoryText == nil ? "silent" : "banner"
    print("  advisory: \(sm.advisory) -> \(banner)")
    print("  ceiling=\(sm.ceilingBytes.map(String.init) ?? "nil")"
        + " available=\(sm.availableBytes.map(String.init) ?? "nil")"
        + " compressor=\(sm.compressorBytes.map(String.init) ?? "nil")"
        + " source=\(sm.source ?? "nil")")
} else {
    print("  system_memory absent — legal (old server, non-mira-mlx, or still starting)")
}

// The five strings the server can emit, from mira-core core/hardware.py:460-497.
// Hardcoded here on purpose: that is two lists, and two lists is the point —
// this is what fails when the server grows a sixth one and the app silently
// starts reading it as `unknown`.
let serverAdvisories = ["ok", "busy", "evicted", "critical", "unknown"]
let mustStaySilent: Set<String> = ["ok", "busy", "unknown"]
print("\nadvisory coverage")
check(Set(MemoryAdvisory.allCases.map(\.rawValue)) == Set(serverAdvisories),
      "the app's cases \(MemoryAdvisory.allCases.map(\.rawValue).sorted()) and the server's "
    + "\(serverAdvisories.sorted()) have drifted apart")
for name in serverAdvisories {
    let one = try JSONDecoder().decode(SystemMemory.self,
                                       from: Data(#"{"advisory":"\#(name)"}"#.utf8))
    check(one.advisory.rawValue == name,
          "the server can emit \(name) and the app decodes it as \(one.advisory) — "
        + "an advisory the app does not know becomes unknown, which renders nothing")
    let shows = one.advisory.advisoryText != nil
    check(shows == !mustStaySilent.contains(name),
          "\(name) must \(mustStaySilent.contains(name) ? "not " : "")produce a banner")
    print("  \(name) -> \(shows ? "banner" : "silent")")
}

// Absence in all its shapes must PASS, not fail. An older server, a non-mira-mlx
// backend and a backend still starting all legitimately send these, and a check
// that rejected them would fail on every machine that is not this one.
let shapes: [(String, String, Bool)] = [
    ("system_memory absent",     #"{"total_ram_gb":32.0}"#,                        false),
    ("system_memory null",       #"{"system_memory":null}"#,                       false),
    ("system_memory {}",         #"{"system_memory":{}}"#,                         true),
    ("advisory missing",         #"{"system_memory":{"ceiling_bytes":1}}"#,        true),
    ("advisory null",            #"{"system_memory":{"advisory":null}}"#,          true),
    ("advisory unrecognised",    #"{"system_memory":{"advisory":"throttled"}}"#,   true),
    ("all numerics null",        #"{"system_memory":{"advisory":"evicted","ceiling_bytes":null,"# +
                                 #""available_bytes":null,"compressor_bytes":null,"pressure_level":null}}"#, true),
    // The server already sends keys the app does not declare. That must stay
    // fine — do not add them to the Swift type to make this symmetrical.
    ("undeclared server keys",   #"{"system_memory":{"advisory":"ok","mira_used_bytes":1,"# +
                                 #""self_compressed_bytes":2,"eviction_signal":true,"self_memory":{}}}"#, true),
]
print("\ndegraded shapes (all must decode)")
for (label, json, expectsMemory) in shapes {
    let h = try JSONDecoder().decode(HardwareInfo.self, from: Data(json.utf8))
    check((h.systemMemory != nil) == expectsMemory, "\(label): wrong presence")
    let advisory = h.systemMemory?.advisory
    print("  \(label) -> \(advisory.map { "\($0)" } ?? "no system_memory")")
    if label.hasPrefix("advisory") || label == "system_memory {}" {
        check(advisory == .unknown, "\(label) must read as unknown, never as health")
        check(advisory?.advisoryText == nil, "\(label) must not produce a banner")
    }
}

// ceiling_bytes is ~31e9 on a 32GB machine, which overflows Int32. It decodes
// correctly into Int on 64-bit, but a check that only ever saw small literals
// would not catch a narrowing of the type.
let big = try JSONDecoder().decode(
    SystemMemory.self, from: Data(#"{"advisory":"ok","ceiling_bytes":31000000000}"#.utf8))
check(big.ceilingBytes == 31_000_000_000, "ceiling_bytes narrowed — 32GB does not fit")
print("\nceiling_bytes 31e9 -> \(big.ceilingBytes.map(String.init) ?? "nil")")

if failures > 0 {
    print("\nFAILED — \(failures) assertion(s) above")
    exit(1)
}
print("\nOK")
SWIFT

swiftc -O -o "$D/decodecheck" \
  "$APP/Shared/Models/ModelInfo.swift" \
  "$APP/Shared/Models/Backend.swift" \
  "$APP/Shared/Models/SystemMemory.swift" \
  "$D/main.swift" 2>&1 | grep -v "^$" || true

"$D/decodecheck" "$D"
