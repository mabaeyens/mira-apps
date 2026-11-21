#!/bin/bash
# Simulator tests for "the chat screen always shows something, and says what is
# going on". Needs no real server, no token and no phone: it starts
# scripts/mira-stub-server.py on 127.0.0.1:18765, runs the UI tests against it
# in an iPhone simulator, and stops the stub again.
#
# The stub can do what the real server cannot be asked to: go silent in the
# middle of a reply and still save the turn, so the dropped-connection states
# (no data, connection lost, waiting for the reply, reply restored) are tested
# without switching Wi-Fi off.
#
# Optional env:
#   SIM     simulator UDID (default: an iPhone 18 Pro; not the screenshot simulator)
#   TESTS   space-separated "Class" or "Class/testName" (default: both classes)
#   RESULT  path for the .xcresult bundle, which holds every sampled screenshot
#   LOG     path for the full xcodebuild log (default: a temp file, removed on success)

set -u
SIM="${SIM:-4F25945B-2937-4297-8610-7780AC83CE70}"
TESTS="${TESTS:-ConversationOpenUITests ChatStateUITests}"
PORT=18765
cd "$(dirname "$0")/.." || exit 1

if curl -s --max-time 2 "http://127.0.0.1:$PORT/health" >/dev/null; then
  echo "something already answers on port $PORT; stop it first"; exit 2
fi

python3 scripts/mira-stub-server.py "$PORT" &
STUB=$!
trap 'kill "$STUB" 2>/dev/null' EXIT INT TERM
for _ in $(seq 20); do
  curl -s --max-time 1 "http://127.0.0.1:$PORT/health" >/dev/null && break
  sleep 0.5
done
curl -s --max-time 2 "http://127.0.0.1:$PORT/health" >/dev/null || { echo "stub server did not start"; exit 2; }

only=()
for t in $TESTS; do only+=("-only-testing:MiraUITests/$t"); done
bundle=()
if [ -n "${RESULT:-}" ]; then rm -rf "$RESULT"; bundle=(-resultBundlePath "$RESULT"); fi

OUT="${LOG:-$(mktemp /tmp/claude_chatstates.XXXXXX)}"
xcodebuild test -project OllamaSearch.xcodeproj -scheme OllamaSearch \
  -destination "platform=iOS Simulator,id=$SIM" "${only[@]}" "${bundle[@]}" >"$OUT" 2>&1
rc=$?
grep -E "PROBE|Test Case .*(passed|failed)|error:|XCTAssert|TEST (SUCCEEDED|FAILED)|BUILD FAILED" "$OUT" | cut -c1-600
echo "xcodebuild exit=$rc"
if [ "$rc" -eq 0 ] && [ -z "${LOG:-}" ]; then rm -f "$OUT"; else echo "full log: $OUT"; fi
exit "$rc"
