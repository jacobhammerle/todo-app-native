#!/usr/bin/env bash
# Resolve the live EAS simulator session for /tab-check and write .env.eas-simulator.
#
# Usage: scripts/tab-check-session.sh [SESSION_ID]
#
# Which session it looks for depends on the platform/type pair recorded by
# scripts/tab-check-start.sh (default: iOS + agent-device). Override for one
# run with TAB_CHECK_PLATFORM / TAB_CHECK_TYPE.
#
# Resolution order:
#   1. SESSION_ID argument (explicit; no fallback if it is not live)
#   2. EAS_SIMULATOR_SESSION_ID in .env.eas-simulator
#   3. The single IN_PROGRESS session of that platform and type
# A candidate is accepted only when `simulator:get` reports status IN_PROGRESS.
# On success the dotenv is rewritten from the session's remoteConfig. Each
# session type carries different connection fields, so the keys differ:
# agent-device gets AGENT_DEVICE_DAEMON_BASE_URL + _AUTH_TOKEN, argent gets
# ARGENT_TOOLS_URL (+ ARGENT_AUTH_TOKEN), appium gets APPIUM_URL.
#
# For an agent-device session the daemon /health is probed for up to 60 s
# (12 attempts, 5 s apart) to ride out a session that is still booting.
#
# Exit 4 means the agent-device daemon inside the session has exited. That
# happens 5 min after the last agent-device command (the daemon's idle timeout;
# GET /health does not count). The session stays IN_PROGRESS and the web
# preview keeps working, but nothing can restart the daemon. Prevent it by
# running scripts/tab-check-preflight.sh (or tab-check-keepalive.sh) right
# after simulator:start; see scripts/tab-check-keepalive.sh.
#
# Exit codes: 0 ok · 1 eas-cli error · 2 no live session · 3 several live sessions · 4 daemon unreachable
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/tab-check-lib.sh

ENV_FILE=$TAB_CHECK_ENV_FILE
echo "target:   $TAB_CHECK_PLATFORM / $TAB_CHECK_TYPE"

SESSION_JSON=""
# try_session <id> — set SESSION_JSON when the session is IN_PROGRESS.
try_session() {
  local id=$1 j status
  if ! j=$(eas simulator:get --id "$id" --json --non-interactive 2>/dev/null); then
    echo "session $id: simulator:get failed (unknown id or not authenticated)"
    return 1
  fi
  status=$(field "$j" status || echo UNKNOWN)
  if [ "$status" = IN_PROGRESS ]; then
    SESSION_JSON=$j
    return 0
  fi
  echo "session $id: status $status"
  return 1
}

if [ -n "${1:-}" ]; then
  echo "Checking the session ID you passed: $1"
  try_session "$1" || { echo "That session is not live. Nothing else was tried." >&2; exit 2; }
