#!/bin/bash
# Prove the app's model/backend types still decode what the live server sends.
#
# Compiles ModelInfo.swift and Backend.swift standalone against real /models and
# /backends payloads, so a server-side key rename fails here instead of silently
# emptying a picker at runtime. Also asserts the two invariants that have broken
# before: exactly one row is active, and a server too old to report `available`
# does not disable every row.
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

cat > "$D/main.swift" <<'SWIFT'
import Foundation

// Passed in rather than hardcoded so the script works from a temp dir.
let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

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
precondition(active.count == 1, "the running model must appear exactly once")

// Old-server compatibility: no `available`/`detail` keys at all.
let legacy = #"[{"id":"a","label":"L","backend":"omlx","model":"m","context_window":1024,"active":false}]"#
let old = try JSONDecoder().decode([BackendPreset].self, from: Data(legacy.utf8))
print("legacy preset decodes, available defaults to \(old[0].available)")
precondition(old[0].available, "a server that does not report availability must not disable every row")

print("\nOK")
SWIFT

swiftc -O -o "$D/decodecheck" \
  "$APP/Shared/Models/ModelInfo.swift" \
  "$APP/Shared/Models/Backend.swift" \
  "$D/main.swift" 2>&1 | grep -v "^$" || true

"$D/decodecheck" "$D"
