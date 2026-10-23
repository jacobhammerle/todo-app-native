#!/usr/bin/env bash
# Shared helpers for the scripts that drive Expo Simulators. Source it; do
# not run it. Works on a laptop and inside an EAS Workflows custom job.

# One pinned eas-cli for every call: a floating @latest can change the
# experimental simulator:* commands between runs. EAS_CLI_VERSION overrides.
export EAS_CLI_VERSION="${EAS_CLI_VERSION:-25.3.0}"
eas() { npx --yes "eas-cli@${EAS_CLI_VERSION}" "$@"; }

# agent-device, run through the session so its daemon URL and token are
# loaded from .env.eas-simulator. AGENT_DEVICE_VERSION overrides the pin.
export AGENT_DEVICE_VERSION="${AGENT_DEVICE_VERSION:-0.21.31}"
ad() { eas simulator:exec npx --yes "agent-device@${AGENT_DEVICE_VERSION}" "$@"; }

# The bundle identifier, from app.json so a fork edits one file.
app_id() { node -p "require('./app.json').expo.ios.bundleIdentifier"; }

# On an EAS worker the auto-injected EXPO_TOKEN is restricted and cannot
# create simulator sessions (they are actor-gated), so a personal access
# token stored as the secret EXPO_TOKEN_SIMULATOR becomes EXPO_TOKEN. On a
# laptop the eas-cli login is used and nothing changes.
use_simulator_token() {
  if [ -n "${EXPO_TOKEN_SIMULATOR:-}" ]; then
    export EXPO_TOKEN="$EXPO_TOKEN_SIMULATOR"
  elif [ -n "${EAS_BUILD_RUNNER:-}" ]; then
    echo "EXPO_TOKEN_SIMULATOR is not set. On EAS, simulator:start needs a personal"
    echo "access token: add it as a secret env var in the production environment."
    echo "Continuing with the worker token; expect 'Not authorized' if it is restricted."
  fi
}

# json_field <path> -> reads JSON on stdin (eas-cli --json output, which may
# carry a text preamble) and prints the dotted field; exit 1 when missing.
json_field() {
  node -e "
    let d = '';
    process.stdin.on('data', c => d += c);
    process.stdin.on('end', () => {
      const j = JSON.parse(d.slice(d.indexOf('{')));
      const v = process.argv[1].split('.').reduce((o, k) => (o ?? {})[k], j);
      if (v === undefined || v === null) process.exit(1);
      console.log(v);
    });
  " "$1"
}

# start_session <simulator:start args...> -> up to three attempts with a
# pause between them; prints the start JSON. Resets the dotenv first so a
# stale session id is never reused.
start_session() {
  local attempt out
  printf '# managed by eas-cli\n' > .env.eas-simulator
  for attempt in 1 2 3; do
    if out=$(eas simulator:start "$@" --json --non-interactive); then
      printf '%s\n' "$out"
      return 0
    fi
    if [ "$attempt" -eq 3 ]; then
      echo "simulator:start failed three times; giving up." >&2
      return 1
    fi
    echo "simulator:start failed (attempt ${attempt}); retrying in 30s..." >&2
    sleep 30
  done
}

# wait_for_session [session-id] -> poll simulator:get (up to 16 min) until
# the session is IN_PROGRESS with its remoteConfig; exit 1 if it stopped.
wait_for_session() {
  local i s id=()
  [ -n "${1:-}" ] && id=(--id "$1")
  for i in $(seq 1 64); do
    s=$(eas simulator:get ${id[@]+"${id[@]}"} --json --non-interactive 2>/dev/null || true)
    if echo "$s" | grep -q '"status": "IN_PROGRESS"' && echo "$s" | grep -q remoteConfig; then
      return 0
    fi
    if echo "$s" | grep -qE '"status": "(STOPPED|ERRORED)"'; then
      echo "Simulator session stopped or errored before it was ready." >&2
      return 1
    fi
    sleep 15
  done
  echo "Session not ready in time." >&2
  return 1
}

# set_output name value -> an EAS Workflows step output when running on EAS,
# a log line otherwise.
set_output() {
  if command -v set-output >/dev/null 2>&1; then
    set-output "$1" "$2"
  else
    echo "output $1=$2"
  fi
}

# fmt_dur <seconds> -> "3m 07s" or "42s".
fmt_dur() { local s=$1; if [ "$s" -ge 60 ]; then printf '%dm %02ds' $((s / 60)) $((s % 60)); else printf '%ds' "$s"; fi; }