else
  DOTENV_ID=$(dotenv_value EAS_SIMULATOR_SESSION_ID)
  if [ -n "$DOTENV_ID" ]; then
    echo "Checking the session in $ENV_FILE: $DOTENV_ID"
    try_session "$DOTENV_ID" || true
  else
    echo "$ENV_FILE has no session ID."
  fi

  if [ -z "$SESSION_JSON" ]; then
    echo "Looking for in-progress $TAB_CHECK_PLATFORM $TAB_CHECK_TYPE sessions in this project..."
    LIST=$(eas simulator:list --status in-progress --platform "$TAB_CHECK_PLATFORM" --type "$TAB_CHECK_TYPE" \
      --limit 20 --json --non-interactive 2>/dev/null) || { echo "simulator:list failed" >&2; exit 1; }
    ROWS=$(field "$LIST" sessions | node -e '
      const s = JSON.parse(require("fs").readFileSync(0, "utf8"));
      console.log(s.map(x => `${x.id}\t${x.name || "(unnamed)"}`).join("\n"));
    ')
    COUNT=$(printf '%s' "$ROWS" | grep -c . || true)
    if [ "$COUNT" -eq 0 ]; then
      echo "No live $TAB_CHECK_PLATFORM $TAB_CHECK_TYPE session found." >&2
      echo "Start one with:" >&2
      echo "  bash scripts/tab-check-start.sh \"Tab check demo\" --platform $TAB_CHECK_PLATFORM --type $TAB_CHECK_TYPE" >&2
      exit 2
    fi
    if [ "$COUNT" -gt 1 ]; then
      echo "Several live sessions found. Re-run with one of these IDs:" >&2
      printf '%s\n' "$ROWS" >&2
      exit 3
    fi
    ONLY_ID=$(printf '%s' "$ROWS" | cut -f1)
    echo "Exactly one live session: $ONLY_ID"
    try_session "$ONLY_ID" || { echo "It stopped while resolving." >&2; exit 2; }
  fi
fi

ID=$(field "$SESSION_JSON" id)
NAME=$(field "$SESSION_JSON" name || echo "(unnamed)")
PREVIEW=$(preview_url "$SESSION_JSON")

# Build the dotenv body from remoteConfig. Which fields are present identifies
# the session type, so this does not depend on __typename surviving --json.
BODY=$(node -e '
  const raw = process.argv[1];
  const start = Math.min(...["{", "["].map(c => raw.indexOf(c)).filter(i => i >= 0));
  const s = JSON.parse(raw.slice(start));
  const rc = s.remoteConfig || {};
  const out = {};
  if (rc.agentDeviceRemoteSessionUrl) {
    out.AGENT_DEVICE_DAEMON_BASE_URL = rc.agentDeviceRemoteSessionUrl;
    out.AGENT_DEVICE_DAEMON_AUTH_TOKEN = rc.agentDeviceRemoteSessionToken;
  } else if (rc.toolsUrl) {
    out.ARGENT_TOOLS_URL = rc.toolsUrl;
    if (rc.toolsAuthToken) out.ARGENT_AUTH_TOKEN = rc.toolsAuthToken;
  } else if (rc.appiumUrl) {
    out.APPIUM_URL = rc.appiumUrl;
  }
  out.EAS_SIMULATOR_SESSION_ID = s.id;
  console.log(Object.entries(out).filter(([, v]) => v != null).map(([k, v]) => `${k}='"'"'${v}'"'"'`).join("\n"));
' "$SESSION_JSON")

WANT="# Do not commit this file.
# Do not modify these values manually. They are managed by eas-cli.
# It holds configuration only for the current simulator session.

$BODY"
if [ "$(cat "$ENV_FILE" 2>/dev/null || true)" != "$WANT" ]; then
  printf '%s\n' "$WANT" > "$ENV_FILE"
  echo "Wrote $ENV_FILE for session $ID."
else
  echo "$ENV_FILE already points at session $ID."
fi

load_session_env

STARTED=$(field "$SESSION_JSON" startedAt || echo "")
# probe <base-url> <token> — the endpoint's /health status. curl already
# prints 000 when it cannot connect, so do not echo a second fallback.
probe() {
  local code
  code=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $2" "$1/health") || true
  echo "${code:-000}"
}

case "$TAB_CHECK_TYPE" in
  agent-device)
    URL=$AGENT_DEVICE_DAEMON_BASE_URL
    ATTEMPTS=${TAB_CHECK_HEALTH_ATTEMPTS:-12}
    CODE=000
    for attempt in $(seq 1 "$ATTEMPTS"); do
      CODE=$(probe "$URL" "$AGENT_DEVICE_DAEMON_AUTH_TOKEN")
      [ "$CODE" = 200 ] && break
      echo "daemon /health returned HTTP $CODE (attempt $attempt/$ATTEMPTS)"
      [ "$attempt" -lt "$ATTEMPTS" ] && sleep 5
    done
    if [ "$CODE" != 200 ]; then
      {
        echo "daemon $URL/health returned HTTP $CODE — session $ID is IN_PROGRESS (started $STARTED) but its agent-device daemon has exited."
        echo "The daemon exits 5 min after the last agent-device command; the web preview keeps working, and nothing can restart the daemon."
        echo "For the demo: start a new session, then run scripts/tab-check-preflight.sh <id> right away — it starts a keepalive that sends a command every 2 min."
      } >&2
      exit 4
    fi
    echo "daemon:   $URL  (HTTP 200)"
    ;;
  argent)
    # Best-effort only: the argent tool-server's health route is not part of
    # the demo's proven path, so a non-200 is reported, not fatal.
    CODE=$(probe "$ARGENT_TOOLS_URL" "${ARGENT_AUTH_TOKEN:-}")
    echo "tools:    $ARGENT_TOOLS_URL  (HTTP $CODE)"
    [ "$CODE" = 200 ] || echo "note:     argent tool-server did not answer /health with 200; try 'bash scripts/agent/argent.sh run list-devices'."
    ;;
  *)
    echo "note:     '$TAB_CHECK_TYPE' sessions are not driven by these scripts; connection values are in $ENV_FILE."
    ;;
esac

echo "session:  $ID  \"$NAME\"  IN_PROGRESS"
[ -n "$PREVIEW" ] && echo "preview:  $PREVIEW"
exit 0
