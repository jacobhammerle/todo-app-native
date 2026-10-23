#!/usr/bin/env bash
# Shared settings for the /tab-check scripts. Source this file; do not run it.
#
# Versions are pinned to releases that ran the demo successfully. Override with
# the TAB_CHECK_* env vars when you need a newer one.
#
# Ported from the employee-onboarding repo on 2026-10-23 for the native app.
# eas-cli 25.3.0 and agent-device 0.21.31 are the pair the native smoke test
# and QA lanes ran with that day (see scripts/expo-simulator/lib.sh).
# agent-device 0.21.x needs Node 22 or newer.

TAB_CHECK_EAS_CLI_VERSION="${TAB_CHECK_EAS_CLI_VERSION:-25.3.0}"
TAB_CHECK_AGENT_DEVICE_VERSION="${TAB_CHECK_AGENT_DEVICE_VERSION:-0.21.31}"

TAB_CHECK_APP_ID="${TAB_CHECK_APP_ID:-com.sunrisesolutions.simpletodo.native}"
# The eas.json profile whose finished builds tab-check-start.sh may install.
TAB_CHECK_BUILD_PROFILE="${TAB_CHECK_BUILD_PROFILE:-simulator}"
TAB_CHECK_ENV_FILE="${TAB_CHECK_ENV_FILE:-.env.eas-simulator}"
TAB_CHECK_RUN_DIR="${TAB_CHECK_RUN_DIR:-${TMPDIR:-/tmp}/tab-check}"

# --- which session these scripts target -------------------------------------
# tab-check-start.sh records the platform/type pair it started in
# $TAB_CHECK_RUN_DIR/session.conf, so the later scripts agree without repeating
# the flags. Precedence: environment variable, then that file, then the default
# (the iOS agent-device pair the demo has always used).
TAB_CHECK_CONF_FILE="$TAB_CHECK_RUN_DIR/session.conf"
# Returns empty (and exit 0) when the file is absent: callers run under
# `set -e -o pipefail`, where a failing sed in a pipeline would abort them.
_conf_value() {
  [ -f "$TAB_CHECK_CONF_FILE" ] || return 0
  sed -nE "s/^$1=(.*)\$/\1/p" "$TAB_CHECK_CONF_FILE" | tail -1
}
TAB_CHECK_PLATFORM="${TAB_CHECK_PLATFORM:-$(_conf_value PLATFORM)}"
TAB_CHECK_PLATFORM="${TAB_CHECK_PLATFORM:-ios}"
TAB_CHECK_TYPE="${TAB_CHECK_TYPE:-$(_conf_value TYPE)}"
TAB_CHECK_TYPE="${TAB_CHECK_TYPE:-agent-device}"

# save_session_conf — remember the pair so the later scripts pick it up.
save_session_conf() {
  mkdir -p "$TAB_CHECK_RUN_DIR"
  printf 'PLATFORM=%s\nTYPE=%s\n' "$TAB_CHECK_PLATFORM" "$TAB_CHECK_TYPE" > "$TAB_CHECK_CONF_FILE"
}

# valid_platform / valid_type — reject a typo before it reaches eas-cli.
valid_platform() { case "$1" in ios|android) return 0;; *) return 1;; esac; }
valid_type() { case "$1" in agent-device|appium|argent|web-preview-only|serve-sim) return 0;; *) return 1;; esac; }

# normalize_type <type> — map the retired eas-cli name to the current one.
# eas-cli 24 calls the preview-only session 'web-preview-only'; 'serve-sim'
# is still accepted here so older notes and shell history keep working.
normalize_type() { case "$1" in serve-sim) echo web-preview-only;; *) echo "$1";; esac; }
# Applied once here, so a session.conf or env var from before the rename still
# yields a value eas-cli 24 accepts (its --type flag rejects 'serve-sim').
TAB_CHECK_TYPE="$(normalize_type "$TAB_CHECK_TYPE")"

# require_type <type> <what> — stop unless the live session is of that type.
# The tab-driving and install helpers speak agent-device only.
require_type() {
  [ "$TAB_CHECK_TYPE" = "$1" ] && return 0
  {
    echo "$2 drives the session with $1, but this session is '$TAB_CHECK_TYPE'."
    if [ "$TAB_CHECK_TYPE" = argent ]; then
      echo "For an argent session, drive it with the argent tools instead:"
      echo "  argent link \"\$ARGENT_TOOLS_URL\" --token \"\$ARGENT_AUTH_TOKEN\" --yes"
      echo "  bash scripts/agent/argent.sh run list-devices"
    fi
    echo "To go back to the default pair: bash scripts/tab-check-start.sh \"<name>\""
  } >&2
  return 1
}

# Bottom tabs in display order. Each entry is "<file-stem>|<tab label>|<text unique to that screen>".
# The marker text is used with `agent-device wait text` to prove the screen rendered.
# The native app launches on Tasks, so that tab is not pressed first.
TAB_CHECK_LAUNCH_TAB="Tasks"
TAB_CHECK_HOME_MARKER="Add a task"
TAB_CHECK_TABS=(
  "1-tasks|Tasks|Add a task"
  "2-done|Done|Completed"
  "3-admin|Admin|This installation"
)

# eas <args...> — run the pinned eas-cli.
eas() { npx --yes "eas-cli@$TAB_CHECK_EAS_CLI_VERSION" "$@"; }

# agent_device <args...> — run the pinned agent-device against the session's
# platform. Needs the AGENT_DEVICE_DAEMON_* vars from .env.eas-simulator.
agent_device() { npx --yes "agent-device@$TAB_CHECK_AGENT_DEVICE_VERSION" "$@" --platform "$TAB_CHECK_PLATFORM"; }

