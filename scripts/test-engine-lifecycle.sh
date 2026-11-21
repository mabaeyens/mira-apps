#!/bin/bash
# Device test for the mira-core engine lifecycle (idle unload / wake).
#
# Puts the engine to sleep, runs one XCUITest on the wired iPhone, then checks
# the server state. Needs no Mac focus: everything is xcodebuild + curl.
#
# Required env (export them yourself; this script never reads a credentials file):
#   MIRA_URL    server base URL, e.g. http://192.168.1.20:8000
#   MIRA_TOKEN  bearer token for the authenticated /engine routes
# Optional:
#   DEVICE      iPhone UDID (default: iPhone Miguel)
#
# The iPhone must be wired, unlocked and awake for the whole run, with Mira
# installed, paired and connected to MIRA_URL. The server needs
# engine_idle_unload_minutes > 0.

set -u
DEVICE="${DEVICE:-00008150-0005255614F8C01C}"
: "${MIRA_URL:?export MIRA_URL}"
: "${MIRA_TOKEN:?export MIRA_TOKEN}"
cd "$(dirname "$0")/.." || exit 1

auth=(-H "Authorization: Bearer $MIRA_TOKEN")
state() { curl -s --max-time 5 "$MIRA_URL/health" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("engine_state","off"))' 2>/dev/null; }

sleep_engine() {
  local s; s=$(state)
  if [ "$s" = "off" ] || [ -z "$s" ]; then echo "engine lifecycle is off or server unreachable (state='$s')"; exit 2; fi
  if [ "$s" = "waking" ]; then for _ in $(seq 60); do sleep 2; [ "$(state)" = "running" ] && break; done; fi
  if [ "$(state)" = "running" ]; then
    local code; code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X POST "${auth[@]}" "$MIRA_URL/engine/unload")
    [ "$code" = "200" ] || { echo "unload returned HTTP $code (409 = busy or lifecycle off)"; exit 2; }
  fi
  for _ in $(seq 30); do [ "$(state)" = "sleeping" ] && return 0; sleep 1; done
  echo "engine never reached sleeping (state=$(state))"; exit 2
}

# Make sure the engine is up (for the Unload now tests).
wake_engine() {
  local s; s=$(state)
  if [ "$s" = "off" ] || [ -z "$s" ]; then echo "engine lifecycle is off or server unreachable (state='$s')"; exit 2; fi
  if [ "$s" = "sleeping" ]; then curl -s -o /dev/null --max-time 300 -X POST "${auth[@]}" "$MIRA_URL/engine/wake"; fi
  for _ in $(seq 150); do [ "$(state)" = "running" ] && return 0; sleep 2; done
  echo "engine never reached running (state=$(state))"; exit 2
}

# Hold a long chat open from a second client, so POST /engine/unload answers 409.
# Uses its own throwaway conversation, deleted again in stop_busy.
busy_conv=""; busy_pid=""
start_busy() {
  busy_conv=$(curl -s --max-time 10 -X POST "${auth[@]}" "$MIRA_URL/conversations" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])' 2>/dev/null)
  [ -n "$busy_conv" ] || { echo "could not create the busy conversation"; exit 2; }
  curl -s -N --max-time 900 -X POST "${auth[@]}" -F "conversation_id=$busy_conv" \
    -F "message=Count from 1 to 5000, one number per line, and write nothing else." \
    "$MIRA_URL/chat" >/dev/null 2>&1 &
  busy_pid=$!
  # Wait until the server really is busy: unload must now refuse.
  for _ in $(seq 20); do
    local code; code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X POST "${auth[@]}" "$MIRA_URL/engine/unload")
    [ "$code" = "409" ] && return 0
    [ "$code" = "200" ] && { echo "busy chat did not hold the engine (unload succeeded)"; stop_busy; exit 2; }
    sleep 1
  done
  echo "server never became busy"; stop_busy; exit 2
}
stop_busy() {
  if [ -n "$busy_pid" ]; then kill "$busy_pid" 2>/dev/null; wait "$busy_pid" 2>/dev/null; fi
  curl -s -o /dev/null --max-time 10 -X POST "${auth[@]}" -H "Content-Type: application/json" -d "{\"conversation_id\": \"$busy_conv\"}" "$MIRA_URL/cancel"
  [ -n "$busy_conv" ] && curl -s -o /dev/null --max-time 10 -X DELETE "${auth[@]}" "$MIRA_URL/conversations/$busy_conv"
  busy_pid=""; busy_conv=""
}
trap 'stop_busy' EXIT

# The phone must be reachable and unlocked.
if ! xcrun devicectl device info lockState --device "$DEVICE" >/dev/null 2>&1; then
  echo "iPhone $DEVICE not reachable over the wire"; exit 2
fi

fail=0
TESTS="${TESTS:-testSleepingShowsQuietBannerNotOffline testFocusingComposerWakesEngine testFirstMessageAfterSleepCompletes testUnloadNowPutsEngineToSleep testUnloadNowWhileBusyShowsBusyMessage}"
for t in $TESTS; do
  echo "=== $t"
  case "$t" in
    testUnloadNowWhileBusy*) wake_engine; start_busy ;;
    testUnloadNow*)          wake_engine ;;
    *)                       sleep_engine ;;
  esac
  start=$(date +%s)
  xcodebuild test -scheme OllamaSearch -destination "id=$DEVICE" \
    -only-testing:"MiraUITests/EngineLifecycleUITests/$t" -allowProvisioningUpdates 2>&1 \
    | grep -E "Test Case .*(passed|failed)|error:|TEST (SUCCEEDED|FAILED)|XCTAssert"
  rc=${PIPESTATUS[0]}
  echo "    exit=$rc  elapsed=$(( $(date +%s) - start ))s  server engine_state=$(state)"
  [ "$rc" -eq 0 ] || fail=1
  stop_busy
done

# Leave the server as found: awake is the default for a tester returning to work.
[ "$fail" -eq 0 ] && echo "ALL PASSED" || echo "FAILURES (see above)"
exit "$fail"
