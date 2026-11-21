#!/bin/bash
# Device test: does the chat survive a connection that goes silent mid-reply?
#
# Runs ConnectionDropUITests on the wired iPhone. About 5 s after the phone's
# POST /chat reaches the server, this script freezes the mira-mlx ENGINE process
# (SIGSTOP; never server.py) for FREEZE seconds (default 25, hard cap 30), then
# thaws it (SIGCONT). A trap thaws it on any exit, so it can never stay frozen.
# Afterwards it checks /health reports backend_ready.
#
# Shared server: ask every other Claude session first and wait for "clear".
# Needs no token. Optional env: DEVICE, MIRA_URL, FREEZE.
#
# The phone must be wired, unlocked and awake, with Mira paired and connected.
# The test leaves one throwaway conversation titled "DROPTEST…" on the server;
# delete it from the app's sidebar.

set -u
DEVICE="${DEVICE:-00008150-0005255614F8C01C}"
MIRA_URL="${MIRA_URL:-https://miguels-macbook-pro.tail51ad7d.ts.net:8443}"
FREEZE="${FREEZE:-25}"
[ "$FREEZE" -le 30 ] || { echo "FREEZE capped at 30 s"; exit 2; }
LOG="$HOME/Library/Application Support/Mira/logs/server.log"
cd "$(dirname "$0")/.." || exit 1

engine_pid() { pgrep -f "core.inference.mira_mlx_server" | head -1; }
ready() { curl -s --max-time 5 "$MIRA_URL/health" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("backend_ready"))' 2>/dev/null; }

PID=$(engine_pid)
[ -n "$PID" ] || { echo "engine process not found"; exit 2; }
[ "$(ready)" = "True" ] || { echo "server not ready before the test (backend_ready=$(ready))"; exit 2; }
xcrun devicectl device info lockState --device "$DEVICE" >/dev/null 2>&1 || { echo "iPhone not reachable"; exit 2; }

thaw() { kill -CONT "$PID" 2>/dev/null; }
trap thaw EXIT INT TERM

base=$(grep -c "POST /chat" "$LOG")
OUT=$(mktemp /tmp/claude_dropdrop.XXXXXX)

xcodebuild test -scheme OllamaSearch -destination "id=$DEVICE" \
  -only-testing:MiraUITests/ConnectionDropUITests/testChatSurvivesFrozenConnection \
  -allowProvisioningUpdates >"$OUT" 2>&1 &
XB=$!

# Wait (up to 15 min: first run builds and installs) for the phone's chat request.
for _ in $(seq 450); do
  [ "$(grep -c "POST /chat" "$LOG")" -gt "$base" ] && break
  kill -0 "$XB" 2>/dev/null || { echo "xcodebuild ended before any chat request"; tail -20 "$OUT"; exit 2; }
  sleep 2
done
[ "$(grep -c "POST /chat" "$LOG")" -gt "$base" ] || { echo "no chat request seen"; kill "$XB" 2>/dev/null; exit 2; }

sleep 5
echo "freezing engine $PID for $FREEZE s at $(date +%T)"
kill -STOP "$PID"
sleep "$FREEZE"
thaw
echo "thawed at $(date +%T)"

wait "$XB"; rc=$?
grep -E "DROPTEST|Test Case .*(passed|failed)|error:|XCTAssert|TEST (SUCCEEDED|FAILED)" "$OUT"
echo "xcodebuild exit=$rc"

for _ in $(seq 30); do [ "$(ready)" = "True" ] && break; sleep 2; done
echo "after: backend_ready=$(ready)"
grep -i "evict\|error\|wedge\|stall\|503" "$LOG" | tail -5
rm -f "$OUT"
exit "$rc"
