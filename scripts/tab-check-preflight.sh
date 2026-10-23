#!/usr/bin/env bash
# Pre-demo check for /tab-check. Run this a few minutes before the demo.
#
# Usage: scripts/tab-check-preflight.sh [SESSION_ID]
#
#   1. Checks node, npx and curl are on PATH.
#   2. Warms the npx cache for the pinned eas-cli and agent-device versions,
#      so the demo does not download anything.
#   3. Confirms eas-cli is logged in.
#   4. Resolves the live session (scripts/tab-check-session.sh) and probes the
#      session's endpoint.
#   5. Starts scripts/tab-check-keepalive.sh in the background so the daemon
#      does not exit after 5 idle minutes (see that script). Run this script
#      right after simulator:start, not only right before the demo. This
#      runs before the app check so a failed check cannot leave the daemon
#      idle until it dies (that happened on 2026-09-16).
#   6. Confirms the app answers on the session (opens it and waits for Home,
#      retrying while the daemon's snapshot bridge warms up).
#      For this app the home screen is the Tasks tab ("Add a task").
#      agent-device sessions only; skipped with a note for other types.
# Exit non-zero on the first failing step, with the reason.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/tab-check-lib.sh

step() { printf '\n== %s\n' "$*"; }

step "1/6 tools"
for t in node npx curl; do command -v "$t" >/dev/null || { echo "missing: $t" >&2; exit 1; }; done
echo "node $(node --version), npx, curl present"

step "2/6 warm npx cache (eas-cli@$TAB_CHECK_EAS_CLI_VERSION, agent-device@$TAB_CHECK_AGENT_DEVICE_VERSION)"
eas --version
if [ "$TAB_CHECK_TYPE" = agent-device ]; then
  agent_device --version 2>/dev/null | head -1 || npx --yes "agent-device@$TAB_CHECK_AGENT_DEVICE_VERSION" --version
else
  echo "skipped agent-device (this is a '$TAB_CHECK_TYPE' session)"
fi

step "3/6 eas login"
eas whoami --non-interactive || { echo "Not logged in. Run: npx --yes eas-cli@$TAB_CHECK_EAS_CLI_VERSION login" >&2; exit 1; }

step "4/6 live session"
bash scripts/tab-check-session.sh "$@"

step "5/6 keepalive"
bash scripts/tab-check-keepalive.sh --background

step "6/6 app answers on the session"
load_session_env
if [ "$TAB_CHECK_TYPE" = agent-device ]; then
  agent_device open "$TAB_CHECK_APP_ID" --relaunch >/dev/null
  if wait_text_retry "$TAB_CHECK_HOME_MARKER" 4; then
    echo "$TAB_CHECK_APP_ID launched; $TAB_CHECK_LAUNCH_TAB screen visible."
  else
    echo "$TAB_CHECK_LAUNCH_TAB screen ('$TAB_CHECK_HOME_MARKER') not visible after relaunch and 4 waits." >&2
    echo "Look at the web preview URL above; if the app is blank, run: bash scripts/tab-check-install-app.sh" >&2
    exit 1
  fi
else
  echo "skipped: opening the app is an agent-device step; this is a '$TAB_CHECK_TYPE' session."
  [ "$TAB_CHECK_TYPE" = argent ] && echo "Check it yourself with: bash scripts/agent/argent.sh run list-devices"
fi

printf '\nReady (%s / %s).' "$TAB_CHECK_PLATFORM" "$TAB_CHECK_TYPE"
if [ "$TAB_CHECK_TYPE" = agent-device ]; then
  printf ' Run /tab-check%s in Claude Code.\n' "${1:+ $1}"
else
  printf ' /tab-check drives agent-device sessions only.\n'
fi
