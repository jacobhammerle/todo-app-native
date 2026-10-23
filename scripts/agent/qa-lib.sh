#!/usr/bin/env bash
# Helpers shared by the QA swarm lane and report scripts. Source it; do
# not run it. Builds on scripts/expo-simulator/lib.sh (eas, start_session,
# wait_for_session, json_field, set_output, fmt_dur, app_id).

# shellcheck disable=SC1091
. scripts/expo-simulator/lib.sh

# --no-install: run the copy in node_modules and fail loudly when it is
# missing, instead of fetching a floating version from the registry.
evidence_tool() { npx --no-install eas-simulator-evidence "$@"; }

# Line 1 of a verdict file decides the lane result, and agents do not
# always write it cleanly ("PASS: no — FAIL: ..." was seen). The package
# collapses a chain of leading keywords to the last one and turns a PASS
# line that still mentions FAIL into a FAIL.
normalize_verdict() { evidence_tool verdict "$1"; }
verdict_badge() { evidence_tool verdict "$1" --badge; }

# load_argent_session -> an argent session's connection config
# (ARGENT_TOOLS_URL / ARGENT_AUTH_TOKEN) lands in .env.eas-simulator;
# exporting it routes every local `argent run` to the session's remote
# tool-server. Falls back to the session's remoteConfig from simulator:get.
load_argent_session() {
  set -a
  # shellcheck disable=SC1091
  . ./.env.eas-simulator
  set +a
  if [ -z "${ARGENT_TOOLS_URL:-}" ] || [ -z "${ARGENT_AUTH_TOKEN:-}" ]; then
    eval "$(eas simulator:get --json --non-interactive | node -e "
      let d = '';
      process.stdin.on('data', c => d += c);
      process.stdin.on('end', () => {
        const found = {};
        (function walk(o) {
          if (!o || typeof o !== 'object') return;
          for (const [k, v] of Object.entries(o)) {
            if ((k === 'ARGENT_TOOLS_URL' || k === 'ARGENT_AUTH_TOKEN') && typeof v === 'string') found[k] = v;
            else walk(v);
          }
        })(JSON.parse(d.slice(d.indexOf('{'))));
        for (const [k, v] of Object.entries(found)) console.log(\`export \${k}=\${JSON.stringify(v)}\`);
      });
    ")"
  fi
  if [ -z "${ARGENT_TOOLS_URL:-}" ] || [ -z "${ARGENT_AUTH_TOKEN:-}" ]; then
    echo "argent connection config not found in .env.eas-simulator or simulator:get."
    exit 1
  fi
  export ARGENT_TOOLS_URL ARGENT_AUTH_TOKEN
}

# argent_device -> exports UDID, the session's iOS simulator. The output
# is captured first: under set -e + pipefail an empty grep would kill the
# script before the message below.
argent_device() {
  local attempt devices=""
  for attempt in 1 2 3 4; do
    devices=$(bash scripts/agent/argent.sh run list-devices 2>&1 || true)
    echo "list-devices (attempt ${attempt}):"
    echo "$devices"
    if echo "$devices" | grep -qE '"udid" *: *"[^"]+"'; then
      break
    fi
    sleep 15
  done
  UDID=$(echo "$devices" | grep -oE '"udid" *: *"[^"]+"' | head -n 1 | sed -E 's/.*"([^"]+)"$/\1/' || true)
  if [ -z "$UDID" ]; then
    echo "No device udid in the argent session's list-devices output (see above)."
    exit 1
  fi
  export UDID
  echo "argent session device: $UDID"
}

# wait_for_home "<marker text>" -> deterministic floor beneath the AI
# agent: poll describe (up to six times) until the marker is in the UI
# tree, relaunching the app once if it stays away; the last tree goes to
# /tmp/home-snapshot.txt, and a missing marker exits 1. Needs UDID
# (argent_device) and APP_ID. Odd attempts pass --bundleId, even attempts
# do not, in case one form is rejected.
wait_for_home() {
  local marker=$1 attempt snapshot=""
  for attempt in 1 2 3 4 5 6; do
    if [ $((attempt % 2)) -eq 1 ]; then
      snapshot=$(bash scripts/agent/argent.sh run describe --udid "$UDID" --bundleId "$APP_ID" 2>&1 || true)
    else
      snapshot=$(bash scripts/agent/argent.sh run describe --udid "$UDID" 2>&1 || true)
    fi
    if echo "$snapshot" | grep -q "$marker"; then
      break
    fi
    echo "Home screen not visible yet (attempt ${attempt})."
    if [ "$attempt" -eq 3 ]; then
      echo "Relaunching the app once..."
      bash scripts/agent/argent.sh run restart-app --udid "$UDID" --bundleId "$APP_ID" >/tmp/relaunch.txt 2>&1 || true
      sleep 5
    fi
    sleep 5
  done
  echo "$snapshot" | tee /tmp/home-snapshot.txt
  if ! echo "$snapshot" | grep -q "$marker"; then
    echo "❌ Home screen ('${marker}') not visible after launch and one relaunch."
    [ -d evidence ] && cp /tmp/home-snapshot.txt evidence/home-snapshot.txt
    exit 1
  fi
}
