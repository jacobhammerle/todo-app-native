#!/usr/bin/env bash
# Shared helpers for the scripts that drive Expo Simulators. Source it; do
# not run it. Works on a laptop and inside an EAS Workflows custom job.

# One pinned eas-cli for every call: a floating @latest can change the
# experimental simulator:* commands between runs. EAS_CLI_VERSION overrides.
# 26.0.0 is the version eas-simulator-evidence 0.2.4 is checked against; the
# variable is exported so the evidence tool runs the same one.
export EAS_CLI_VERSION="${EAS_CLI_VERSION:-26.0.0}"
eas() { npx --yes "eas-cli@${EAS_CLI_VERSION}" "$@"; }

# agent-device, run through the session so its daemon URL and token are
# loaded from .env.eas-simulator. AGENT_DEVICE_VERSION overrides the pin.
export AGENT_DEVICE_VERSION="${AGENT_DEVICE_VERSION:-0.21.31}"
ad() { eas simulator:exec npx --yes "agent-device@${AGENT_DEVICE_VERSION}" "$@"; }

# The bundle identifier, from app.json so a fork edits one file.
app_id() { node -p "require('./app.json').expo.ios.bundleIdentifier"; }

# use_simulator_token -> picks the token for simulator sessions. A personal
# access token stored as the secret EXPO_TOKEN_SIMULATOR is used first when
# it is set. Otherwise the token already in the environment is used: on an
# EAS worker that is the EXPO_TOKEN every workflow run gets, on a laptop the
# eas-cli login. The worker token starts sessions on its own (the first runs
# of simulator-smoke.yml and pr-live-preview.yml on this project did exactly
# that, before the project had any secrets). A "Not authorized" from
# simulator:start means Expo Simulators is not enabled on the account the
# active token belongs to (check with `eas simulator:availability`), which
# is the one reason to set EXPO_TOKEN_SIMULATOR: a token from an account
# that has access. See SETUP.md.
use_simulator_token() {
  if [ -n "${EXPO_TOKEN_SIMULATOR:-}" ]; then
    export EXPO_TOKEN="$EXPO_TOKEN_SIMULATOR"
  elif [ -n "${EAS_BUILD_RUNNER:-}" ]; then
    echo "EXPO_TOKEN_SIMULATOR is not set; using the workflow run's own EXPO_TOKEN for simulator sessions."
  else
    echo "EXPO_TOKEN_SIMULATOR is not set; using the local eas-cli login for simulator sessions."
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
