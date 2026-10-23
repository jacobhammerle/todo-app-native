#!/usr/bin/env bash
# Keep the agent-device daemon of the live EAS simulator session alive for /tab-check.
#
# Usage: scripts/tab-check-keepalive.sh [SESSION_ID]      run in the foreground
#        scripts/tab-check-keepalive.sh --background [ID]  start detached; prints pid + log path
#        scripts/tab-check-keepalive.sh --status           show whether one is running
#        scripts/tab-check-keepalive.sh --stop             stop the background one
#
# Why: the agent-device daemon inside an EAS simulator session exits on its
# own after 5 minutes without an agent-device command (observed 2026-08-27 and
# 2026-08-28). The session stays IN_PROGRESS and the web preview keeps working,
# but ngrok answers HTTP 502 for the daemon and nothing can restart it. GET
# /health does not count as activity. A real command does, so this script runs
# `agent-device apps` every TAB_CHECK_KEEPALIVE_INTERVAL_S seconds (default 120).
#
# It stops by itself when the session is no longer IN_PROGRESS, when the
# daemon has been unreachable for 3 heartbeats, or when .env.eas-simulator is
# switched to another session.
#
# Exit codes: 0 session ended / stopped · 1 setup error · 4 daemon unreachable
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/tab-check-lib.sh

INTERVAL=${TAB_CHECK_KEEPALIVE_INTERVAL_S:-120}
RUN_DIR=$TAB_CHECK_RUN_DIR
mkdir -p "$RUN_DIR"
PID_FILE=$RUN_DIR/keepalive.pid
LOG_FILE=$RUN_DIR/keepalive.log

# The pid file holds "<pid> <session id>".
running_pid() {
  local p
  p=$(cut -d' ' -f1 "$PID_FILE" 2>/dev/null || true)
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null && echo "$p"
}
running_session() { cut -d' ' -f2 "$PID_FILE" 2>/dev/null || true; }
dotenv_session() { dotenv_value EAS_SIMULATOR_SESSION_ID; }

case "${1:-}" in
  --status)
    if p=$(running_pid) && [ -n "$p" ]; then
      echo "keepalive running (pid $p), log: $LOG_FILE"
      tail -n 3 "$LOG_FILE" 2>/dev/null || true
      exit 0
    fi
    echo "keepalive not running"
    exit 1
    ;;
  --stop)
    if p=$(running_pid) && [ -n "$p" ]; then
      kill "$p" && echo "stopped keepalive (pid $p)"
    else
      echo "keepalive not running"
    fi
    rm -f "$PID_FILE"
    exit 0
    ;;
  --background)
    shift
    if [ -n "${1:-}" ]; then
      bash scripts/tab-check-session.sh "$1"
      set --
    fi
    if p=$(running_pid) && [ -n "$p" ]; then
      if [ "$(running_session)" = "$(dotenv_session)" ]; then
        echo "keepalive already running (pid $p), log: $LOG_FILE"
        exit 0
      fi
      kill "$p" 2>/dev/null || true
      echo "stopped keepalive for previous session (pid $p)"
    fi
    : > "$LOG_FILE"
    nohup bash "$0" "$@" >>"$LOG_FILE" 2>&1 &
    disown
    echo "keepalive started (pid $!), heartbeat every ${INTERVAL}s, log: $LOG_FILE"
    exit 0
    ;;
esac

if [ -n "${1:-}" ]; then
  bash scripts/tab-check-session.sh "$1"
fi
load_session_env
SESSION=$EAS_SIMULATOR_SESSION_ID
echo "$$ $SESSION" > "$PID_FILE"
trap 'rm -f "$PID_FILE"' EXIT

log() { echo "$(date -u +%FT%TZ) $*"; }
log "keepalive for session $SESSION ($TAB_CHECK_PLATFORM/$TAB_CHECK_TYPE), heartbeat every ${INTERVAL}s"

FAILS=0
BEAT=0
while :; do
  # Stop if the dotenv now points somewhere else.
  CUR=$(dotenv_session)
  if [ "$CUR" != "$SESSION" ]; then
    log "$TAB_CHECK_ENV_FILE now points at '$CUR'; stopping"
    exit 0
  fi

  if OUT=$(heartbeat 2>&1); then
    FAILS=0
    log "heartbeat ok"
  else
    FAILS=$((FAILS + 1))
    if [ "$TAB_CHECK_TYPE" = agent-device ]; then
      CODE=$(curl -sS -m 15 -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $AGENT_DEVICE_DAEMON_AUTH_TOKEN" "$AGENT_DEVICE_DAEMON_BASE_URL/health" || echo 000)
    else
      CODE="n/a"
    fi
    log "heartbeat failed ($FAILS/3), daemon /health HTTP $CODE: $(printf '%s' "$OUT" | tail -n 1)"
    if [ "$FAILS" -ge 3 ]; then
      log "daemon unreachable; giving up"
      exit 4
    fi
  fi

  # Every 5th heartbeat (~10 min) confirm the session is still IN_PROGRESS.
  BEAT=$((BEAT + 1))
  if [ $((BEAT % 5)) -eq 0 ]; then
    if J=$(eas simulator:get --id "$SESSION" --json --non-interactive 2>/dev/null); then
      STATUS=$(field "$J" status || echo UNKNOWN)
      if [ "$STATUS" != IN_PROGRESS ]; then
        log "session $SESSION is $STATUS; stopping"
        exit 0
      fi
    fi
  fi

  sleep "$INTERVAL"
done
