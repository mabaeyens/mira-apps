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

# The phone must be reachable and unlocked.
if ! xcrun devicectl device info lockState --device "$DEVICE" >/dev/null 2>&1; then
  echo "iPhone $DEVICE not reachable over the wire"; exit 2
fi

fail=0
TESTS="${TESTS:-testSleepingShowsQuietBannerNotOffline testFocusingComposerWakesEngine testFirstMessageAfterSleepCompletes}"
for t in $TESTS; do
  echo "=== $t"
  sleep_engine
  start=$(date +%s)
  xcodebuild test -scheme OllamaSearch -destination "id=$DEVICE" \
    -only-testing:"MiraUITests/EngineLifecycleUITests/$t" -allowProvisioningUpdates 2>&1 \
    | grep -E "Test Case .*(passed|failed)|error:|TEST (SUCCEEDED|FAILED)|XCTAssert"
  rc=${PIPESTATUS[0]}
  echo "    exit=$rc  elapsed=$(( $(date +%s) - start ))s  server engine_state=$(state)"
  [ "$rc" -eq 0 ] || fail=1
done

# Leave the server as found: awake is the default for a tester returning to work.
[ "$fail" -eq 0 ] && echo "ALL PASSED" || echo "FAILURES (see above)"
exit "$fail"