# wait_text_retry <marker> [attempts] — `agent-device wait text` with retries.
# Right after `open --relaunch` the daemon's iOS snapshot bridge can still be
# "preparing" (seen 2026-09-16: the wait ran 4 s after relaunch, the bridge
# reported bridge-preparation-pending, the xctest fallback was canceled, and
# the ~13 s built-in wait timed out while the app was already on Home). One
# wait is not enough; a few, spaced out, are. `wait text` takes no --timeout.
wait_text_retry() {
  local marker=$1 attempts=${2:-4} i
  for i in $(seq 1 "$attempts"); do
    if agent_device wait text "$marker" >/dev/null 2>&1; then return 0; fi
    [ "$i" -lt "$attempts" ] && { echo "  '$marker' not visible yet (attempt $i of $attempts); retrying..."; sleep 5; }
  done
  return 1
}

# argent_cli <args...> — the argent CLI, routed at the session by the
# ARGENT_TOOLS_URL / ARGENT_AUTH_TOKEN pair in the environment.
argent_cli() { bash scripts/agent/argent.sh "$@"; }

# heartbeat — one cheap command that counts as activity for this session type.
# The agent-device daemon exits after 5 idle minutes; see tab-check-keepalive.sh.
heartbeat() {
  case "$TAB_CHECK_TYPE" in
    agent-device) agent_device apps ;;
    argent)       argent_cli run list-devices ;;
    *)            eas simulator:get --id "$EAS_SIMULATOR_SESSION_ID" --json --non-interactive >/dev/null ;;
  esac
}

# session_env_keys — the dotenv keys eas-cli writes for this session type.
# Mirrors getRemoteSessionEnvironmentVariables in eas-cli's simulator/utils.js:
# agent-device gets the daemon URL + token, argent gets a tools URL and an
# optional token, appium gets a URL, web-preview-only gets nothing to drive.
session_env_keys() {
  case "$TAB_CHECK_TYPE" in
    agent-device) echo "EAS_SIMULATOR_SESSION_ID AGENT_DEVICE_DAEMON_BASE_URL AGENT_DEVICE_DAEMON_AUTH_TOKEN" ;;
    argent)       echo "EAS_SIMULATOR_SESSION_ID ARGENT_TOOLS_URL" ;;
    appium)       echo "EAS_SIMULATOR_SESSION_ID APPIUM_URL" ;;
    *)            echo "EAS_SIMULATOR_SESSION_ID" ;;
  esac
}

# session_env_optional_keys — keys that may legitimately be absent.
session_env_optional_keys() {
  case "$TAB_CHECK_TYPE" in
    argent) echo "ARGENT_AUTH_TOKEN" ;;
  esac
}

# dotenv_value <key> — read one value out of the session dotenv. Empty and
# exit 0 when the file is absent, for the same `set -e -o pipefail` reason.
dotenv_value() {
  [ -f "$TAB_CHECK_ENV_FILE" ] || return 0
  sed -nE "s/^$1=['\"]?([^'\"]*)['\"]?\$/\1/p" "$TAB_CHECK_ENV_FILE" | tail -1
}

# load_session_env — export this session type's connection variables.
load_session_env() {
  [ -f "$TAB_CHECK_ENV_FILE" ] || { echo "$TAB_CHECK_ENV_FILE not found. Run scripts/tab-check-session.sh first." >&2; return 1; }
  local k v
  for k in $(session_env_keys); do
    v=$(dotenv_value "$k")
    [ -n "$v" ] || { echo "$TAB_CHECK_ENV_FILE has no $k for a '$TAB_CHECK_TYPE' session. Run scripts/tab-check-session.sh first." >&2; return 1; }
    export "$k=$v"
  done
  for k in $(session_env_optional_keys); do
    v=$(dotenv_value "$k")
    [ -n "$v" ] && export "$k=$v"
  done
  return 0
}

# field <json> <dot.path> — print a JSON field; exit 1 if missing. Tolerates
# eas-cli banner lines before the JSON.
field() {
  node -e '
    const raw = process.argv[1];
    const start = Math.min(...["{", "["].map(c => raw.indexOf(c)).filter(i => i >= 0));
    const j = JSON.parse(raw.slice(start));
    const v = process.argv[2].split(".").reduce((o, k) => (o == null ? o : o[k]), j);
    if (v == null) process.exit(1);
    console.log(typeof v === "string" ? v : JSON.stringify(v));
  ' "$1" "$2"
}

# preview_url <session json> — the browser preview link, or empty. Sessions
# with an automation interface expose remoteConfig.webPreviewUrl; a
# web-preview-only session exposes remoteConfig.previewUrl instead. eas-cli 24
# already appends the required ?token= to both.
preview_url() {
  field "$1" remoteConfig.webPreviewUrl 2>/dev/null || field "$1" remoteConfig.previewUrl 2>/dev/null || true
}

# newest_build <platform> — print "<id> <artifact url>" for the newest finished
# $TAB_CHECK_BUILD_PROFILE build that can be installed on a remote device of that platform.
# iOS needs a simulator build (isForIosSimulator); Android just needs an archive.
newest_build() {
  local platform=$1 list
  list=$(eas build:list --platform "$platform" --status finished --build-profile "$TAB_CHECK_BUILD_PROFILE" --limit 10 --json --non-interactive 2>/dev/null) || return 1
  node -e '
    const raw = process.argv[1];
    const platform = process.argv[2];
    const b = JSON.parse(raw.slice(raw.indexOf("[")));
    const hit = b.find(x =>
      x.artifacts && x.artifacts.applicationArchiveUrl &&
      (platform === "android" || x.isForIosSimulator));
    if (!hit) process.exit(1);
    console.log(hit.id, hit.artifacts.applicationArchiveUrl);
  ' "$list" "$platform"
}
